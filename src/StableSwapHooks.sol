// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BaseHooks} from "./BaseHooks.sol";

// TODO: Move to somewhere else, or use OZ IERC20s
interface IERC20 {
    function decimals() external view returns (uint8);
}

contract StableSwapHooks is BaseHooks {
    using SafeCast for int256;
    using SafeCast for uint256;
    using TickMath for int24;

    /// Constants

    uint256 public constant MAX_AMP = 1e6;
    uint256 public constant RATE_PRECISION = 1e18;

    // TODO: Make fee and tick spacing configurable. Current value is recommended for stable pairs
    uint24 public constant FEE = 1e2; // 0.01%
    uint256 public constant FEE_DENOMINATOR = 1e6; // 100%
    int24 public constant TICK_SPACING = 1;

    /// Immutables

    IPoolManager public immutable poolManager;
    PoolId public immutable poolId;
    uint256 public immutable rate0;
    uint256 public immutable rate1;

    /// Variables

    uint256 public amp;
    uint256 public reserves0;
    uint256 public reserves1;
    uint256 public totalShares;

    mapping(address => uint256) public sharesByUser;

    /// Errors

    error InvalidAmp();
    error InvalidPoolId();
    error InvalidInvariant();
    error InvalidRange();
    error InvalidCaller();

    /// Events

    event AmpSet(uint256 newAmp);

    /// Deployment

    constructor(uint256 initialAmp, IPoolManager manager, Currency currency0, Currency currency1) {
        poolManager = manager;

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(this))
        });

        rate0 = 10 ** (36 - IERC20(Currency.unwrap(key.currency0)).decimals());
        rate1 = 10 ** (36 - IERC20(Currency.unwrap(key.currency1)).decimals());

        poolId = key.toId();

        _setAmp(initialAmp);
    }

    /// External

    /// TODO: Who can call this function?
    function setAmp(uint256 newAmp) external {
        _setAmp(newAmp);
    }

    /// @notice Stores which pool this hook belongs to.
    /// Only that pool will be able to interact with this hook.
    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96)
        external
        override
        returns (bytes4)
    {
        if (PoolId.unwrap(poolId) != PoolId.unwrap(key.toId())) {
            revert InvalidPoolId();
        }

        return StableSwapHooks.beforeInitialize.selector;
    }

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        // Verify only the pool manager is calling this function
        if (msg.sender != address(poolManager)) {
            revert InvalidCaller();
        }

        // Verify that liquidity is being added to the targeted pool
        if (PoolId.unwrap(poolId) != PoolId.unwrap(key.toId())) {
            revert InvalidPoolId();
        }

        // Verify that only a full ranged position is being created
        if (params.tickUpper != TICK_SPACING.maxUsableTick() || params.tickLower != TICK_SPACING.minUsableTick()) {
            revert InvalidRange();
        }

        // Extract amounts from delta
        uint256 amount0 = uint256(int256(-delta.amount0()));
        uint256 amount1 = uint256(int256(-delta.amount1()));

        uint256 oldTotalShares = totalShares;
        // TODO: Add min shares minted check (provided in hookData?)
        uint256 newShares = 0;

        {
            // Calculate old invariant
            uint256 oldReserves0 = reserves0;
            uint256 oldReserves1 = reserves1;
            uint256 oldInvariant =
                getD(rate0 * oldReserves0 / RATE_PRECISION, rate1 * oldReserves1 / RATE_PRECISION, amp);

            // Calculate new invariant
            uint256 newInvariant = getD(
                rate0 * (oldReserves0 + amount0) / RATE_PRECISION,
                rate1 * (oldReserves1 + amount1) / RATE_PRECISION,
                amp
            );

            // Verify new invariant is higher
            if (newInvariant <= oldInvariant) {
                revert InvalidInvariant();
            }

            // Calculate new shares
            if (oldTotalShares == 0) {
                newShares = newInvariant;
            } else {
                newShares = oldTotalShares * (newInvariant - oldInvariant) / oldInvariant;
            }
        }

        // Update storage
        totalShares = oldTotalShares + newShares;
        sharesByUser[sender] += newShares;
        reserves0 += amount0;
        reserves1 += amount1;

        // TODO: Emit event

        return (StableSwapHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        // Verify only the pool manager is calling this function
        if (msg.sender != address(poolManager)) {
            revert InvalidCaller();
        }

        // Verify that liquidity is being removed from the targeted pool
        if (PoolId.unwrap(poolId) != PoolId.unwrap(key.toId())) {
            revert InvalidPoolId();
        }

        // Verify that only a full ranged position is being removed
        if (params.tickUpper != TICK_SPACING.maxUsableTick() || params.tickLower != TICK_SPACING.minUsableTick()) {
            revert InvalidRange();
        }

        // Extract amounts from delta
        uint256 amount0 = uint256(int256(delta.amount0()));
        uint256 amount1 = uint256(int256(delta.amount1()));

        uint256 oldTotalShares = totalShares;
        uint256 sharesToBurn = 0;

        {
            // Calculate old invariant
            uint256 oldReserves0 = reserves0;
            uint256 oldReserves1 = reserves1;
            uint256 oldInvariant =
                getD(rate0 * oldReserves0 / RATE_PRECISION, rate1 * oldReserves1 / RATE_PRECISION, amp);

            // Calculate new invariant
            uint256 newInvariant = getD(
                rate0 * (oldReserves0 - amount0) / RATE_PRECISION,
                rate1 * (oldReserves1 - amount1) / RATE_PRECISION,
                amp
            );

            // Verify new invariant is lower (liquidity removed)
            if (newInvariant >= oldInvariant) {
                revert InvalidInvariant();
            }

            // Calculate shares to burn proportional to invariant decrease
            // TODO: Make sure the whole of the lps of the user are being burned at the end (avoid dust)
            sharesToBurn = oldTotalShares * (oldInvariant - newInvariant) / oldInvariant;
        }

        // Update storage
        // TODO: What would happen for accumulated rounding issues?
        totalShares = oldTotalShares - sharesToBurn;
        sharesByUser[sender] -= sharesToBurn;
        reserves0 -= amount0;
        reserves1 -= amount1;

        // TODO: Emit event

        return (StableSwapHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        // int128 dy = swap(_sender, _key, _params, amp);
        // BeforeSwapDelta delta = toBeforeSwapDelta(-_params.amountSpecified.toInt128(), dy);
        // Commented implementation for now until more robust solution.
        BeforeSwapDelta delta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), 0);

        return (StableSwapHooks.beforeSwap.selector, delta, 0);
    }

    /// Internal

    function swap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata params)
        private
        returns (int128)
    {
        uint256 xp0 = (rate0 * reserves0) / RATE_PRECISION;
        uint256 xp1 = (rate1 * reserves1) / RATE_PRECISION;

        int256 dx = params.amountSpecified;
        uint256 memAmp = amp;
        uint256 D = getD(xp0, xp1, memAmp);

        uint256 dy;
        // TODO dedup logic
        if (params.zeroForOne) {
            // Swapping token0 for token1
            if (dx < 0) {
                // Exact input: we know how much token0 is being put in
                uint256 x = xp0 + (uint256(-dx) * rate0) / RATE_PRECISION;

                uint256 y = getY(x, memAmp, D);
                dy = xp1 - y - 1;

                // Calculate fee on the output
                uint256 dy_fee = (dy * FEE) / FEE_DENOMINATOR;

                // Convert to real units
                dy = ((dy - dy_fee) * RATE_PRECISION) / rate1;
            } else {
                // Calculate required token0 input to provide desired token1 output (after fees)
                // based on how much token1 is desired
                uint256 dy_desired = uint256(dx);

                uint256 dy_gross = (dy_desired * rate1) / RATE_PRECISION;
                // The fee is applied to token1 output, so we need to calculate
                // the gross amount of token1 to be removed from reserves in order
                // to deliver the desired net amount to the user after fees.
                // Solve for gross_output such that:
                //   net_output = gross_output * (FEE_DENOMINATOR - FEE) / FEE_DENOMINATOR
                //   => gross_output = net_output * FEE_DENOMINATOR / (FEE_DENOMINATOR - FEE)
                dy_gross = (dy_gross * FEE_DENOMINATOR) / (FEE_DENOMINATOR - FEE);

                // Calculate y after swap
                uint256 y = xp1 - dy_gross;

                // Calculate required x (input in precision units)
                uint256 x = getY(y, memAmp, D);
                uint256 dx_required = x - xp0;

                // Convert to real units and return as negative (amount to take from user)
                dy = -int256((dx_required * RATE_PRECISION) / rate0);
            }
        } else {
            // Swapping token1 for token0
            if (dx < 0) {
                // Exact input: we know how much token1 is being put in
                uint256 y = xp1 + (uint256(-dx) * rate1) / RATE_PRECISION;
                uint256 x = getY(y, memAmp, D);
                dy = xp0 - x - 1;

                // Calculate fee on the output
                uint256 dy_fee = (dy * FEE) / FEE_DENOMINATOR;

                // Convert to real units
                dy = ((dy - dy_fee) * RATE_PRECISION) / rate0;
            } else {
                // Exact output: we know how much token0 should be received
                uint256 dy_desired = uint256(dx);

                uint256 dy_gross = (dy_desired * rate0) / RATE_PRECISION;
                dy_gross = (dy_gross * FEE_DENOMINATOR) / (FEE_DENOMINATOR - FEE);

                // Calculate x after swap
                uint256 x = xp0 - dy_gross;

                // Calculate required y (input in precision units)
                uint256 y = getY(x, memAmp, D);
                uint256 dx_required = y - xp1;

                // Convert to real units and return as negative (amount to take from user)
                dy = (dx_required * RATE_PRECISION) / rate1;
                // Negate dy to indicate amount to take from user
                dy = -int256(dy);
            }
        }

        // TODO
        // self.upkeep_oracles(xp, amp, D)

        // TODO
        // Check dy against amount * sqrtPrice => min to receive
        return dy.toInt128();
    }

    function getD(uint256 xp0, uint256 xp1, uint256 memAmp) private pure returns (uint256) {
        uint256 S = xp0 + xp1;

        uint256 D = S;
        uint256 Ann = memAmp * 2;

        for (uint256 i = 0; i < 255; ++i) {
            uint256 D_P = D;

            D_P = (D_P * D) / xp0;
            D_P = (D_P * D) / xp1;

            D_P = D_P / 4;

            uint256 D_prev = D;

            // (Ann * S / A_PRECISION + D_P * N_COINS) * D / ((Ann - A_PRECISION) * D / A_PRECISION + (N_COINS + 1) * D_P)
            D = (((Ann * S) / 100 + D_P * 2) * D) / (((Ann - 100) * D) / 100 + (2 + 1) * D_P);

            if (D > D_prev) {
                if (D - D_prev <= 1) {
                    return D;
                }
            } else {
                if (D - D_prev <= 1) {
                    return D;
                }
            }
        }

        revert("Convergence not reached");
    }

    function getY(uint256 x, uint256 memAmp, uint256 D) private pure returns (uint256) {
        uint256 S_ = x;
        uint256 y_prev = 0;
        uint256 c = D * (D / (x * 2));
        uint256 Ann = memAmp * 2;

        // c = c * D * A_PRECISION / (Ann * N_COINS)
        c = (c * D * 100) / (Ann * 2);

        // b: uint256 = S_ + D * A_PRECISION / Ann  # - D
        uint256 b = S_ + (D * 100) / Ann;

        // y: uint256 = D
        uint256 y = D;

        for (uint256 i = 0; i < 255; ++i) {
            y_prev = y;
            y = (y * y + c) / (2 * y + b - D);

            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                }
            } else {
                if (y - y_prev <= 1) {
                    return y;
                }
            }
        }

        revert("Convergence not reached (y)");
    }

    function _setAmp(uint256 newAmp) private {
        if (newAmp >= MAX_AMP) {
            revert InvalidAmp();
        }

        emit AmpSet(newAmp);

        amp = newAmp;
    }
}

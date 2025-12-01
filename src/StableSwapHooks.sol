// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";

// TODO: Move to somewhere else, or use OZ IERC20s
interface IERC20 {
    function decimals() external view returns (uint8);
}

contract StableSwapHooks is BaseHook {
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

    /// Events

    event AmpSet(uint256 newAmp);

    /// Deployment

    constructor(uint256 initialAmp, IPoolManager manager, Currency currency0, Currency currency1) BaseHook(manager) {
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

    /// Hooks

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions = Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Validates pool initialization parameters.
    /// @dev Reverts if the pool ID doesn't match.
    function _beforeInitialize(address, PoolKey calldata key, uint160 sqrtPriceX96) internal override returns (bytes4) {
        if (PoolId.unwrap(poolId) != PoolId.unwrap(key.toId())) {
            revert InvalidPoolId();
        }

        return BaseHook.beforeInitialize.selector;
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
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
                _getD(rate0 * oldReserves0 / RATE_PRECISION, rate1 * oldReserves1 / RATE_PRECISION, amp);

            // Calculate new invariant
            uint256 newInvariant = _getD(
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

        return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
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
                _getD(rate0 * oldReserves0 / RATE_PRECISION, rate1 * oldReserves1 / RATE_PRECISION, amp);

            // Calculate new invariant
            uint256 newInvariant = _getD(
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

        return (BaseHook.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Verify that swap is being performed on the targeted pool
        if (PoolId.unwrap(poolId) != PoolId.unwrap(key.toId())) {
            revert InvalidPoolId();
        }

        // int128 dy = swap(_sender, _key, _params, amp);
        // BeforeSwapDelta delta = toBeforeSwapDelta(-_params.amountSpecified.toInt128(), dy);
        // Commented implementation for now until more robust solution.
        BeforeSwapDelta delta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), 0);

        return (BaseHook.beforeSwap.selector, delta, 0);
    }

    /// Internal

    function _swap(address sender, PoolKey calldata key, SwapParams calldata params)
        private
        returns (int128)
    {
        uint256 xp0 = (rate0 * reserves0) / RATE_PRECISION;
        uint256 xp1 = (rate1 * reserves1) / RATE_PRECISION;

        int256 dx = params.amountSpecified;
        uint256 memAmp = amp;
        uint256 D = _getD(xp0, xp1, memAmp);

        int256 dy;

        // Determine token direction and rates
        bool isToken0In = params.zeroForOne;
        uint256 xpIn = isToken0In ? xp0 : xp1;
        uint256 xpOut = isToken0In ? xp1 : xp0;
        uint256 rateIn = isToken0In ? rate0 : rate1;
        uint256 rateOut = isToken0In ? rate1 : rate0;

        if (dx < 0) {
            // Exact input swap: user specifies how much they want to put in
            // dx is negative, representing amount being taken from user
            dy = _swapExactInput(xpIn, xpOut, uint256(-dx), rateIn, rateOut, memAmp, D);
        } else {
            // Exact output swap: user specifies how much they want to receive
            // dx is positive, representing desired output amount
            dy = _swapExactOutput(xpIn, xpOut, uint256(dx), rateIn, rateOut, memAmp, D);
        }

        // TODO
        // self.upkeep_oracles(xp, amp, D)

        // TODO
        // Check dy against amount * sqrtPrice => min to receive
        return dy.toInt128();
    }

    /// @dev Performs an exact input swap calculation
    /// @param xpIn Precision-adjusted reserve of input token
    /// @param xpOut Precision-adjusted reserve of output token
    /// @param amountIn Amount of input token (in real units)
    /// @param rateIn Rate multiplier for input token
    /// @param rateOut Rate multiplier for output token
    /// @param memAmp Amplification coefficient
    /// @param D Invariant D
    /// @return Amount of output token to give to user (positive = user receives)
    function _swapExactInput(
        uint256 xpIn,
        uint256 xpOut,
        uint256 amountIn,
        uint256 rateIn,
        uint256 rateOut,
        uint256 memAmp,
        uint256 D
    ) private pure returns (int256) {
        // Convert input amount to precision units and add to reserves
        uint256 xIn = xpIn + (amountIn * rateIn) / RATE_PRECISION;

        uint256 xOut = _getY(xIn, memAmp, D);

        // Subtract 1 to round in favor of the pool
        uint256 dyGross = xpOut - xOut - 1;

        // TODO
        // Fee handling: Apply fee to the output amount
        // Fee is deducted from the amount user receives
        // net_output = gross_output * (1 - fee_rate)
        // net_output = gross_output * (FEE_DENOMINATOR - FEE) / FEE_DENOMINATOR
        uint256 dyFee = (dyGross * FEE) / FEE_DENOMINATOR;
        uint256 dyNet = dyGross - dyFee;

        // Convert from precision units to real token units
        uint256 amountOut = (dyNet * RATE_PRECISION) / rateOut;

        return int256(amountOut);
    }

    /// @dev Performs an exact output swap calculation
    /// @param xpIn Precision-adjusted reserve of input token
    /// @param xpOut Precision-adjusted reserve of output token
    /// @param amountOut Desired amount of output token (in real units)
    /// @param rateIn Rate multiplier for input token
    /// @param rateOut Rate multiplier for output token
    /// @param memAmp Amplification coefficient
    /// @param D Invariant D
    /// @return Amount of input token to take from user (negative = user pays)
    function _swapExactOutput(
        uint256 xpIn,
        uint256 xpOut,
        uint256 amountOut,
        uint256 rateIn,
        uint256 rateOut,
        uint256 memAmp,
        uint256 D
    ) private pure returns (int256) {
        // Convert desired output to precision units
        uint256 dyNet = (amountOut * rateOut) / RATE_PRECISION;

        // TODO
        // Fee handling: Calculate gross output needed to deliver net output after fees
        // Since fee is applied to output: net_output = gross_output * (1 - fee_rate)
        // Solving for gross_output: gross_output = net_output / (1 - fee_rate)
        // Which equals: gross_output = net_output * FEE_DENOMINATOR / (FEE_DENOMINATOR - FEE)
        uint256 dyGross = (dyNet * FEE_DENOMINATOR) / (FEE_DENOMINATOR - FEE);

        // Calculate new output reserve after removing gross output
        uint256 xOut = xpOut - dyGross;

        // Calculate required input reserve using constant product invariant
        uint256 xIn = _getY(xOut, memAmp, D);

        // Calculate required input amount (in precision units)
        uint256 dxRequired = xIn - xpIn;

        // Convert from precision units to real token units
        uint256 amountIn = (dxRequired * RATE_PRECISION) / rateIn;

        // Return as negative to indicate amount to take from user
        return -int256(amountIn);
    }

    function _getD(uint256 xp0, uint256 xp1, uint256 memAmp) private pure returns (uint256) {
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

    function _getY(uint256 x, uint256 memAmp, uint256 D) private pure returns (uint256) {
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

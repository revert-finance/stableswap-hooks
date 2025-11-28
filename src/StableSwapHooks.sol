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
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BaseHooks} from "./BaseHooks.sol";

// TODO: Move to somewhere else, or use OZ IERC20s
interface IERC20 is IERC20Minimal {
    function decimals() external view returns (uint8);
}

contract StableSwapHooks is BaseHooks {
    using SafeCast for int256;
    using SafeCast for uint256;
    using TickMath for int24;

    /// Constants

    uint256 public constant MAX_AMP = 1e6;
    uint256 public constant RATE_PRECISION = 1e18;
    int24 public constant TICK_SPACING = 60;

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

    constructor(uint256 initialAmp, IPoolManager manager, Currency currency0, Currency currency1, uint24 fee) {
        poolManager = manager;

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
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
        // xp_mem
        uint256 xp0 = rate0 * reserves0 / 1e18;
        uint256 xp1 = rate1 * reserves1 / 1e18;

        // dx should be calculated?
        int256 dx = params.amountSpecified;
        if (dx >= 0) {
            // zeroForOne not used.
            revert();
        }

        uint256 x = xp0 + uint256(-dx) * rate0 / 1e18;

        uint256 memAmp = amp;

        uint256 D = getD(xp0, xp1, memAmp);
        uint256 y = getY(x, memAmp, D);
        uint256 dy = xp1 - y - 1;
        uint256 dy_fee = 0; // TODO

        // Convert all to real units
        dy = (dy - dy_fee) * 1e18 / rate1;

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

            D_P = D_P * D / xp0;
            D_P = D_P * D / xp1;

            D_P = D_P / 4;

            uint256 D_prev = D;

            // (Ann * S / A_PRECISION + D_P * N_COINS) * D / ((Ann - A_PRECISION) * D / A_PRECISION + (N_COINS + 1) * D_P)
            D = (Ann * S / 100 + D_P * 2) * D / ((Ann - 100) * D / 100 + (2 + 1) * D_P);

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
        c = c * D * 100 / (Ann * 2);

        // b: uint256 = S_ + D * A_PRECISION / Ann  # - D
        uint256 b = S_ + D * 100 / Ann;

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

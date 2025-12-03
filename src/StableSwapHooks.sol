// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";

import {StableSwapMath} from "./libraries/StableSwapMath.sol";

contract StableSwapHooks is BaseHook, AccessControlEnumerable, IUnlockCallback, ERC20 {
    using SafeCast for int256;
    using SafeCast for uint256;
    using TickMath for int24;
    using SafeERC20 for IERC20;

    /// Constants

    bytes32 public constant A_ADMIN_ROLE = keccak256("A_ADMIN_ROLE");

    uint256 public constant MAX_A = 1e6;
    uint256 public constant MAX_A_CHANGE = 10; // Maximum 10x change
    uint256 public constant MIN_RAMP_TIME = 1 days; // Minimum time between ramps and minimum ramp duration
    uint256 public constant RATE_PRECISION = 1e18;
    uint256 public constant ADD_LIQUIDITY_ACTION = 1;
    uint256 public constant REMOVE_LIQUIDITY_ACTION = 2;

    // TODO: Make fee and tick spacing configurable. Current value is recommended for stable pairs
    uint24 public constant FEE = 1e2; // 0.01%
    uint256 public constant FEE_DENOMINATOR = 1e6; // 100%
    int24 public constant TICK_SPACING = 1;

    /// Immutables

    PoolId public immutable poolId;
    uint256 public immutable rate0;
    uint256 public immutable rate1;
    Currency public immutable currency0;
    Currency public immutable currency1;

    /// Variables

    uint256 public initialA;
    uint256 public futureA;
    uint256 public initialATime;
    uint256 public futureATime;

    uint256 public reserves0;
    uint256 public reserves1;
    uint256 public totalShares;

    mapping(address => uint256) public sharesByUser;

    /// Errors

    error InvalidA();
    error InvalidPoolId();
    error InvalidInvariant();
    error InvalidRange();
    error InsufficientRampTime();
    error InsufficientTimeSinceLastAChange();
    error ExcessiveAmpChange();
    error InsufficientShares();
    error InsufficientAmounts();
    error UseHookLiquidityModifiers(address hookAddress);
    error AddLiquidityAmountsCannotBeZero();

    /// Events

    event RampedA(uint256 oldA, uint256 newA, uint256 initialTime, uint256 futureTime);
    event StoppedRampA(uint256 currentA, uint256 time);
    event LiquidityAdded(address indexed sender, uint256 amount0, uint256 amount1, uint256 shares);
    event LiquidityRemoved(address indexed sender, uint256 amount0, uint256 amount1, uint256 shares);

    /// Deployment

    constructor(uint256 _initialA, IPoolManager manager, Currency currency0_, Currency currency1_)
        BaseHook(manager)
        ERC20("StableSwap LP", "ssLP")
    {
        currency0 = currency0_;
        currency1 = currency1_;

        PoolKey memory key = PoolKey({
            currency0: currency0_,
            currency1: currency1_,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(this))
        });

        rate0 = 10 ** (36 - IERC20(Currency.unwrap(currency0_)).decimals());
        rate1 = 10 ** (36 - IERC20(Currency.unwrap(currency1_)).decimals());

        poolId = key.toId();

        if (_initialA >= MAX_A) {
            revert InvalidA();
        }

        initialA = _initialA;
        futureA = _initialA;
        // Set to 0 to allow immediate first ramp
        initialATime = 0;
        futureATime = 0;

        // Grant deployer the default admin role and AMP_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(A_ADMIN_ROLE, msg.sender);
    }

    /// External

    /// @notice Ramp A up or down over time
    /// @param _futureA The target amplification coefficient
    /// @param _futureTime The timestamp when ramping completes
    function rampA(uint256 _futureA, uint256 _futureTime) external onlyRole(A_ADMIN_ROLE) {
        // Validate future A value
        if (_futureA == 0 || _futureA >= MAX_A) {
            revert InvalidA();
        }

        // Ensure sufficient time has passed since last ramp (skip check if initialATime is 0, i.e., first ramp)
        if (initialATime != 0 && block.timestamp < initialATime + MIN_RAMP_TIME) {
            revert InsufficientTimeSinceLastAChange();
        }

        // Ensure sufficient ramp duration
        if (_futureTime < block.timestamp + MIN_RAMP_TIME) {
            revert InsufficientRampTime();
        }

        uint256 currentA = A();

        // Validate A change is not too large
        if (_futureA < currentA) {
            // Ramping down: futureA * MAX_A_CHANGE >= currentA
            if (_futureA * MAX_A_CHANGE < currentA) {
                revert ExcessiveAmpChange();
            }
        } else {
            // Ramping up: futureA <= currentA * MAX_A_CHANGE
            if (_futureA > currentA * MAX_A_CHANGE) {
                revert ExcessiveAmpChange();
            }
        }

        initialA = currentA;
        futureA = _futureA;
        initialATime = block.timestamp;
        futureATime = _futureTime;

        emit RampedA(currentA, _futureA, block.timestamp, _futureTime);
    }

    /// @notice Stop ramping A and fix it at current value
    function stopRampA() external onlyRole(A_ADMIN_ROLE) {
        uint256 currentA = A();

        initialA = currentA;
        futureA = currentA;
        initialATime = block.timestamp;
        futureATime = block.timestamp;

        emit StoppedRampA(currentA, block.timestamp);
    }

    /// @notice Add liquidity to the pool
    /// @param amount0 The amount of currency0 to add
    /// @param amount1 The amount of currency1 to add
    /// @param minShares The minimum number of shares to receive
    function addLiquidity(uint256 amount0, uint256 amount1, uint256 minShares) external {
        bytes memory data = abi.encode(ADD_LIQUIDITY_ACTION, amount0, amount1, minShares, msg.sender);

        poolManager.unlock(data);
    }

    /// @notice Remove liquidity from the pool
    /// @param shares The number of shares to burn
    /// @param minAmount0 The minimum amount of currency0 to receive
    /// @param minAmount1 The minimum amount of currency1 to receive
    function removeLiquidity(uint256 shares, uint256 minAmount0, uint256 minAmount1) external {
        bytes memory data = abi.encode(REMOVE_LIQUIDITY_ACTION, shares, minAmount0, minAmount1, msg.sender);

        poolManager.unlock(data);
    }

    /// @notice Callback function for the pool manager
    /// @param data The data passed to the unlock function
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        uint256 action = abi.decode(data, (uint256));

        if (action == ADD_LIQUIDITY_ACTION) {
            _handleAddLiquidityCallback(data);
        } else if (action == REMOVE_LIQUIDITY_ACTION) {
            _handleRemoveLiquidityCallback(data);
        }
    }

    /// @notice Get current amplification coefficient with ramping
    /// @return The current A value, interpolated if ramping is in progress
    function A() public view returns (uint256) {
        uint256 t1 = futureATime;
        uint256 A1 = futureA;

        if (block.timestamp < t1) {
            uint256 A0 = initialA;
            uint256 t0 = initialATime;

            uint256 timeDelta = block.timestamp - t0;
            uint256 totalTime = t1 - t0;

            // Linear interpolation between A0 and A1
            if (A1 > A0) {
                // Ramping up
                return A0 + ((A1 - A0) * timeDelta) / totalTime;
            } else {
                // Ramping down
                return A0 - ((A0 - A1) * timeDelta) / totalTime;
            }
        } else {
            // When t1 == 0 or block.timestamp >= t1, ramping is complete
            return A1;
        }
    }

    /// Hooks

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions = Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
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
    function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4) {
        if (PoolId.unwrap(poolId) != PoolId.unwrap(key.toId())) {
            revert InvalidPoolId();
        }

        return BaseHook.beforeInitialize.selector;
    }

    /// @dev Reverts if liquidity is modified via PoolManager.modifyLiquidity function.
    /// Liquidity should be provided via the addLiquidity function of this contract.
    function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        override
        returns (bytes4)
    {
        revert UseHookLiquidityModifiers(address(this));
    }

    /// @dev Reverts if liquidity is modified via PoolManager.modifyLiquidity function.
    /// Liquidity should be removed via the removeLiquidity function of this contract.
    function _beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        override
        returns (bytes4)
    {
        revert UseHookLiquidityModifiers(address(this));
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (PoolId.unwrap(poolId) != PoolId.unwrap(key.toId())) {
            revert InvalidPoolId();
        }

        int128 dy = _swap(sender, key, params);
        BeforeSwapDelta delta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), -dy);

        if (params.zeroForOne) {
            poolManager.burn(address(this), currency1.toId(), uint128(dy));
            poolManager.mint(address(this), currency0.toId(), uint256(-params.amountSpecified));
            reserves0 += uint256(-params.amountSpecified);
            reserves1 -= uint128(dy);
        } else {
            poolManager.mint(address(this), currency1.toId(), uint256(-params.amountSpecified));
            poolManager.burn(address(this), currency0.toId(), uint128(dy));
            reserves0 -= uint128(dy);
            reserves1 += uint256(-params.amountSpecified);
        }

        return (BaseHook.beforeSwap.selector, delta, 0);
    }

    /// Internal

    function _handleAddLiquidityCallback(bytes calldata data) private {
        (, uint256 amount0, uint256 amount1, uint256 minShares, address sender) =
            abi.decode(data, (uint256, uint256, uint256, uint256, address));

        // Check that amount0 and amount1 are not both zero.
        // The invariant takes into consideration single sided deposits
        if (amount0 == 0 && amount1 == 0) {
            revert AddLiquidityAmountsCannotBeZero();
        }

        uint256 oldTotalShares = totalShares;
        uint256 newShares;

        uint256 oldReserves0 = reserves0;
        uint256 oldReserves1 = reserves1;

        uint256 newReserves0 = oldReserves0 + amount0;
        uint256 newReserves1 = oldReserves1 + amount1;

        // Calculate new invariant
        uint256 newInvariant = StableSwapMath.getInvariant(
            rate0 * newReserves0 / RATE_PRECISION, rate1 * newReserves1 / RATE_PRECISION, A()
        );

        // TODO: Handle min liquidity to prevent dust attacks
        if (oldTotalShares == 0) {
            // Shares equal the invariant on the first deposit
            newShares = newInvariant;
        } else {
            // Compute the old invariant
            uint256 oldInvariant = StableSwapMath.getInvariant(
                rate0 * oldReserves0 / RATE_PRECISION, rate1 * oldReserves1 / RATE_PRECISION, A()
            );

            // Check that the new invariant is higher
            if (newInvariant <= oldInvariant) {
                revert InvalidInvariant();
            }

            // Compute the new shares
            newShares = oldTotalShares * (newInvariant - oldInvariant) / oldInvariant;
        }

        // Check that the new shares are above the minimum
        if (newShares < minShares) {
            revert InsufficientShares();
        }

        // Transfer tokens from sender to PoolManager
        if (amount0 > 0) {
            poolManager.sync(currency0);
            IERC20(Currency.unwrap(currency0)).safeTransferFrom(sender, address(poolManager), amount0);
            poolManager.settle();
            poolManager.mint(address(this), currency0.toId(), amount0);
        }

        if (amount1 > 0) {
            poolManager.sync(currency1);
            IERC20(Currency.unwrap(currency1)).safeTransferFrom(sender, address(poolManager), amount1);
            poolManager.settle();
            poolManager.mint(address(this), currency1.toId(), amount1);
        }

        // Update storage
        totalShares += newShares;
        sharesByUser[sender] += newShares;
        reserves0 += amount0;
        reserves1 += amount1;

        _mint(sender, newShares);

        emit LiquidityAdded(sender, amount0, amount1, newShares);
    }

    function _handleRemoveLiquidityCallback(bytes calldata data) private {
        (, uint256 shares, uint256 minAmount0, uint256 minAmount1, address sender) =
            abi.decode(data, (uint256, uint256, uint256, uint256, address));

        uint256 userShares = sharesByUser[sender];

        // Check that user has enough shares
        if (shares > userShares) {
            revert InsufficientShares();
        }

        // Calculate proportional amounts to withdraw
        uint256 currentTotalShares = totalShares;
        uint256 amount0 = (shares * reserves0) / currentTotalShares;
        uint256 amount1 = (shares * reserves1) / currentTotalShares;

        // Check slippage
        if (amount0 < minAmount0 || amount1 < minAmount1) {
            revert InsufficientAmounts();
        }

        // Burn claims and transfer tokens from PoolManager to sender
        if (amount0 > 0) {
            poolManager.burn(address(this), currency0.toId(), amount0);
            poolManager.take(currency0, sender, amount0);
        }

        if (amount1 > 0) {
            poolManager.burn(address(this), currency1.toId(), amount1);
            poolManager.take(currency1, sender, amount1);
        }

        // Update storage
        totalShares = currentTotalShares - shares;
        sharesByUser[sender] = userShares - shares;
        reserves0 -= amount0;
        reserves1 -= amount1;

        _burn(sender, shares);

        emit LiquidityRemoved(sender, amount0, amount1, shares);
    }

    function _swap(address sender, PoolKey calldata key, SwapParams calldata params) private returns (int128) {
        uint256 xp0 = (rate0 * reserves0) / RATE_PRECISION;
        uint256 xp1 = (rate1 * reserves1) / RATE_PRECISION;

        int256 dx = params.amountSpecified;
        uint256 memAmp = A();
        uint256 D = StableSwapMath.getInvariant(xp0, xp1, memAmp);

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

        uint256 xOut = StableSwapMath.getOtherReserves(xIn, memAmp, D);

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
        uint256 xIn = StableSwapMath.getOtherReserves(xOut, memAmp, D);

        // Calculate required input amount (in precision units)
        uint256 dxRequired = xIn - xpIn;

        // Convert from precision units to real token units
        uint256 amountIn = (dxRequired * RATE_PRECISION) / rateIn;

        // Return as negative to indicate amount to take from user
        return -int256(amountIn);
    }
}

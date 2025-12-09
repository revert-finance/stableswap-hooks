// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";

import {StableSwapMath} from "src/libraries/StableSwapMath.sol";
import {Actions} from "src/libraries/Actions.sol";
import {Fees} from "src/Fees.sol";
import {Base} from "src/Base.sol";
import {Amp} from "src/Amp.sol";
import {Swap} from "src/Swap.sol";

contract StableSwapHooks is IUnlockCallback, ERC20, Swap {
    using SafeERC20 for IERC20;

    /// Variables

    uint256 public totalShares;

    mapping(address => uint256) public sharesByUser;

    /// Errors

    error InvalidInvariant();
    error InsufficientShares();
    error InsufficientAmounts();
    error UseHookLiquidityModifiers(address hookAddress);
    error AddLiquidityAmountsCannotBeZero();
    error InvalidAction();

    /// Events

    event LiquidityAdded(address indexed sender, uint256 amount0, uint256 amount1, uint256 shares);
    event LiquidityRemoved(address indexed sender, uint256 amount0, uint256 amount1, uint256 shares);

    /// Deployment

    constructor(
        IPoolManager _poolManager,
        Currency _currency0,
        Currency _currency1,
        address _protocolFeeCollector,
        uint256 _protocolFeePercentage,
        uint256 _hookFeePercentage,
        uint256 _lpFeePercentage,
        uint256 _baseAmp
    )
        Base(_poolManager, _currency0, _currency1, _lpFeePercentage)
        Fees(_protocolFeeCollector, _protocolFeePercentage, _hookFeePercentage, _lpFeePercentage)
        Amp(_baseAmp)
        ERC20("StableSwap LP", "ssLP")
    {}

    /// External

    /// @notice Add liquidity to the pool
    /// @param amount0 The amount of currency0 to add
    /// @param amount1 The amount of currency1 to add
    /// @param minShares The minimum number of shares to receive
    function addLiquidity(uint256 amount0, uint256 amount1, uint256 minShares) external {
        bytes memory data = abi.encode(Actions.ADD_LIQUIDITY, amount0, amount1, minShares, _msgSender());

        poolManager.unlock(data);
    }

    /// @notice Remove liquidity from the pool
    /// @param shares The number of shares to burn
    /// @param minAmount0 The minimum amount of currency0 to receive
    /// @param minAmount1 The minimum amount of currency1 to receive
    function removeLiquidity(uint256 shares, uint256 minAmount0, uint256 minAmount1) external {
        bytes memory data = abi.encode(Actions.REMOVE_LIQUIDITY, shares, minAmount0, minAmount1, _msgSender());

        poolManager.unlock(data);
    }

    /// @notice Callback function for the pool manager
    /// @param data The data passed to the unlock function
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        uint256 action = abi.decode(data, (uint256));

        if (action == Actions.ADD_LIQUIDITY) {
            _handleAddLiquidityCallback(data);
        } else if (action == Actions.REMOVE_LIQUIDITY) {
            _handleRemoveLiquidityCallback(data);
        } else {
            revert InvalidAction();
        }

        return "";
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
            beforeDonate: true,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Validates pool initialization parameters.
    /// @dev Reverts if the pool ID doesn't match.
    function _beforeInitialize(address, PoolKey calldata key, uint160) internal view override returns (bytes4) {
        if (PoolId.unwrap(poolId) != PoolId.unwrap(key.toId())) {
            revert InvalidPoolId();
        }

        return BaseHook.beforeInitialize.selector;
    }

    /// @dev Reverts if liquidity is modified via PoolManager.modifyLiquidity function.
    /// Liquidity should be provided via the addLiquidity function of this contract.
    function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4)
    {
        revert UseHookLiquidityModifiers(address(this));
    }

    /// @dev Reverts if liquidity is modified via PoolManager.modifyLiquidity function.
    /// Liquidity should be removed via the removeLiquidity function of this contract.
    function _beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4)
    {
        revert UseHookLiquidityModifiers(address(this));
    }

    /// @dev Reverts if someone tries to donate tokens to the pool.
    /// All liquidity must be handled via the liquidity modifier functions of this contract.
    function _beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        internal
        view
        override
        returns (bytes4)
    {
        revert UseHookLiquidityModifiers(address(this));
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

        uint256 currentAmp = _currentAmp();

        // Calculate new invariant
        uint256 newInvariant = StableSwapMath.getInvariant(
            StableSwapMath.scaleTo(newReserves0, rate0), StableSwapMath.scaleTo(newReserves1, rate1), currentAmp
        );

        // TODO: Handle min liquidity to prevent dust attacks
        if (oldTotalShares == 0) {
            // Shares equal the invariant on the first deposit
            newShares = newInvariant;
        } else {
            // Compute the old invariant
            uint256 oldInvariant = StableSwapMath.getInvariant(
                StableSwapMath.scaleTo(oldReserves0, rate0), StableSwapMath.scaleTo(oldReserves1, rate1), currentAmp
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
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Amp} from "src/Amp.sol";
import {Actions} from "src/libraries/Actions.sol";
import {StableSwapMath} from "src/libraries/StableSwapMath.sol";

abstract contract Liquidity is Amp, ERC20 {
    using SafeERC20 for IERC20;

    event LiquidityAdded(address indexed sender, uint256 amount0, uint256 amount1, uint256 shares);
    event LiquidityRemoved(address indexed sender, uint256 amount0, uint256 amount1, uint256 shares);

    error InvalidInvariant();
    error InsufficientShares();
    error InsufficientAmounts();
    error UseHookLiquidityModifiers(address hookAddress);
    error AddLiquidityAmountsCannotBeZero();

    constructor() ERC20("StableSwap LP Token", "SSLP") {}

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

    function _handleAddLiquidityCallback(bytes calldata data) internal {
        (, uint256 amount0, uint256 amount1, uint256 minShares, address sender) =
            abi.decode(data, (uint256, uint256, uint256, uint256, address));

        // Check that amount0 and amount1 are not both zero.
        // The invariant takes into consideration single sided deposits
        if (amount0 == 0 && amount1 == 0) {
            revert AddLiquidityAmountsCannotBeZero();
        }

        // TODO: Handle min liquidity to prevent dust attacks
        uint256 newShares = _computeNewShares(amount0, amount1);

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
        reserves0 += amount0;
        reserves1 += amount1;

        _mint(sender, newShares);

        emit LiquidityAdded(sender, amount0, amount1, newShares);
    }

    function _computeNewShares(uint256 amount0, uint256 amount1) internal view returns (uint256 newShares) {
        uint256 oldTotalShares = totalSupply();

        uint256 oldReserves0 = reserves0;
        uint256 oldReserves1 = reserves1;

        uint256 newReserves0 = oldReserves0 + amount0;
        uint256 newReserves1 = oldReserves1 + amount1;

        uint256 currentAmp = _currentAmp();

        uint256 newInvariant = StableSwapMath.getInvariant(
            StableSwapMath.scaleTo(newReserves0, rate0), StableSwapMath.scaleTo(newReserves1, rate1), currentAmp
        );

        if (oldTotalShares == 0) {
            newShares = newInvariant;
        } else {
            uint256 oldInvariant = StableSwapMath.getInvariant(
                StableSwapMath.scaleTo(oldReserves0, rate0), StableSwapMath.scaleTo(oldReserves1, rate1), currentAmp
            );

            if (newInvariant <= oldInvariant) {
                revert InvalidInvariant();
            }

            newShares = oldTotalShares * (newInvariant - oldInvariant) / oldInvariant;
        }
    }

    function _handleRemoveLiquidityCallback(bytes calldata data) internal {
        (, uint256 shares, uint256 minAmount0, uint256 minAmount1, address sender) =
            abi.decode(data, (uint256, uint256, uint256, uint256, address));

        uint256 userShares = balanceOf(sender);

        // Check that user has enough shares
        if (shares > userShares) {
            revert InsufficientShares();
        }

        // Calculate proportional amounts to withdraw
        uint256 currentTotalSupply = totalSupply();
        uint256 amount0 = (shares * reserves0) / currentTotalSupply;
        uint256 amount1 = (shares * reserves1) / currentTotalSupply;

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
        reserves0 -= amount0;
        reserves1 -= amount1;

        _burn(sender, shares);

        emit LiquidityRemoved(sender, amount0, amount1, shares);
    }
}

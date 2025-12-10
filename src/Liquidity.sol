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

/// @notice Abstract contract that manages liquidity provision and withdrawal for the StableSwap pool
/// @dev Inherits from Amp for amplification factor management and ERC20 for LP token functionality
abstract contract Liquidity is Amp, ERC20 {
    using SafeERC20 for IERC20;

    /// @notice Emitted when liquidity is added to the pool
    /// @param sender Address that added liquidity
    /// @param amount0 Amount of currency0 added
    /// @param amount1 Amount of currency1 added
    /// @param shares Number of LP shares minted
    event LiquidityAdded(address indexed sender, uint256 amount0, uint256 amount1, uint256 shares);

    /// @notice Emitted when liquidity is removed from the pool
    /// @param sender Address that removed liquidity
    /// @param amount0 Amount of currency0 withdrawn
    /// @param amount1 Amount of currency1 withdrawn
    /// @param shares Number of LP shares burned
    event LiquidityRemoved(address indexed sender, uint256 amount0, uint256 amount1, uint256 shares);

    /// @notice Error thrown when adding liquidity would decrease the invariant
    error InvalidInvariant();

    /// @notice Error thrown when user has insufficient LP shares for the operation
    error InsufficientShares();

    /// @notice Error thrown when withdrawal amounts are below the minimum specified
    error InsufficientAmounts();

    /// @notice Error thrown when attempting to modify liquidity via PoolManager directly
    /// @param hookAddress The address of this hook contract that should be used instead
    error UseHookLiquidityModifiers(address hookAddress);

    /// @notice Error thrown when both deposit amounts are zero
    error AddLiquidityAmountsCannotBeZero();

    /// @notice Error thrown when initial liquidity is below minimum
    error InsufficientInitialLiquidity();

    /// @notice Minimum liquidity permanently locked on first deposit to prevent dust attacks and price manipulation
    uint256 private constant MINIMUM_LIQUIDITY = 1000;

    constructor() ERC20("StableSwap LP Token", "SSLP") {}

    /// @notice Add liquidity to the pool
    /// @dev Supports single-sided deposits; at least one amount must be non-zero
    /// @dev Triggers an unlock callback to handle the deposit through the pool manager
    /// @param amount0 The amount of currency0 to add
    /// @param amount1 The amount of currency1 to add
    /// @param minShares The minimum number of shares to receive (slippage protection)
    function addLiquidity(uint256 amount0, uint256 amount1, uint256 minShares) external {
        bytes memory data = abi.encode(Actions.ADD_LIQUIDITY, amount0, amount1, minShares, _msgSender());

        poolManager.unlock(data);
    }

    /// @notice Remove liquidity from the pool
    /// @dev Burns LP shares and returns proportional amounts of both tokens
    /// @dev Triggers an unlock callback to handle the withdrawal through the pool manager
    /// @param shares The number of LP shares to burn
    /// @param minAmount0 The minimum amount of currency0 to receive (slippage protection)
    /// @param minAmount1 The minimum amount of currency1 to receive (slippage protection)
    function removeLiquidity(uint256 shares, uint256 minAmount0, uint256 minAmount1) external {
        bytes memory data = abi.encode(Actions.REMOVE_LIQUIDITY, shares, minAmount0, minAmount1, _msgSender());

        poolManager.unlock(data);
    }

    /// @notice Hook called before liquidity is added via PoolManager
    /// @dev Always reverts to enforce using this contract's addLiquidity function
    function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4)
    {
        revert UseHookLiquidityModifiers(address(this));
    }

    /// @notice Hook called before liquidity is removed via PoolManager
    /// @dev Always reverts to enforce using this contract's removeLiquidity function
    function _beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4)
    {
        revert UseHookLiquidityModifiers(address(this));
    }

    /// @notice Hook called before tokens are donated to the pool
    /// @dev Always reverts as donations are not supported
    function _beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        internal
        view
        override
        returns (bytes4)
    {
        revert UseHookLiquidityModifiers(address(this));
    }

    /// @notice Internal callback handler for adding liquidity
    /// @dev Called during unlock callback to process the liquidity addition
    /// @dev Validates amounts, computes shares, transfers tokens, and mints LP tokens
    /// @param data Encoded data containing amounts, minShares, and sender address
    function _handleAddLiquidityCallback(bytes calldata data) internal {
        (, uint256 amount0, uint256 amount1, uint256 minShares, address sender) =
            abi.decode(data, (uint256, uint256, uint256, uint256, address));

        // Check that amount0 and amount1 are not both zero.
        // The invariant takes into consideration single sided deposits
        if (amount0 == 0 && amount1 == 0) {
            revert AddLiquidityAmountsCannotBeZero();
        }

        bool isFirstDeposit = totalSupply() == 0;

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

        // Lock minimum liquidity on first deposit to prevent dust attacks and price manipulation
        if (isFirstDeposit) {
            _mint(address(0), MINIMUM_LIQUIDITY);
        }

        emit LiquidityAdded(sender, amount0, amount1, newShares);
    }

    /// @notice Computes the number of LP shares to mint for a given deposit
    /// @dev Uses the StableSwap invariant to calculate proportional shares
    /// @dev For first deposit, shares equal the invariant minus MINIMUM_LIQUIDITY; for subsequent deposits, shares are proportional to invariant increase
    /// @param amount0 Amount of currency0 being deposited
    /// @param amount1 Amount of currency1 being deposited
    /// @return newShares Number of LP shares to mint
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
            // First deposit - lock minimum liquidity to prevent dust attacks and price manipulation
            if (newInvariant < MINIMUM_LIQUIDITY) {
                revert InsufficientInitialLiquidity();
            }
            newShares = newInvariant - MINIMUM_LIQUIDITY;
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

    /// @notice Internal callback handler for removing liquidity
    /// @dev Called during unlock callback to process the liquidity removal
    /// @dev Validates shares, calculates proportional amounts, burns LP tokens, and transfers underlying tokens
    /// @param data Encoded data containing shares, minAmounts, and sender address
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

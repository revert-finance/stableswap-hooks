// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {Amp} from "src/Amp.sol";
import {Actions} from "src/libraries/Actions.sol";
import {StableSwapMath} from "src/libraries/StableSwapMath.sol";

/// @notice Abstract contract that manages liquidity provision and withdrawal for the StableSwap pool
abstract contract Liquidity is Amp, ERC20 {
    using SafeERC20 for IERC20;

    /// @notice Minimum liquidity permanently locked on first deposit to prevent dust attacks and price manipulation
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    /// @notice Address where minimum liquidity is permanently locked
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Emitted when liquidity is added to the pool
    event LiquidityAdded(address indexed _sender, uint256[] _amounts, uint256 _shares);

    /// @notice Emitted when liquidity is removed from the pool
    event LiquidityRemoved(address indexed _sender, uint256[] _amounts, uint256 _shares);

    /// @notice Error thrown when user has insufficient LP shares for the operation
    error InsufficientShares();

    /// @notice Error thrown when withdrawal amounts are below the minimum specified
    error InsufficientAmounts();

    /// @notice Error thrown when actual amounts used are below the minimum specified
    error InsufficientAmountsUsed();

    /// @notice Error thrown when attempting to modify liquidity via PoolManager directly
    error UseHookLiquidityModifiers(address _hookAddress);

    /// @notice Error thrown when initial liquidity is below minimum
    error InsufficientInitialLiquidity();

    /// @notice Error thrown when msg.value doesn't match the native ETH amount in _amounts
    error AmountValueMismatch();

    /// @notice Error thrown when ETH is sent to a pool that doesn't support native ETH
    error UnexpectedValue();

    constructor() ERC20("StableSwap LP Token", "SSLP") {}

    /// @notice Quote the result of adding liquidity to the pool
    /// @dev First deposit uses all amounts; subsequent deposits must be proportional to reserves
    /// @param _amounts Array of amounts for each currency (max amounts for subsequent deposits)
    function quoteAddLiquidity(uint256[] calldata _amounts)
        external
        view
        returns (uint256 shares, uint256[] memory actualAmounts)
    {
        (shares, actualAmounts) = _calculateAddLiquidity(_amounts);
    }

    /// @notice Quote the result of removing liquidity from the pool
    /// @dev Returns proportional amounts of all currencies for the given shares
    /// @param _shares The number of LP shares to burn
    function quoteRemoveLiquidity(uint256 _shares) external view returns (uint256[] memory amounts) {
        amounts = _calculateRemoveLiquidity(_shares);
    }

    /// @notice Add liquidity to the pool
    /// @dev First deposit uses all amounts; subsequent deposits must be proportional to reserves
    /// @dev Triggers an unlock callback to handle the deposit through the pool manager
    /// @param _amounts Array of amounts for each currency (max amounts for subsequent deposits)
    /// @param _minAmounts Array of minimum amounts that must be used (slippage protection for amounts)
    /// @param _minShares The minimum number of shares to receive (slippage protection for LP tokens)
    function addLiquidity(uint256[] calldata _amounts, uint256[] calldata _minAmounts, uint256 _minShares)
        external
        payable
    {
        bytes memory data = abi.encode(Actions.ADD_LIQUIDITY, _amounts, _minAmounts, _minShares, msg.sender, msg.value);

        poolManager.unlock(data);
    }

    /// @notice Remove liquidity from the pool
    /// @dev Burns LP shares and returns proportional amounts of all currencies
    /// @dev Triggers an unlock callback to handle the withdrawal through the pool manager
    /// @param _shares The number of LP shares to burn
    /// @param _minAmounts Array of minimum amounts for each currency to receive (slippage protection)
    function removeLiquidity(uint256 _shares, uint256[] calldata _minAmounts) external {
        bytes memory data = abi.encode(Actions.REMOVE_LIQUIDITY, _shares, _minAmounts, msg.sender);

        poolManager.unlock(data);
    }

    /// @dev Hook called before liquidity is added via PoolManager, always reverts
    function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4)
    {
        revert UseHookLiquidityModifiers(address(this));
    }

    /// @dev Hook called before liquidity is removed via PoolManager, always reverts
    function _beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4)
    {
        revert UseHookLiquidityModifiers(address(this));
    }

    /// @dev Hook called before tokens are donated to the pool, always reverts
    function _beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        internal
        view
        override
        returns (bytes4)
    {
        revert UseHookLiquidityModifiers(address(this));
    }

    /// @dev Callback handler for adding liquidity
    function _handleAddLiquidityCallback(bytes calldata data) internal {
        (, uint256[] memory amounts, uint256[] memory minAmounts, uint256 minShares, address sender, uint256 value) =
            abi.decode(data, (uint256, uint256[], uint256[], uint256, address, uint256));

        if (currencies[0].isAddressZero()) {
            if (amounts[0] != value) {
                revert AmountValueMismatch();
            }
        } else if (value != 0) {
            revert UnexpectedValue();
        }

        bool isInitialDeposit = totalSupply() == 0;

        (uint256 newShares, uint256[] memory actualAmounts) = _calculateAddLiquidity(amounts);

        if (newShares < minShares) {
            revert InsufficientShares();
        }

        for (uint256 i = 0; i < currenciesLength; ++i) {
            if (actualAmounts[i] < minAmounts[i]) {
                revert InsufficientAmountsUsed();
            }
        }

        if (isInitialDeposit) {
            _mint(DEAD_ADDRESS, MINIMUM_LIQUIDITY);
        }

        uint256 refundValue;

        for (uint256 i = 0; i < currenciesLength; ++i) {
            Currency currency = currencies[i];

            if (currency.isAddressZero()) {
                refundValue = amounts[i] - actualAmounts[i];
                poolManager.settle{value: actualAmounts[i]}();
            } else {
                poolManager.sync(currency);
                IERC20(Currency.unwrap(currency)).safeTransferFrom(sender, address(poolManager), actualAmounts[i]);
                poolManager.settle();
            }

            poolManager.mint(address(this), currency.toId(), actualAmounts[i]);
            reserves[i] += actualAmounts[i];
        }

        _mint(sender, newShares);

        if (refundValue > 0) {
            Address.sendValue(payable(sender), refundValue);
        }

        emit LiquidityAdded(sender, actualAmounts, newShares);
    }

    /// @dev Callback handler for removing liquidity
    function _handleRemoveLiquidityCallback(bytes calldata data) internal {
        (, uint256 shares, uint256[] memory minAmounts, address sender) =
            abi.decode(data, (uint256, uint256, uint256[], address));

        if (shares > balanceOf(sender)) {
            revert InsufficientShares();
        }

        uint256[] memory amounts = _calculateRemoveLiquidity(shares);

        _burn(sender, shares);

        for (uint256 i = 0; i < currenciesLength; ++i) {
            if (amounts[i] < minAmounts[i]) {
                revert InsufficientAmounts();
            }

            reserves[i] -= amounts[i];
        }

        for (uint256 i = 0; i < currenciesLength; ++i) {
            Currency currency = currencies[i];

            poolManager.burn(address(this), currency.toId(), amounts[i]);
            poolManager.take(currency, sender, amounts[i]);
        }

        emit LiquidityRemoved(sender, amounts, shares);
    }

    /// @dev Calculates shares and actual amounts for adding liquidity
    function _calculateAddLiquidity(uint256[] memory _amounts)
        private
        view
        returns (uint256 shares, uint256[] memory actualAmounts)
    {
        uint256 currentTotalSupply = totalSupply();
        actualAmounts = new uint256[](currenciesLength);

        if (currentTotalSupply == 0) {
            uint256[] memory scaledAmounts = new uint256[](currenciesLength);

            for (uint256 i = 0; i < currenciesLength; ++i) {
                scaledAmounts[i] = StableSwapMath.scaleTo(_amounts[i], _getRate(i));
            }

            shares = StableSwapMath.geometricMean(scaledAmounts);

            if (shares < MINIMUM_LIQUIDITY) {
                revert InsufficientInitialLiquidity();
            }

            shares -= MINIMUM_LIQUIDITY;

            for (uint256 i = 0; i < currenciesLength; ++i) {
                actualAmounts[i] = _amounts[i];
            }
        } else {
            uint256 minProportion = type(uint256).max;

            for (uint256 i = 0; i < currenciesLength; ++i) {
                uint256 proportion = Math.mulDiv(_amounts[i], currentTotalSupply, reserves[i]);

                if (proportion < minProportion) {
                    minProportion = proportion;
                }
            }

            shares = minProportion;

            for (uint256 i = 0; i < currenciesLength; ++i) {
                actualAmounts[i] = Math.mulDiv(shares, reserves[i], currentTotalSupply, Math.Rounding.Ceil);
            }
        }
    }

    /// @dev Calculates withdrawal amounts for removing liquidity
    function _calculateRemoveLiquidity(uint256 _shares) private view returns (uint256[] memory amounts) {
        uint256 currentTotalSupply = totalSupply();
        amounts = new uint256[](currenciesLength);

        for (uint256 i = 0; i < currenciesLength; ++i) {
            amounts[i] = (_shares * reserves[i]) / currentTotalSupply;
        }
    }
}

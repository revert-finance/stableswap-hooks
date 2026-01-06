// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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

    /// @notice Error thrown when attempting to modify liquidity via PoolManager directly
    error UseHookLiquidityModifiers(address _hookAddress);

    /// @notice Error thrown when initial liquidity is below minimum
    error InsufficientInitialLiquidity();

    constructor() ERC20("StableSwap LP Token", "SSLP") {}

    /// @notice Add liquidity to the pool
    /// @dev First deposit uses all amounts; subsequent deposits must be proportional to reserves
    /// @dev Triggers an unlock callback to handle the deposit through the pool manager
    /// @param _amounts Array of amounts for each currency (max amounts for subsequent deposits)
    /// @param _minShares The minimum number of shares to receive (slippage protection)
    function addLiquidity(uint256[] calldata _amounts, uint256 _minShares) external {
        bytes memory data = abi.encode(Actions.ADD_LIQUIDITY, _amounts, _minShares, msg.sender);

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
        (, uint256[] memory amounts, uint256 minShares, address sender) =
            abi.decode(data, (uint256, uint256[], uint256, address));

        uint256 currentTotalSupply = totalSupply();
        uint256[] memory actualAmounts = new uint256[](currenciesLength);
        uint256 newShares;

        if (currentTotalSupply == 0) {
            uint256[] memory scaledAmounts = new uint256[](currenciesLength);

            for (uint256 i = 0; i < currenciesLength; ++i) {
                scaledAmounts[i] = StableSwapMath.scaleTo(amounts[i], _getRate(i));
            }

            newShares = StableSwapMath.geometricMean(scaledAmounts);

            if (newShares < MINIMUM_LIQUIDITY) {
                revert InsufficientInitialLiquidity();
            }

            newShares -= MINIMUM_LIQUIDITY;

            for (uint256 i = 0; i < currenciesLength; ++i) {
                actualAmounts[i] = amounts[i];
            }

            _mint(DEAD_ADDRESS, MINIMUM_LIQUIDITY);
        } else {
            uint256[] memory cachedRates = new uint256[](currenciesLength);
            uint256[] memory scaledReserves = new uint256[](currenciesLength);

            for (uint256 i = 0; i < currenciesLength; ++i) {
                cachedRates[i] = _getRate(i);
                scaledReserves[i] = StableSwapMath.scaleTo(reserves[i], cachedRates[i]);
            }

            uint256 minProportion = type(uint256).max;

            for (uint256 i = 0; i < currenciesLength; ++i) {
                uint256 scaledAmount = StableSwapMath.scaleTo(amounts[i], cachedRates[i]);
                uint256 proportion = Math.mulDiv(scaledAmount, currentTotalSupply, scaledReserves[i]);

                if (proportion < minProportion) {
                    minProportion = proportion;
                }
            }

            newShares = minProportion;

            for (uint256 i = 0; i < currenciesLength; ++i) {
                uint256 scaledAmount = (minProportion * scaledReserves[i]) / currentTotalSupply;
                actualAmounts[i] = StableSwapMath.descale(scaledAmount, cachedRates[i]);
            }
        }

        if (newShares < minShares) {
            revert InsufficientShares();
        }

        for (uint256 i = 0; i < currenciesLength; ++i) {
            Currency currency = currencies[i];
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).safeTransferFrom(sender, address(poolManager), actualAmounts[i]);
            poolManager.settle();
            poolManager.mint(address(this), currency.toId(), actualAmounts[i]);
            reserves[i] += actualAmounts[i];
        }

        _mint(sender, newShares);

        emit LiquidityAdded(sender, actualAmounts, newShares);
    }

    /// @dev Callback handler for removing liquidity
    function _handleRemoveLiquidityCallback(bytes calldata data) internal {
        (, uint256 shares, uint256[] memory minAmounts, address sender) =
            abi.decode(data, (uint256, uint256, uint256[], address));

        uint256 userShares = balanceOf(sender);

        if (shares > userShares) {
            revert InsufficientShares();
        }

        uint256 currentTotalSupply = totalSupply();

        uint256[] memory amounts = new uint256[](currenciesLength);

        for (uint256 i = 0; i < currenciesLength; ++i) {
            uint256 amount = (shares * reserves[i]) / currentTotalSupply;

            amounts[i] = amount;

            if (amount < minAmounts[i]) {
                revert InsufficientAmounts();
            }

            Currency currency = currencies[i];

            poolManager.burn(address(this), currency.toId(), amount);
            poolManager.take(currency, sender, amount);

            reserves[i] -= amount;
        }

        _burn(sender, shares);

        emit LiquidityRemoved(sender, amounts, shares);
    }
}

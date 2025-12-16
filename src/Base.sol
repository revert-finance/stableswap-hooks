// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";

import {StableSwapMath} from "src/libraries/StableSwapMath.sol";

/// @notice Abstract base contract for StableSwap hooks providing core state and configuration
abstract contract Base is BaseHook, AccessControlEnumerable {
    /// @notice Fixed tick spacing used for all pools
    /// @dev Set to 1 since concentrated liquidity is not used; only needed to form the pool key
    int24 public constant TICK_SPACING = 1;

    /// @notice Maximum number of currencies allowed in the pool
    uint256 public constant MAX_CURRENCIES = 8;

    /// @notice Number of currencies supported by this hook
    uint256 public immutable currenciesLength;

    /// @notice Scaling rates for each currency to normalize to 1e18 precision
    /// @dev Each rate is calculated as 10^(36 - decimals) to handle tokens with different decimal places
    uint256[] public rates;

    /// @notice Array of currencies supported by this hook
    Currency[] public currencies;

    /// @notice Mapping of valid pool IDs managed by this hook
    /// @dev Used to validate that operations are performed on authorized pools
    mapping(PoolId => bool) poolIds;

    mapping(Currency => uint256) public currenciesIndexes;

    /// @notice Current reserves for each currency in the pool
    uint256[] public reserves;

    /// @notice Thrown when the operation is attempted on a pool that doesn't match this hook's poolId
    error InvalidPoolId();

    /// @notice Thrown when attempting to create a pool with more currencies than MAX_CURRENCIES
    error TooManyCurrencies();

    /// @notice Initializes the base StableSwap hook configuration
    /// @dev Grants DEFAULT_ADMIN_ROLE to the deployer. Initializes all pairwise pools for the provided currencies.
    /// @param _poolManager The Uniswap v4 PoolManager contract
    /// @param _lpFeePercentage The LP fee percentage encoded in the pool key fee field
    /// @param _currencies Array of currencies to create pools for (all pairwise combinations will be initialized)
    constructor(IPoolManager _poolManager, uint256 _lpFeePercentage, Currency[] memory _currencies)
        BaseHook(_poolManager)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        currencies = _currencies;
        currenciesLength = _currencies.length;

        if (currenciesLength > MAX_CURRENCIES) {
            revert TooManyCurrencies();
        }

        reserves = new uint256[](currenciesLength);

        for (uint256 i = 0; i < _currencies.length; ++i) {
            rates.push(StableSwapMath.getRate(_currencies[i]));
            currenciesIndexes[_currencies[i]] = i;

            for (uint256 j = i + 1; j < _currencies.length; ++j) {
                PoolKey memory poolKey = PoolKey({
                    currency0: _currencies[i],
                    currency1: _currencies[j],
                    fee: SafeCast.toUint24(_lpFeePercentage),
                    tickSpacing: TICK_SPACING,
                    hooks: IHooks(address(this))
                });

                _poolManager.initialize(poolKey, 1 << 96);

                poolIds[poolKey.toId()] = true;
            }
        }
    }

    /// @notice Returns the hook permissions required by this contract
    /// @dev Enables beforeInitialize, beforeAddLiquidity, beforeRemoveLiquidity, beforeSwap, beforeDonate, and beforeSwapReturnDelta
    /// @return permissions The hook permissions struct with enabled flags
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

    /// @notice Validates that the given pool key matches this hook's poolId
    /// @dev Reverts with InvalidPoolId if the pool ID doesn't match
    /// @param _poolKey The pool key to validate
    function _validatePoolId(PoolKey calldata _poolKey) internal view {
        if (!poolIds[_poolKey.toId()]) {
            revert InvalidPoolId();
        }
    }

    /// @notice Hook called before pool initialization
    /// @dev Validates that the pool being initialized is managed by this hook
    /// @param _poolKey The pool key of the pool being initialized
    /// @return The function selector to indicate successful validation
    function _beforeInitialize(address, PoolKey calldata _poolKey, uint160) internal view override returns (bytes4) {
        _validatePoolId(_poolKey);

        return BaseHook.beforeInitialize.selector;
    }
}

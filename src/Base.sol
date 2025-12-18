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

/// @notice Configuration for a currency's rate oracle
/// @param oracle The oracle contract address (address(0) if no oracle)
/// @param selector The function selector to call on the oracle (e.g., stEthPerToken())
struct RateOracleConfig {
    address oracle;
    bytes4 selector;
}

/// @notice Abstract base contract for StableSwap hooks providing core state and configuration
abstract contract Base is BaseHook, AccessControlEnumerable {
    /// @notice Fixed tick spacing used for all pools
    /// @dev Set to 1 since concentrated liquidity is not used; only needed to form the pool key
    int24 public constant TICK_SPACING = 1;

    /// @notice Minimum number of currencies required in the pool
    uint256 public constant MIN_CURRENCIES = 2;

    /// @notice Maximum number of currencies allowed in the pool
    uint256 public constant MAX_CURRENCIES = 8;

    /// @notice Number of currencies supported by this hook
    uint256 public immutable currenciesLength;

    /// @notice Base scaling rates for each currency to normalize to 1e18 precision
    /// @dev Each rate is calculated as 10^(36 - decimals) to handle tokens with different decimal places
    uint256[] public rates;

    /// @notice Rate oracle configurations for each currency
    /// @dev If oracle is address(0), uses static rate; otherwise fetches rate from oracle
    RateOracleConfig[] public rateOracles;

    /// @notice Array of currencies supported by this hook
    Currency[] public currencies;

    /// @notice Mapping of valid pool IDs managed by this hook
    /// @dev Used to validate that operations are performed on authorized pools
    mapping(PoolId => bool) public isValidPoolId;

    /// @notice Internal mapping of currency to index+1 (0 means currency not supported)
    /// @dev Stores index+1 to distinguish between index 0 and unsupported currencies
    mapping(Currency => uint256) private _currencyIndex;

    /// @notice Current reserves for each currency in the pool
    uint256[] public reserves;

    /// @notice Thrown when the operation is attempted on a pool that doesn't match this hook's poolId
    error InvalidPoolId();

    /// @notice Thrown when currencies array length is outside valid range [MIN_CURRENCIES, MAX_CURRENCIES]
    error InvalidCurrenciesLength();

    /// @notice Thrown when currencies array is not sorted in ascending order
    error CurrenciesNotSorted();

    /// @notice Thrown when a rate oracle call fails
    error RateOracleCallFailed();

    /// @notice Thrown when rate oracles array length doesn't match currencies length
    error InvalidRateOraclesLength();

    /// @notice Initializes the base StableSwap hook configuration
    /// @dev Grants DEFAULT_ADMIN_ROLE to the deployer. Initializes all pairwise pools for the provided currencies.
    /// @param _poolManager The Uniswap v4 PoolManager contract
    /// @param _lpFeePercentage The LP fee percentage encoded in the pool key fee field
    /// @param _currencies Array of currencies to create pools for, must be sorted in ascending order by address
    /// @param _rateOracles Array of rate oracle configurations for each currency (use address(0) for static rate)
    constructor(
        IPoolManager _poolManager,
        uint256 _lpFeePercentage,
        Currency[] memory _currencies,
        RateOracleConfig[] memory _rateOracles
    ) BaseHook(_poolManager) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        currencies = _currencies;
        currenciesLength = _currencies.length;

        if (currenciesLength < MIN_CURRENCIES || currenciesLength > MAX_CURRENCIES) {
            revert InvalidCurrenciesLength();
        }

        if (_rateOracles.length != currenciesLength) {
            revert InvalidRateOraclesLength();
        }

        reserves = new uint256[](currenciesLength);

        for (uint256 i = 0; i < currenciesLength; ++i) {
            rates.push(StableSwapMath.getRate(_currencies[i]));
            rateOracles.push(_rateOracles[i]);

            _currencyIndex[_currencies[i]] = i + 1;

            for (uint256 j = i + 1; j < currenciesLength; ++j) {
                if (Currency.unwrap(_currencies[j]) <= Currency.unwrap(_currencies[i])) {
                    revert CurrenciesNotSorted();
                }

                PoolKey memory poolKey = PoolKey({
                    currency0: _currencies[i],
                    currency1: _currencies[j],
                    fee: SafeCast.toUint24(_lpFeePercentage),
                    tickSpacing: TICK_SPACING,
                    hooks: IHooks(address(this))
                });

                _poolManager.initialize(poolKey, 1 << 96);

                isValidPoolId[poolKey.toId()] = true;
            }
        }
    }

    /// @notice Returns the index of a currency in the currencies array
    /// @dev Reverts with underflow if currency is not supported
    /// @param _currency The currency to look up
    /// @return The index of the currency in the currencies array
    function getCurrencyIndex(Currency _currency) public view returns (uint256) {
        return _currencyIndex[_currency] - 1;
    }

    /// @notice Gets the rate for a currency, fetching from oracle if configured
    /// @dev If the currency has a rate oracle configured, fetches the rate via static call.
    ///      The fetched rate is assumed to be 1e18 precision and is multiplied with the base rate.
    ///      For currencies without an oracle, returns the static base rate.
    /// @param _index The index of the currency in the currencies array
    /// @return rate The effective rate for the currency
    function _getRate(uint256 _index) internal view returns (uint256 rate) {
        rate = rates[_index];

        RateOracleConfig memory oracleConfig = rateOracles[_index];

        if (oracleConfig.oracle != address(0)) {
            // Fetch rate from oracle (e.g., wstETH.stEthPerToken())
            // The oracle rate is assumed to be 1e18 precision
            (bool success, bytes memory returnData) =
                oracleConfig.oracle.staticcall(abi.encodeWithSelector(oracleConfig.selector));

            if (!success || returnData.length != 32) {
                revert RateOracleCallFailed();
            }

            uint256 fetchedRate = abi.decode(returnData, (uint256));

            // Multiply base rate by fetched rate and divide by precision
            rate = rate * fetchedRate / StableSwapMath.RATE_PRECISION;
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
        if (!isValidPoolId[_poolKey.toId()]) {
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

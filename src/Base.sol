// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";

import {StableSwapMath} from "src/libraries/StableSwapMath.sol";
import {IStableSwapHooksFactory} from "src/interfaces/IStableSwapHooksFactory.sol";

/// @notice Abstract base contract for StableSwap hooks providing core state and configuration
abstract contract Base is BaseHook {
    /// @notice Configuration for a currency's rate oracle
    struct RateOracleConfig {
        address oracle;
        bytes4 selector;
    }

    /// @notice Fixed tick spacing used for all pools
    int24 public constant TICK_SPACING = 1;

    /// @notice Minimum number of currencies required in the pool
    uint256 public constant MIN_CURRENCIES = 2;

    /// @notice Maximum number of currencies allowed in the pool
    uint256 public constant MAX_CURRENCIES = 4;

    /// @notice LP fee percentage (scaled by FEE_PRECISION)
    uint256 public immutable lpFeePercentage;

    /// @notice The factory that deployed this hook
    IStableSwapHooksFactory public immutable factory;

    /// @notice Number of currencies supported by this hook
    uint256 public immutable currenciesLength;

    /// @notice Base scaling rates for each currency to normalize to 1e18 precision
    /// @dev Each rate is calculated as 10^(36 - decimals) to handle tokens with different decimal places
    uint256[] public rates;

    /// @notice Rate oracle configurations for each currency
    RateOracleConfig[] public rateOracles;

    /// @notice Array of currencies supported by this hook
    Currency[] public currencies;

    /// @notice Mapping of pool IDs managed by this hook
    mapping(PoolId => bool) public isValidPoolId;

    /// @notice Current reserves for each currency in the pool
    uint256[] public reserves;

    /// @dev Mapping of currency to index + 1
    mapping(Currency => uint256) private _currencyIndex;

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

    /// @notice Error thrown when caller is not the factory owner
    error OnlyFactoryOwner();

    /// @notice Restricts function access to the factory owner
    modifier onlyFactoryOwner() {
        if (msg.sender != factory.owner()) {
            revert OnlyFactoryOwner();
        }
        _;
    }

    /// @notice Initializes the base StableSwap hook configuration
    /// @dev Initializes all pairwise pools for the provided currencies.
    /// @param _poolManager The Uniswap v4 PoolManager contract
    /// @param _factory The factory that deployed this hook
    /// @param _lpFeePercentage The LP fee percentage encoded in the pool key fee field
    /// @param _currencies Array of currencies to create pools for, must be sorted in ascending order by address
    /// @param _rateOracles Array of rate oracle configurations for each currency (use address(0) for static rate)
    constructor(
        IPoolManager _poolManager,
        IStableSwapHooksFactory _factory,
        uint256 _lpFeePercentage,
        Currency[] memory _currencies,
        RateOracleConfig[] memory _rateOracles
    ) BaseHook(_poolManager) {
        factory = _factory;
        lpFeePercentage = _lpFeePercentage;
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

                isValidPoolId[poolKey.toId()] = true;

                _poolManager.initialize(poolKey, 1 << 96);
            }
        }
    }

    /// @notice Returns the index of a currency in the currencies array
    /// @dev Reverts with underflow if currency is not supported
    /// @param _currency The currency to look up
    function getCurrencyIndex(Currency _currency) public view returns (uint256) {
        return _currencyIndex[_currency] - 1;
    }

    /// @notice Returns the hook permissions required by this contract
    /// @dev Enabled hooks:
    /// 1. beforeInitialize - validates pool is managed by this hook
    /// 2. beforeAddLiquidity - blocks direct liquidity additions via PoolManager
    /// 3. beforeRemoveLiquidity - blocks direct liquidity removals via PoolManager
    /// 4. beforeSwap - executes StableSwap logic instead of default AMM
    /// 5. beforeDonate - blocks donations to the pool
    /// 6. beforeSwapReturnDelta - allows hook to specify swap amounts
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

    /// @dev Gets the rate for a currency, fetching from oracle if configured
    function _getRate(uint256 _index) internal view returns (uint256 rate) {
        rate = rates[_index];

        RateOracleConfig memory oracleConfig = rateOracles[_index];

        if (oracleConfig.oracle != address(0)) {
            bytes memory returnData =
                Address.functionStaticCall(oracleConfig.oracle, abi.encodeWithSelector(oracleConfig.selector));

            if (returnData.length != 32) {
                revert RateOracleCallFailed();
            }

            uint256 fetchedRate = abi.decode(returnData, (uint256));
            rate = rate * fetchedRate / StableSwapMath.RATE_PRECISION;
        }
    }

    /// @dev Validates that the given pool key matches this hook's poolId
    function _validatePoolId(PoolKey calldata _poolKey) internal view {
        if (!isValidPoolId[_poolKey.toId()]) {
            revert InvalidPoolId();
        }
    }

    /// @dev Hook called before pool initialization, validates the pool is managed by this hook
    function _beforeInitialize(address, PoolKey calldata _poolKey, uint160) internal view override returns (bytes4) {
        _validatePoolId(_poolKey);

        return BaseHook.beforeInitialize.selector;
    }
}

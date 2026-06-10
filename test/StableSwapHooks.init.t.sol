// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {stdError} from "forge-std/StdError.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Pool} from "@uniswap/v4-core/src/libraries/Pool.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

import {PoolDonateTest} from "@uniswap/v4-core/src/test/PoolDonateTest.sol";

import {Base} from "src/Base.sol";
import {Liquidity} from "src/Liquidity.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";

contract StableSwapHooksInitTest is StableSwapHooksBaseTest {
    PoolDonateTest private donateRouter;

    function setUp() public override {
        super.setUp();

        donateRouter = new PoolDonateTest(IPoolManager(poolManager));
    }

    // ==========================================================================
    // Pool Initialization
    // ==========================================================================

    function test_initialize_ShouldRevertWhenPoolAlreadyInitialized() public {
        PoolKey memory poolKey = _getPoolKey();

        vm.expectRevert(Pool.PoolAlreadyInitialized.selector);
        poolManager.initialize(poolKey, BASE_SQRT_PRICE_X96);
    }

    function test_initialize_ShouldRevertWhenAnotherPoolUsesHook() public {
        PoolKey memory poolKey = _getPoolKey();
        poolKey.fee = poolKey.fee + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hooks),
                IHooks.beforeInitialize.selector,
                abi.encodeWithSelector(Base.InvalidPoolId.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        poolManager.initialize(poolKey, BASE_SQRT_PRICE_X96);
    }

    function test_initialize_ShouldRevertWhenCurrenciesNotSorted() public {
        Currency[] memory unsortedCurrencies = new Currency[](2);
        unsortedCurrencies[0] = currency1;
        unsortedCurrencies[1] = currency0;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(unsortedCurrencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, code);

        vm.expectRevert(Base.CurrenciesNotSorted.selector);
        factory.deploy(unsortedCurrencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, salt, code);
    }

    function test_initialize_ShouldRevertWhenTooFewCurrencies() public {
        Currency[] memory singleCurrency = new Currency[](1);
        singleCurrency[0] = currency0;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](1);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(singleCurrency, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, code);

        vm.expectRevert(Base.InvalidCurrenciesLength.selector);
        factory.deploy(singleCurrency, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, salt, code);
    }

    function test_initialize_ShouldRevertWhenTooManyCurrencies() public {
        Currency[] memory fiveCurrencies = new Currency[](5);
        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](5);
        for (uint160 i = 0; i < 5; i++) {
            fiveCurrencies[i] = Currency.wrap(address(uint160(i + 1)));
            rateOracles[i] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        }

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(fiveCurrencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, code);

        vm.expectRevert(Base.InvalidCurrenciesLength.selector);
        factory.deploy(fiveCurrencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, salt, code);
    }

    function test_initialize_ShouldRevertWhenLpFeePercentageExceedsPrecision() public {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        uint256 invalidFee = hooks.FEE_PRECISION() + 1;

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, invalidFee, BASE_AMP, code);

        vm.expectRevert(Base.InvalidLpFeePercentage.selector);
        factory.deploy(currencies, rateOracles, invalidFee, BASE_AMP, salt, code);
    }

    function test_initialize_ShouldRevertWhenLpFeePercentageEqualsPrecision() public {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        uint256 maxFee = hooks.FEE_PRECISION();

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, maxFee, BASE_AMP, code);

        vm.expectRevert(Base.InvalidLpFeePercentage.selector);
        factory.deploy(currencies, rateOracles, maxFee, BASE_AMP, salt, code);
    }

    function test_initialize_ShouldSetCorrectPoolId() public view {
        PoolKey memory poolKey = _getPoolKey();
        PoolId poolId = poolKey.toId();

        assertTrue(hooks.isValidPoolId(poolId));
    }

    // ==========================================================================
    // Currency Configuration
    // ==========================================================================

    function test_initialize_ShouldSetCorrectCurrencies() public view {
        assertEq(Currency.unwrap(hooks.currencies(0)), Currency.unwrap(currency0));
        assertEq(Currency.unwrap(hooks.currencies(1)), Currency.unwrap(currency1));
    }

    function test_initialize_ShouldSetCorrectCurrenciesLength() public view {
        assertEq(hooks.currenciesLength(), 2);
    }

    function test_initialize_ShouldSetCorrectRates() public view {
        uint8 decimals0 = IERC20Metadata(Currency.unwrap(currency0)).decimals();
        uint8 decimals1 = IERC20Metadata(Currency.unwrap(currency1)).decimals();

        uint256 expectedRate0 = 10 ** (36 - decimals0);
        uint256 expectedRate1 = 10 ** (36 - decimals1);

        assertEq(hooks.rates(0), expectedRate0);
        assertEq(hooks.rates(1), expectedRate1);
    }

    function test_initialize_ShouldInitializeReservesToZero() public view {
        assertEq(hooks.reserves(0), 0);
        assertEq(hooks.reserves(1), 0);
    }

    function test_getCurrencyIndex_ShouldReturnCorrectIndex() public view {
        assertEq(hooks.getCurrencyIndex(currency0), 0);
        assertEq(hooks.getCurrencyIndex(currency1), 1);
    }

    function test_getCurrencyIndex_ShouldRevertForUnsupportedCurrency() public {
        Currency unsupportedCurrency = Currency.wrap(address(0xdead));

        vm.expectRevert(stdError.arithmeticError);
        hooks.getCurrencyIndex(unsupportedCurrency);
    }

    // ==========================================================================
    // Hook Permissions
    // ==========================================================================

    function test_getHookPermissions_ShouldReturnCorrectFlags() public view {
        Hooks.Permissions memory permissions = hooks.getHookPermissions();

        assertTrue(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertTrue(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertTrue(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertFalse(permissions.afterSwap);
        assertTrue(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
        assertTrue(permissions.beforeSwapReturnDelta);
        assertFalse(permissions.afterSwapReturnDelta);
        assertFalse(permissions.afterAddLiquidityReturnDelta);
        assertFalse(permissions.afterRemoveLiquidityReturnDelta);
    }

    function test_TICK_SPACING_ShouldBeOne() public view {
        assertEq(hooks.TICK_SPACING(), 1);
    }

    function test_MAX_CURRENCIES_ShouldBeFour() public view {
        assertEq(hooks.MAX_CURRENCIES(), 4);
    }

    function test_beforeDonate_ShouldRevertWithUseHookLiquidityModifiers() public {
        PoolKey memory poolKey = _getPoolKey();

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hooks),
                IHooks.beforeDonate.selector,
                abi.encodeWithSelector(Liquidity.UseHookLiquidityModifiers.selector, address(hooks)),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        donateRouter.donate(poolKey, 100, 100, bytes(""));
    }

    // ==========================================================================
    // Multi-Currency (hooks3)
    // ==========================================================================

    function test_hooks3_ShouldSetCorrectCurrenciesLength() public view {
        assertEq(hooks3.currenciesLength(), 3);
    }

    function test_hooks3_ShouldSetCorrectCurrencies() public view {
        assertEq(Currency.unwrap(hooks3.currencies(0)), Currency.unwrap(currency0));
        assertEq(Currency.unwrap(hooks3.currencies(1)), Currency.unwrap(currency1));
        assertEq(Currency.unwrap(hooks3.currencies(2)), Currency.unwrap(currency2));
    }

    function test_hooks3_ShouldSetCorrectRates() public view {
        uint8 decimals0 = IERC20Metadata(Currency.unwrap(currency0)).decimals();
        uint8 decimals1 = IERC20Metadata(Currency.unwrap(currency1)).decimals();
        uint8 decimals2 = IERC20Metadata(Currency.unwrap(currency2)).decimals();

        assertEq(hooks3.rates(0), 10 ** (36 - decimals0));
        assertEq(hooks3.rates(1), 10 ** (36 - decimals1));
        assertEq(hooks3.rates(2), 10 ** (36 - decimals2));
    }

    function test_hooks3_ShouldInitializeReservesToZero() public view {
        assertEq(hooks3.reserves(0), 0);
        assertEq(hooks3.reserves(1), 0);
        assertEq(hooks3.reserves(2), 0);
    }

    function test_hooks3_getCurrencyIndex_ShouldReturnCorrectIndex() public view {
        assertEq(hooks3.getCurrencyIndex(currency0), 0);
        assertEq(hooks3.getCurrencyIndex(currency1), 1);
        assertEq(hooks3.getCurrencyIndex(currency2), 2);
    }

    function test_hooks3_ShouldCreateThreeValidPoolIds() public view {
        PoolKey memory poolKey01 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(BASE_LP_FEE_PERCENTAGE),
            tickSpacing: hooks3.TICK_SPACING(),
            hooks: IHooks(address(hooks3))
        });

        PoolKey memory poolKey02 = PoolKey({
            currency0: currency0,
            currency1: currency2,
            fee: uint24(BASE_LP_FEE_PERCENTAGE),
            tickSpacing: hooks3.TICK_SPACING(),
            hooks: IHooks(address(hooks3))
        });

        PoolKey memory poolKey12 = PoolKey({
            currency0: currency1,
            currency1: currency2,
            fee: uint24(BASE_LP_FEE_PERCENTAGE),
            tickSpacing: hooks3.TICK_SPACING(),
            hooks: IHooks(address(hooks3))
        });

        assertTrue(hooks3.isValidPoolId(poolKey01.toId()));
        assertTrue(hooks3.isValidPoolId(poolKey02.toId()));
        assertTrue(hooks3.isValidPoolId(poolKey12.toId()));
    }
}

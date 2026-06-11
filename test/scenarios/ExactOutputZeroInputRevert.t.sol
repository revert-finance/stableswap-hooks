// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {Base} from "src/Base.sol";
import {Swap} from "src/Swap.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactoryHarness} from "test/testUtils/StableSwapHooksFactoryHarness.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";
import {MockERC20} from "test/scenarios/mocks/MockERC20.sol";

contract ExactOutputLowDecimalInputRevertTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 private constant LP_FEE_PERCENTAGE = 500;
    uint256 private constant BASE_AMP = 100;
    uint256 private constant INITIAL_LOW_DECIMAL_LIQUIDITY = 1_000_000;
    uint256 private constant INITIAL_NORMAL_LIQUIDITY = 1_000_000e18;
    uint256 private constant NORMAL_OUT = 0.999e18;

    StableSwapHooksFactoryHarness private factory;
    StableSwapHooks private hooks;
    MockERC20 private lowDecimalToken;
    MockERC20 private normalToken;
    Currency private lowDecimalCurrency;
    Currency private normalCurrency;
    uint256 private lowDecimalIndex;
    uint256 private normalIndex;
    int24 private tickSpacing;
    address private lp;
    address private swapper;

    function setUp() public override {
        super.setUp();

        lp = makeAddr("lp");
        swapper = makeAddr("swapper");

        lowDecimalToken = new MockERC20("Low Decimal", "LOW", 0);
        normalToken = new MockERC20("Normal 18", "N18", 18);
        lowDecimalCurrency = Currency.wrap(address(lowDecimalToken));
        normalCurrency = Currency.wrap(address(normalToken));

        factory = new StableSwapHooksFactoryHarness(
            IPoolManager(poolManager),
            makeAddr("owner"),
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );

        _deployPool();
        tickSpacing = hooks.TICK_SPACING();
        _seedPool();
        _fundSwapper();
    }

    function test_exactOutput_lowDecimalInputRevertsWithZeroInput() public {
        uint256 swapperLowBefore = lowDecimalToken.balanceOf(swapper);
        uint256 reserveLowBefore = hooks.reserves(lowDecimalIndex);
        uint256 reserveNormalBefore = hooks.reserves(normalIndex);

        vm.expectRevert(_expectedRevert());
        _executeExactOutput(lowDecimalCurrency, normalCurrency, NORMAL_OUT);

        assertEq(lowDecimalToken.balanceOf(swapper), swapperLowBefore, "swapper paid no low-decimal input");
        assertEq(hooks.reserves(lowDecimalIndex), reserveLowBefore, "input reserve unchanged");
        assertEq(hooks.reserves(normalIndex), reserveNormalBefore, "output reserve protected");
    }

    function test_exactOutput_lowDecimalInputRevertsOnEveryAttempt() public {
        uint256 reserveNormalBefore = hooks.reserves(normalIndex);

        for (uint256 i = 0; i < 10; ++i) {
            vm.expectRevert(_expectedRevert());
            _executeExactOutput(lowDecimalCurrency, normalCurrency, NORMAL_OUT);
        }

        assertEq(hooks.reserves(normalIndex), reserveNormalBefore, "no cumulative output loss");
    }

    function _expectedRevert() private view returns (bytes memory) {
        return abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            address(hooks),
            IHooks.beforeSwap.selector,
            abi.encodeWithSelector(Swap.ZeroInput.selector),
            abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        );
    }

    function _deployPool() private {
        Currency[] memory currencies = new Currency[](2);
        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);

        if (Currency.unwrap(lowDecimalCurrency) < Currency.unwrap(normalCurrency)) {
            currencies[0] = lowDecimalCurrency;
            currencies[1] = normalCurrency;
            lowDecimalIndex = 0;
            normalIndex = 1;
        } else {
            currencies[0] = normalCurrency;
            currencies[1] = lowDecimalCurrency;
            normalIndex = 0;
            lowDecimalIndex = 1;
        }

        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, BASE_AMP, code);
        hooks = StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, BASE_AMP, salt, code));
    }

    function _seedPool() private {
        lowDecimalToken.mint(lp, INITIAL_LOW_DECIMAL_LIQUIDITY);
        normalToken.mint(lp, INITIAL_NORMAL_LIQUIDITY);

        uint256[] memory amounts = new uint256[](2);
        amounts[lowDecimalIndex] = INITIAL_LOW_DECIMAL_LIQUIDITY;
        amounts[normalIndex] = INITIAL_NORMAL_LIQUIDITY;

        vm.startPrank(lp);
        IERC20(address(lowDecimalToken)).forceApprove(address(hooks), type(uint256).max);
        IERC20(address(normalToken)).forceApprove(address(hooks), type(uint256).max);
        hooks.addLiquidity(amounts, new uint256[](2), 0);
        vm.stopPrank();
    }

    function _fundSwapper() private {
        lowDecimalToken.mint(swapper, 1_000_000);

        vm.startPrank(swapper);
        IERC20(address(lowDecimalToken)).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(address(lowDecimalToken), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _executeExactOutput(Currency inputCurrency, Currency outputCurrency, uint256 amountOut) private {
        bool zeroForOne = Currency.unwrap(inputCurrency) < Currency.unwrap(outputCurrency);
        PoolKey memory poolKey = PoolKey({
            currency0: zeroForOne ? inputCurrency : outputCurrency,
            currency1: zeroForOne ? outputCurrency : inputCurrency,
            fee: uint24(LP_FEE_PERCENTAGE),
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hooks))
        });

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountOut: uint128(amountOut),
                amountInMaximum: type(uint128).max,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(inputCurrency, type(uint128).max);
        params[2] = abi.encode(outputCurrency, amountOut);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.prank(swapper);
        universalRouter.execute(commands, inputs, block.timestamp + 100);
    }
}

contract ExactOutputHighDecimalOutputRevertTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 private constant LP_FEE_PERCENTAGE = 500;
    uint256 private constant AMP = 100;

    StableSwapHooksFactoryHarness private factory;
    StableSwapHooks private hooks;

    MockERC20 private normalToken;
    MockERC20 private highDecimalsToken;
    Currency private normalCurrency;
    Currency private highDecimalsCurrency;
    int24 private tickSpacing;

    address private liquidityProvider = makeAddr("liquidityProvider");
    address private swapper = makeAddr("swapper");

    function setUp() public override {
        super.setUp();
        vm.warp(1731337000);

        normalToken = new MockERC20("Normal Token", "NORM", 18);
        highDecimalsToken = new MockERC20("High Decimals Token", "HIGH", 19);

        normalCurrency = Currency.wrap(address(normalToken));
        highDecimalsCurrency = Currency.wrap(address(highDecimalsToken));

        factory = new StableSwapHooksFactoryHarness(
            IPoolManager(poolManager),
            makeAddr("admin"),
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );

        Currency[] memory currencies = _sortedCurrencies();
        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, code);
        hooks = StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, salt, code));
        tickSpacing = hooks.TICK_SPACING();

        normalToken.mint(liquidityProvider, 2_000_000 ether);
        highDecimalsToken.mint(liquidityProvider, 20_000_000 * 1e18);
        normalToken.mint(swapper, 1 ether);

        vm.startPrank(liquidityProvider);
        IERC20(address(normalToken)).forceApprove(address(hooks), type(uint256).max);
        IERC20(address(highDecimalsToken)).forceApprove(address(hooks), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper);
        IERC20(address(normalToken)).forceApprove(address(permit2), type(uint256).max);
        IERC20(address(highDecimalsToken)).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(address(normalToken), address(universalRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(highDecimalsToken), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amounts[i] = Currency.unwrap(currencies[i]) == address(normalToken) ? 1_000_000 ether : 10_000_000 * 1e18;
        }

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, new uint256[](2), 0);
    }

    function test_exactOutput_highDecimalOutputRevertsWithZeroInput() public {
        uint256 normalBefore = normalToken.balanceOf(swapper);
        uint256 highDecimalsBefore = highDecimalsToken.balanceOf(swapper);
        uint256 inputReserveBefore = _reserveOf(normalCurrency);
        uint256 outputReserveBefore = _reserveOf(highDecimalsCurrency);

        vm.expectRevert(_expectedRevert());
        _exactOutputSwap(normalCurrency, highDecimalsCurrency, 1);

        assertEq(normalToken.balanceOf(swapper), normalBefore, "swapper paid no input");
        assertEq(highDecimalsToken.balanceOf(swapper), highDecimalsBefore, "swapper received no output");
        assertEq(_reserveOf(normalCurrency), inputReserveBefore, "input reserve unchanged");
        assertEq(_reserveOf(highDecimalsCurrency), outputReserveBefore, "output reserve protected");
    }

    function _expectedRevert() private view returns (bytes memory) {
        return abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            address(hooks),
            IHooks.beforeSwap.selector,
            abi.encodeWithSelector(Swap.ZeroInput.selector),
            abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        );
    }

    function _exactOutputSwap(Currency inputCurrency, Currency outputCurrency, uint256 amountOut) private {
        PoolKey memory poolKey = _poolKey(inputCurrency, outputCurrency);
        bool zeroForOne = Currency.unwrap(inputCurrency) < Currency.unwrap(outputCurrency);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountOut: uint128(amountOut),
                amountInMaximum: type(uint128).max,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(inputCurrency, type(uint128).max);
        params[2] = abi.encode(outputCurrency, amountOut);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.prank(swapper);
        universalRouter.execute(commands, inputs, block.timestamp + 100);
    }

    function _poolKey(Currency a, Currency b) private view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.unwrap(a) < Currency.unwrap(b) ? a : b,
            currency1: Currency.unwrap(a) < Currency.unwrap(b) ? b : a,
            fee: uint24(LP_FEE_PERCENTAGE),
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hooks))
        });
    }

    function _sortedCurrencies() private view returns (Currency[] memory currencies) {
        currencies = new Currency[](2);
        if (address(normalToken) < address(highDecimalsToken)) {
            currencies[0] = normalCurrency;
            currencies[1] = highDecimalsCurrency;
        } else {
            currencies[0] = highDecimalsCurrency;
            currencies[1] = normalCurrency;
        }
    }

    function _reserveOf(Currency currency) private view returns (uint256) {
        return hooks.reserves(hooks.getCurrencyIndex(currency));
    }
}

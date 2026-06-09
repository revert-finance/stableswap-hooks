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
import {StableSwapMath} from "src/libraries/StableSwapMath.sol";
import {StableSwapHooksFactoryHarness} from "test/testUtils/StableSwapHooksFactoryHarness.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";
import {MockERC20} from "test/scenarios/mocks/MockERC20.sol";

contract StableSwapMathProbe {
    uint256 private constant BASE_AMP = 100;

    function targetInputReserve(
        uint256 inputReserve,
        uint256 outputReserve,
        uint256 amountOut,
        uint256 tokenInIndex,
        uint256 tokenOutIndex
    ) external pure returns (uint256) {
        uint256[] memory scaledReserves = new uint256[](2);
        scaledReserves[tokenInIndex] = inputReserve;
        scaledReserves[tokenOutIndex] = outputReserve;

        uint256 amp = BASE_AMP * StableSwapMath.AMP_PRECISION;
        uint256 invariant = StableSwapMath.getInvariant(scaledReserves, amp);
        uint256 newOutputReserve = outputReserve - amountOut;

        return
            StableSwapMath.getTargetReserves(
                tokenOutIndex, tokenInIndex, newOutputReserve, scaledReserves, amp, invariant
            );
    }
}

contract ExactOutputZeroInputGuardTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 private constant LP_FEE_PERCENTAGE = 500;
    uint256 private constant BASE_AMP = 100;
    uint256 private constant TINY_INPUT_SIDE_LIQUIDITY = 1_000;
    uint256 private constant HUGE_OUTPUT_SIDE_LIQUIDITY = 3e24;
    uint256 private constant FREE_OUTPUT = 1e21;

    StableSwapHooksFactoryHarness private factory;
    StableSwapHooks private hooks;
    MockERC20 private inputSideToken;
    MockERC20 private outputSideToken;
    StableSwapMathProbe private mathProbe;
    Currency private inputSideCurrency;
    Currency private outputSideCurrency;
    uint256 private inputSideIndex;
    uint256 private outputSideIndex;
    int24 private tickSpacing;
    address private lp;
    address private attacker;

    function setUp() public override {
        super.setUp();

        lp = makeAddr("lp");
        attacker = makeAddr("attacker");

        inputSideToken = new MockERC20("Normal Input Side", "NIN", 18);
        outputSideToken = new MockERC20("Normal Output Side", "NOUT", 18);
        mathProbe = new StableSwapMathProbe();
        inputSideCurrency = Currency.wrap(address(inputSideToken));
        outputSideCurrency = Currency.wrap(address(outputSideToken));

        factory = new StableSwapHooksFactoryHarness(
            IPoolManager(poolManager),
            makeAddr("owner"),
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );

        _deployPool();
        tickSpacing = hooks.TICK_SPACING();
        _seedImbalancedPool();
        _fundAttacker();
    }

    function test_exactOutput_imbalancedPool_shouldRevertOnZeroInput() public {
        uint256 attackerInputBefore = inputSideToken.balanceOf(attacker);
        uint256 attackerOutputBefore = outputSideToken.balanceOf(attacker);
        uint256 reserveInputBefore = hooks.reserves(inputSideIndex);
        uint256 reserveOutputBefore = hooks.reserves(outputSideIndex);

        vm.expectRevert(_expectedRevert());
        _executeExactOutput(inputSideCurrency, outputSideCurrency, FREE_OUTPUT);

        assertEq(inputSideToken.balanceOf(attacker), attackerInputBefore, "attacker balance unchanged");
        assertEq(outputSideToken.balanceOf(attacker), attackerOutputBefore, "attacker received no output");
        assertEq(hooks.reserves(inputSideIndex), reserveInputBefore, "input reserve unchanged");
        assertEq(hooks.reserves(outputSideIndex), reserveOutputBefore, "output reserve protected");
    }

    function test_exactOutput_imbalancedPool_shouldRevertOnEveryAttempt() public {
        uint256 reserveOutputBefore = hooks.reserves(outputSideIndex);

        for (uint256 i = 0; i < 3; ++i) {
            vm.expectRevert(_expectedRevert());
            _executeExactOutput(inputSideCurrency, outputSideCurrency, FREE_OUTPUT);
        }

        assertEq(hooks.reserves(outputSideIndex), reserveOutputBefore, "no cumulative loss");
    }

    function test_exactOutput_imbalancedPool_solverReturnsZeroInputDelta() public view {
        uint256 inputScaled = StableSwapMath.scaleTo(TINY_INPUT_SIDE_LIQUIDITY, 1e18);
        uint256 outputScaled = StableSwapMath.scaleTo(HUGE_OUTPUT_SIDE_LIQUIDITY, 1e18);

        uint256 targetInput =
            mathProbe.targetInputReserve(inputScaled, outputScaled, FREE_OUTPUT, inputSideIndex, outputSideIndex);

        assertEq(targetInput, inputScaled, "solver required zero input-side reserve increase for nonzero output");
    }

    function _expectedRevert() private view returns (bytes memory) {
        return abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            address(hooks),
            IHooks.beforeSwap.selector,
            abi.encodeWithSelector(Swap.ZeroInputForNonZeroOutput.selector),
            abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        );
    }

    function _deployPool() private {
        (hooks, inputSideIndex, outputSideIndex) = _deployPoolFor(inputSideCurrency, outputSideCurrency);
    }

    function _deployPoolFor(Currency currencyA, Currency currencyB)
        private
        returns (StableSwapHooks deployedHooks, uint256 indexA, uint256 indexB)
    {
        Currency[] memory currencies = new Currency[](2);
        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);

        if (Currency.unwrap(currencyA) < Currency.unwrap(currencyB)) {
            currencies[0] = currencyA;
            currencies[1] = currencyB;
            indexA = 0;
            indexB = 1;
        } else {
            currencies[0] = currencyB;
            currencies[1] = currencyA;
            indexB = 0;
            indexA = 1;
        }

        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, BASE_AMP, code);
        deployedHooks =
            StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, BASE_AMP, salt, code));
    }

    function _seedImbalancedPool() private {
        inputSideToken.mint(lp, TINY_INPUT_SIDE_LIQUIDITY);
        outputSideToken.mint(lp, HUGE_OUTPUT_SIDE_LIQUIDITY);

        uint256[] memory amounts = new uint256[](2);
        amounts[inputSideIndex] = TINY_INPUT_SIDE_LIQUIDITY;
        amounts[outputSideIndex] = HUGE_OUTPUT_SIDE_LIQUIDITY;

        vm.startPrank(lp);
        IERC20(address(inputSideToken)).forceApprove(address(hooks), type(uint256).max);
        IERC20(address(outputSideToken)).forceApprove(address(hooks), type(uint256).max);
        hooks.addLiquidity(amounts, new uint256[](2), 0);
        vm.stopPrank();
    }

    function _fundAttacker() private {
        inputSideToken.mint(attacker, 1e18);
        vm.startPrank(attacker);
        IERC20(address(inputSideToken)).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(address(inputSideToken), address(universalRouter), type(uint160).max, type(uint48).max);
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

        vm.prank(attacker);
        universalRouter.execute(commands, inputs, block.timestamp + 100);
    }
}

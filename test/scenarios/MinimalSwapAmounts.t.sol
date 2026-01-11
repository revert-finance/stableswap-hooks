// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";
import {console} from "forge-std/console.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";
import {MockERC20} from "test/scenarios/mocks/MockERC20.sol";

/// @notice Tests swap behavior with minimal amounts (1 wei)
/// @dev Uses custom 12-decimal tokens to test edge cases
contract MinimalSwapAmountsTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 internal constant LP_FEE_PERCENTAGE = 300;
    uint256 internal constant AMP = 100;
    uint256 internal constant LIQUIDITY_AMOUNT = 1_000_000;

    uint8 internal constant TOKEN_DECIMALS = 18;

    Currency internal tokenA;
    Currency internal tokenB;

    StableSwapHooksFactory internal factory;
    StableSwapHooks internal hooks;

    address internal liquidityProvider;
    address internal swapper;

    function setUp() public override {
        super.setUp();

        if (block.chainid == 31337) {
            vm.warp(1731337000);
        }

        liquidityProvider = makeAddr("liquidityProvider");
        swapper = makeAddr("swapper");

        _deployMockTokens();

        factory = new StableSwapHooksFactory(
            IPoolManager(poolManager),
            makeAddr("admin"),
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );

        _deployHooks();
        _dealTokens();
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
    }

    /// @notice 1 wei exact input swap returns 0 wei output (minimum 1 wei fee applies)
    function test_exactInput_oneWei_minimumFeeApplied() public {
        uint256 amountIn = 1;
        uint256 amountOut = _executeSwapAndGetOutput(true, amountIn);

        console.log("1 wei exact input swap:");
        console.log("Amount In:  ", amountIn);
        console.log("Amount Out: ", amountOut);

        // Minimum 1 wei LP fee is enforced, so 1 wei in - 1 wei fee = 0 wei out
        assertEq(amountOut, 0);
    }

    /// @notice 1 wei exact output swap requires at least 2 wei input (1 output + 1 min fee)
    function test_exactOutput_oneWei_requiresMoreInput() public {
        uint256 amountOut = 1;

        uint256 balanceABefore = IERC20(Currency.unwrap(tokenA)).balanceOf(swapper);
        uint256 balanceBBefore = IERC20(Currency.unwrap(tokenB)).balanceOf(swapper);

        _executeExactOutputSwap(true, amountOut);

        uint256 balanceAAfter = IERC20(Currency.unwrap(tokenA)).balanceOf(swapper);
        uint256 balanceBAfter = IERC20(Currency.unwrap(tokenB)).balanceOf(swapper);

        uint256 amountIn = balanceABefore - balanceAAfter;
        uint256 actualOut = balanceBAfter - balanceBBefore;

        console.log("1 wei exact output swap:");
        console.log("Amount In:  ", amountIn);
        console.log("Amount Out: ", actualOut);

        assertEq(actualOut, amountOut);
        // With minimum 1 wei fee, need at least 2 wei input for 1 wei output
        assertGe(amountIn, 2);
    }

    /// @notice Small amounts pay HIGHER effective fees due to minimum fee
    function test_smallAmounts_minimumFeeImpact() public {
        uint256 smallAmount = 100;
        uint256 largeAmount = 1e18; // 1 token

        uint256 smallOut = _executeSwapAndGetOutput(true, smallAmount);
        uint256 largeOut = _executeSwapAndGetOutput(true, largeAmount);

        uint256 smallEffectiveFee = smallAmount > smallOut ? (smallAmount - smallOut) * 1e6 / smallAmount : 0;
        uint256 largeEffectiveFee = (largeAmount - largeOut) * 1e6 / largeAmount;

        console.log("Small amount (100 wei):");
        console.log("  In:            ", smallAmount);
        console.log("  Out:           ", smallOut);
        console.log("  Effective fee: ", smallEffectiveFee, "ppm");

        console.log("Large amount (1 token):");
        console.log("  In:            ", largeAmount);
        console.log("  Out:           ", largeOut);
        console.log("  Effective fee: ", largeEffectiveFee, "ppm");

        // With minimum fee, small amounts pay higher effective fees
        // 1 wei min fee on 100 wei = 10000 ppm (1%) vs normal 300 ppm
        assertGe(smallEffectiveFee, largeEffectiveFee);
    }

    /// @notice SECURITY: Verify tiny swaps cannot extract value (output never > input)
    function test_security_tinySwaps_cannotExtractValue() public {
        // Try various tiny amounts - output should NEVER exceed input
        for (uint256 i = 1; i <= 100; i++) {
            uint256 amountOut = _executeSwapAndGetOutput(true, i);
            assertLe(amountOut, i, "Output exceeded input - potential exploit!");
        }
    }

    /// @notice SECURITY: Roundtrip swaps should not profit the attacker
    function test_security_roundtrip_noProfitPossible() public {
        uint256 startBalanceA = IERC20(Currency.unwrap(tokenA)).balanceOf(swapper);
        uint256 startBalanceB = IERC20(Currency.unwrap(tokenB)).balanceOf(swapper);

        // Do 100 roundtrip swaps with 1 wei
        for (uint256 i = 0; i < 100; i++) {
            _executeSwapAndGetOutput(true, 1); // A -> B
            _executeSwapAndGetOutput(false, 1); // B -> A
        }

        uint256 endBalanceA = IERC20(Currency.unwrap(tokenA)).balanceOf(swapper);
        uint256 endBalanceB = IERC20(Currency.unwrap(tokenB)).balanceOf(swapper);

        // Attacker should not have more of either token
        assertLe(endBalanceA, startBalanceA, "Attacker profited in token A");
        assertLe(endBalanceB, startBalanceB, "Attacker profited in token B");

        console.log("Roundtrip attack (100 iterations):");
        console.log("  Token A delta:", startBalanceA > endBalanceA ? startBalanceA - endBalanceA : 0, "(lost)");
        console.log("  Token B delta:", startBalanceB > endBalanceB ? startBalanceB - endBalanceB : 0, "(lost)");
    }

    /// @notice SECURITY: Test on imbalanced pool - tiny swaps should still not profit
    function test_security_imbalancedPool_tinySwapsCannotProfit() public {
        // First create imbalance by doing a large swap (10% of pool)
        uint256 largeSwap = 100_000 * 10 ** TOKEN_DECIMALS;
        _executeSwapAndGetOutput(true, largeSwap);

        // Now try tiny swaps in the "favorable" direction (where price favors B->A)
        uint256 startBalanceA = IERC20(Currency.unwrap(tokenA)).balanceOf(swapper);
        uint256 startBalanceB = IERC20(Currency.unwrap(tokenB)).balanceOf(swapper);

        // Try 100 tiny swaps of 1 wei in the reverse direction
        for (uint256 i = 0; i < 100; i++) {
            uint256 amountOut = _executeSwapAndGetOutput(false, 1); // B -> A
            assertLe(amountOut, 1, "Got more than 1 wei out on imbalanced pool!");
        }

        uint256 endBalanceA = IERC20(Currency.unwrap(tokenA)).balanceOf(swapper);
        uint256 endBalanceB = IERC20(Currency.unwrap(tokenB)).balanceOf(swapper);

        console.log("Imbalanced pool tiny swaps (100x 1 wei B->A):");
        console.log("  Token A gained:", endBalanceA - startBalanceA);
        console.log("  Token B spent: ", startBalanceB - endBalanceB);

        // Net result: spent at least as much as gained (no profit)
        uint256 tokenAGained = endBalanceA - startBalanceA;
        uint256 tokenBSpent = startBalanceB - endBalanceB;
        assertGe(tokenBSpent, tokenAGained, "Attacker profited on imbalanced pool");
    }

    /// @notice SECURITY: Even with maximum imbalance, tiny swaps break even
    function test_security_extremeImbalance_tinySwapsBreakEven() public {
        // Create extreme imbalance - swap 40% of pool
        uint256 hugeSwap = 400_000 * 10 ** TOKEN_DECIMALS;
        _executeSwapAndGetOutput(true, hugeSwap);

        // Single 1 wei swap in favorable direction
        uint256 amountOut = _executeSwapAndGetOutput(false, 1);

        console.log("Extreme imbalance (40% swap) then 1 wei:");
        console.log("  1 wei B in -> ", amountOut, "wei A out");

        // Even with extreme imbalance, 1 wei should give at most 1 wei
        assertLe(amountOut, 1, "Extreme imbalance exploitation possible!");
    }

    /// @notice FUZZ: Output should never exceed input for any swap amount
    function testFuzz_outputNeverExceedsInput(uint256 _amountIn) public {
        // Bound from 1 wei to 2x pool size to cover extreme scenarios
        _amountIn = bound(_amountIn, 1, LIQUIDITY_AMOUNT * 10 ** TOKEN_DECIMALS * 2);

        uint256 amountOut = _executeSwapAndGetOutput(true, _amountIn);

        assertLe(amountOut, _amountIn, "Output exceeded input - potential exploit!");
    }

    /// @notice FUZZ: Roundtrip swaps should never profit
    function testFuzz_roundtripNeverProfits(uint256 _amountIn) public {
        // Bound from 1 wei to 2x pool size to cover extreme scenarios
        _amountIn = bound(_amountIn, 1, LIQUIDITY_AMOUNT * 10 ** TOKEN_DECIMALS * 2);

        uint256 startBalanceA = IERC20(Currency.unwrap(tokenA)).balanceOf(swapper);

        // A -> B
        uint256 amountOutB = _executeSwapAndGetOutput(true, _amountIn);

        // B -> A (swap back whatever we got)
        if (amountOutB > 0) {
            _executeSwapAndGetOutput(false, amountOutB);
        }

        uint256 endBalanceA = IERC20(Currency.unwrap(tokenA)).balanceOf(swapper);

        assertLe(endBalanceA, startBalanceA, "Roundtrip profit - potential exploit!");
    }

    /// @notice FUZZ: Exact output swaps should require more input than output (fees charged)
    function testFuzz_exactOutput_inputExceedsOutput(uint256 _amountOut) public {
        // Bound to reasonable range: 1 wei to 50% of pool (can't get more than pool has)
        _amountOut = bound(_amountOut, 1, LIQUIDITY_AMOUNT * 10 ** TOKEN_DECIMALS / 2);

        uint256 balanceABefore = IERC20(Currency.unwrap(tokenA)).balanceOf(swapper);
        uint256 balanceBBefore = IERC20(Currency.unwrap(tokenB)).balanceOf(swapper);

        _executeExactOutputSwap(true, _amountOut);

        uint256 balanceAAfter = IERC20(Currency.unwrap(tokenA)).balanceOf(swapper);
        uint256 balanceBAfter = IERC20(Currency.unwrap(tokenB)).balanceOf(swapper);

        uint256 amountIn = balanceABefore - balanceAAfter;
        uint256 actualOut = balanceBAfter - balanceBBefore;

        // Got what we asked for
        assertEq(actualOut, _amountOut, "Didn't receive exact output amount");

        // Input should exceed output (fees charged)
        assertGt(amountIn, actualOut, "Input not greater than output - no fees charged!");
    }

    /// @notice Dust amounts near fee threshold
    function test_dustAmounts_nearFeeThreshold() public {
        // With 0.03% LP fee, amounts below ~3333 wei should lose significant percentage to fees
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 10;
        amounts[1] = 100;
        amounts[2] = 1000;
        amounts[3] = 10000;
        amounts[4] = 100000;

        console.log("Dust amount analysis:");

        uint256 previousLossBps = type(uint256).max;

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amountOut = _executeSwapAndGetOutput(true, amounts[i]);
            uint256 lossBps = amounts[i] > 0 ? (amounts[i] - amountOut) * 10000 / amounts[i] : 0;

            console.log("  Amount:", amounts[i], "Out:", amountOut);
            console.log("  Loss bps:", lossBps);

            // Fees are always charged (output < input)
            assertLt(amountOut, amounts[i], "No fee charged on dust amount");

            // Larger amounts have proportionally lower fees (converges to LP fee rate)
            assertLe(lossBps, previousLossBps, "Larger amount had higher effective fee");
            previousLossBps = lossBps;
        }

        // Largest amount should converge to ~3 bps (0.03% LP fee)
        uint256 finalOut = _executeSwapAndGetOutput(true, amounts[4]);
        uint256 finalLossBps = (amounts[4] - finalOut) * 10000 / amounts[4];
        assertLe(finalLossBps, 10, "Large amount fee not converging to LP fee rate");
    }

    function _deployMockTokens() private {
        MockERC20 mockA = new MockERC20("Token A", "TKNA", TOKEN_DECIMALS);
        MockERC20 mockB = new MockERC20("Token B", "TKNB", TOKEN_DECIMALS);

        // Ensure tokenA < tokenB for currency ordering
        if (address(mockA) < address(mockB)) {
            tokenA = Currency.wrap(address(mockA));
            tokenB = Currency.wrap(address(mockB));
        } else {
            tokenA = Currency.wrap(address(mockB));
            tokenB = Currency.wrap(address(mockA));
        }
    }

    function _deployHooks() private {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = tokenA;
        currencies[1] = tokenB;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, code);

        hooks = StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, salt, code));
    }

    function _dealTokens() private {
        uint256 totalNeeded = LIQUIDITY_AMOUNT * 10 ** TOKEN_DECIMALS * 4;

        MockERC20(Currency.unwrap(tokenA)).mint(liquidityProvider, totalNeeded);
        MockERC20(Currency.unwrap(tokenB)).mint(liquidityProvider, totalNeeded);
        MockERC20(Currency.unwrap(tokenA)).mint(swapper, totalNeeded);
        MockERC20(Currency.unwrap(tokenB)).mint(swapper, totalNeeded);

        vm.startPrank(liquidityProvider);
        IERC20(Currency.unwrap(tokenA)).forceApprove(address(hooks), type(uint256).max);
        IERC20(Currency.unwrap(tokenB)).forceApprove(address(hooks), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper);
        IERC20(Currency.unwrap(tokenA)).forceApprove(address(permit2), type(uint256).max);
        IERC20(Currency.unwrap(tokenB)).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(tokenA), address(universalRouter), type(uint160).max, type(uint48).max);
        permit2.approve(Currency.unwrap(tokenB), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _addLiquidity(uint256 _amount0, uint256 _amount1) internal {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _amount0 * 10 ** TOKEN_DECIMALS;
        amounts[1] = _amount1 * 10 ** TOKEN_DECIMALS;

        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, minAmounts, 0);
    }

    function _getPoolKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: tokenA,
            currency1: tokenB,
            fee: uint24(LP_FEE_PERCENTAGE),
            tickSpacing: hooks.TICK_SPACING(),
            hooks: IHooks(address(hooks))
        });
    }

    function _executeSwapAndGetOutput(bool _zeroForOne, uint256 _amountIn) internal returns (uint256 amountOut) {
        PoolKey memory poolKey = _getPoolKey();

        Currency inputCurrency = _zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = _zeroForOne ? poolKey.currency1 : poolKey.currency0;

        uint256 outputBefore = IERC20(Currency.unwrap(outputCurrency)).balanceOf(swapper);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: _zeroForOne,
                amountIn: uint128(_amountIn),
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(inputCurrency, _amountIn);
        params[2] = abi.encode(outputCurrency, 0);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.prank(swapper);
        universalRouter.execute(commands, inputs, block.timestamp + 100);

        uint256 outputAfter = IERC20(Currency.unwrap(outputCurrency)).balanceOf(swapper);
        amountOut = outputAfter - outputBefore;
    }

    function _executeExactOutputSwap(bool _zeroForOne, uint256 _amountOut) internal {
        PoolKey memory poolKey = _getPoolKey();

        Currency inputCurrency = _zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = _zeroForOne ? poolKey.currency1 : poolKey.currency0;

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: poolKey,
                zeroForOne: _zeroForOne,
                amountOut: uint128(_amountOut),
                amountInMaximum: type(uint128).max,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(inputCurrency, type(uint128).max);
        params[2] = abi.encode(outputCurrency, _amountOut);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.prank(swapper);
        universalRouter.execute(commands, inputs, block.timestamp + 100);
    }
}

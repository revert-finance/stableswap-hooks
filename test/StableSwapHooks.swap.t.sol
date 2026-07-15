// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Vm} from "forge-std/Vm.sol";

import {Swap} from "src/Swap.sol";
import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

contract StableSwapHooksSwapTest is StableSwapHooksBaseTest {
    uint256 private constant SWAP_AMOUNT = 100;
    uint256 private constant LIQUIDITY_AMOUNT = 1_000_000;
    uint256 private constant STABLESWAP_SLIPPAGE_TOLERANCE = 0.0001e18; // 0.01%

    function setUp() public override {
        super.setUp();

        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
    }

    function _feePrecision() private view returns (uint256) {
        return hooks.FEE_PRECISION();
    }

    // Total fees = LP fee percentage (hook/protocol are portions of LP fees, not additional)
    function _addFeesToAmount(uint256 amount) private view returns (uint256) {
        return amount + (amount * BASE_LP_FEE_PERCENTAGE / _feePrecision());
    }

    function _subtractFeesFromAmount(uint256 amount) private view returns (uint256) {
        return amount - (amount * BASE_LP_FEE_PERCENTAGE / _feePrecision());
    }

    struct StableSwapEventData {
        address sender;
        address currencyIn;
        address currencyOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 lpFees;
        uint256 hookFees;
        uint256 protocolFees;
    }

    function _findStableSwapEvent(Vm.Log[] memory _logs) private pure returns (StableSwapEventData memory data) {
        for (uint256 i = 0; i < _logs.length; i++) {
            if (_logs[i].topics[0] == Swap.StableSwap.selector) {
                data.sender = address(uint160(uint256(_logs[i].topics[1])));
                data.currencyIn = address(uint160(uint256(_logs[i].topics[2])));
                data.currencyOut = address(uint160(uint256(_logs[i].topics[3])));
                (data.amountIn, data.amountOut, data.lpFees, data.hookFees, data.protocolFees) =
                    abi.decode(_logs[i].data, (uint256, uint256, uint256, uint256, uint256));
                return data;
            }
        }
        revert("StableSwap event not found");
    }

    function _assertFeeRatios(StableSwapEventData memory _eventData) private view {
        uint256 grossLpFees = _eventData.lpFees + _eventData.hookFees + _eventData.protocolFees;
        uint256 expectedHookFees = grossLpFees * BASE_HOOK_FEE_PERCENTAGE / _feePrecision();
        uint256 expectedProtocolFees = grossLpFees * BASE_PROTOCOL_FEE_PERCENTAGE / _feePrecision();
        uint256 expectedNetLpFees = grossLpFees - expectedHookFees - expectedProtocolFees;

        assertEq(_eventData.lpFees, expectedNetLpFees);
        assertEq(_eventData.hookFees, expectedHookFees);
        assertEq(_eventData.protocolFees, expectedProtocolFees);
    }

    // ==========================================================================
    // Exact Input Swaps
    // ==========================================================================

    function test_swap_ExactInput_ZeroForOne_ShouldSwapCorrectly() public {
        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 swapperBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        _executeExactInputSwap(true, amountIn);

        uint256 swapperBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        uint256 expectedOutput = _subtractFeesFromAmount(_toTokenWei(currency1, SWAP_AMOUNT));

        assertEq(swapperBalance0After, swapperBalance0Before - amountIn);
        assertGt(swapperBalance1After, swapperBalance1Before);
        assertApproxEqRel(swapperBalance1After - swapperBalance1Before, expectedOutput, STABLESWAP_SLIPPAGE_TOLERANCE);
    }

    function test_swap_ExactInput_OneForZero_ShouldSwapCorrectly() public {
        uint256 amountIn = _toTokenWei(currency1, SWAP_AMOUNT);

        uint256 swapperBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        _executeExactInputSwap(false, amountIn);

        uint256 swapperBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        uint256 expectedOutput = _subtractFeesFromAmount(_toTokenWei(currency0, SWAP_AMOUNT));

        assertEq(swapperBalance1After, swapperBalance1Before - amountIn);
        assertGt(swapperBalance0After, swapperBalance0Before);
        assertApproxEqRel(swapperBalance0After - swapperBalance0Before, expectedOutput, STABLESWAP_SLIPPAGE_TOLERANCE);
    }

    // ==========================================================================
    // Exact Output Swaps
    // ==========================================================================

    function test_swap_ExactOutput_ZeroForOne_ShouldSwapCorrectly() public {
        uint256 amountOut = _toTokenWei(currency1, SWAP_AMOUNT);

        uint256 swapperBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        _executeExactOutputSwap(true, amountOut);

        uint256 swapperBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        uint256 expectedInput = _addFeesToAmount(_toTokenWei(currency0, SWAP_AMOUNT));

        assertEq(swapperBalance1After, swapperBalance1Before + amountOut);
        assertLt(swapperBalance0After, swapperBalance0Before);
        assertApproxEqRel(swapperBalance0Before - swapperBalance0After, expectedInput, STABLESWAP_SLIPPAGE_TOLERANCE);
    }

    function test_swap_ExactOutput_OneForZero_ShouldSwapCorrectly() public {
        uint256 amountOut = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 swapperBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        _executeExactOutputSwap(false, amountOut);

        uint256 swapperBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        uint256 expectedInput = _addFeesToAmount(_toTokenWei(currency1, SWAP_AMOUNT));

        assertEq(swapperBalance0After, swapperBalance0Before + amountOut);
        assertLt(swapperBalance1After, swapperBalance1Before);
        assertApproxEqRel(swapperBalance1Before - swapperBalance1After, expectedInput, STABLESWAP_SLIPPAGE_TOLERANCE);
    }

    // ==========================================================================
    // Fee Accumulation
    // ==========================================================================

    function test_swap_ExactInput_ShouldAccumulateFeesOnOutputCurrency() public {
        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 protocolFees1Before = hooks.protocolFees(1);
        uint256 hookFees1Before = hooks.hookFees(1);

        _executeExactInputSwap(true, amountIn);

        uint256 protocolFees1After = hooks.protocolFees(1);
        uint256 hookFees1After = hooks.hookFees(1);

        assertGt(protocolFees1After, protocolFees1Before);
        assertGt(hookFees1After, hookFees1Before);
        assertEq(hooks.protocolFees(0), 0);
        assertEq(hooks.hookFees(0), 0);
    }

    function test_swap_ExactOutput_ShouldAccumulateFeesOnOutputCurrency() public {
        uint256 amountOut = _toTokenWei(currency1, SWAP_AMOUNT);

        uint256 protocolFees1Before = hooks.protocolFees(1);
        uint256 hookFees1Before = hooks.hookFees(1);

        _executeExactOutputSwap(true, amountOut);

        uint256 protocolFees1After = hooks.protocolFees(1);
        uint256 hookFees1After = hooks.hookFees(1);

        assertGt(protocolFees1After, protocolFees1Before);
        assertGt(hookFees1After, hookFees1Before);
        assertEq(hooks.protocolFees(0), 0);
        assertEq(hooks.hookFees(0), 0);
    }

    function test_swap_ShouldKeepLpFeesInReserves() public {
        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);

        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        _executeExactInputSwap(true, amountIn);

        uint256 reserves0After = hooks.reserves(0);
        uint256 reserves1After = hooks.reserves(1);

        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        uint256 outputReceived = swapperBalance1After - swapperBalance1Before;

        uint256 protocolFees1 = hooks.protocolFees(1);
        uint256 hookFees1 = hooks.hookFees(1);

        assertEq(reserves0After, reserves0Before + amountIn);

        // reserves1 -= (output - lpFees), so totalOutputFromReserves = output - lpFees
        // outputReceived = output - lpFees - hookFees - protocolFees
        // Therefore: totalOutputFromReserves = outputReceived + hookFees + protocolFees
        uint256 totalOutputFromReserves = reserves1Before - reserves1After;
        uint256 expectedOutputFromReserves = outputReceived + hookFees1 + protocolFees1;

        assertEq(totalOutputFromReserves, expectedOutputFromReserves);
        assertGt(protocolFees1, 0);
        assertGt(hookFees1, 0);
    }

    // ==========================================================================
    // Reserve Updates
    // ==========================================================================

    function test_swap_ExactInput_ZeroForOne_ShouldUpdateReserves() public {
        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);

        _executeExactInputSwap(true, amountIn);

        uint256 reserves0After = hooks.reserves(0);
        uint256 reserves1After = hooks.reserves(1);

        assertEq(reserves0After, reserves0Before + amountIn);
        assertLt(reserves1After, reserves1Before);
    }

    function test_swap_ExactInput_OneForZero_ShouldUpdateReserves() public {
        uint256 amountIn = _toTokenWei(currency1, SWAP_AMOUNT);

        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);

        _executeExactInputSwap(false, amountIn);

        uint256 reserves0After = hooks.reserves(0);
        uint256 reserves1After = hooks.reserves(1);

        assertEq(reserves1After, reserves1Before + amountIn);
        assertLt(reserves0After, reserves0Before);
    }

    function test_swap_ExactOutput_ZeroForOne_ShouldUpdateReserves() public {
        uint256 amountOut = _toTokenWei(currency1, SWAP_AMOUNT);

        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);

        _executeExactOutputSwap(true, amountOut);

        uint256 reserves0After = hooks.reserves(0);
        uint256 reserves1After = hooks.reserves(1);

        assertGt(reserves0After, reserves0Before);
        assertEq(reserves1After, reserves1Before - amountOut - hooks.protocolFees(1) - hooks.hookFees(1));
    }

    function test_swap_ExactOutput_OneForZero_ShouldUpdateReserves() public {
        uint256 amountOut = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);

        _executeExactOutputSwap(false, amountOut);

        uint256 reserves0After = hooks.reserves(0);
        uint256 reserves1After = hooks.reserves(1);

        assertGt(reserves1After, reserves1Before);
        assertEq(reserves0After, reserves0Before - amountOut - hooks.protocolFees(0) - hooks.hookFees(0));
    }

    // ==========================================================================
    // StableSwap Behavior
    // ==========================================================================

    function test_swap_ShouldProvideNearOneToOneForBalancedPool() public {
        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        _executeExactInputSwap(true, amountIn);

        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        uint256 amountOut = swapperBalance1After - swapperBalance1Before;

        uint256 expectedOutput = _subtractFeesFromAmount(_toTokenWei(currency1, SWAP_AMOUNT));

        assertApproxEqRel(amountOut, expectedOutput, STABLESWAP_SLIPPAGE_TOLERANCE);
    }

    function test_swap_MultipleSwaps_ShouldMaintainConsistency() public {
        uint256 swapAmount = _toTokenWei(currency0, SWAP_AMOUNT);

        _executeExactInputSwap(true, swapAmount);
        _executeExactInputSwap(true, swapAmount);
        _executeExactInputSwap(true, swapAmount);

        uint256 reserves0 = hooks.reserves(0);
        uint256 reserves1 = hooks.reserves(1);

        assertEq(reserves0, _toTokenWei(currency0, LIQUIDITY_AMOUNT + SWAP_AMOUNT * 3));
        assertLt(reserves1, _toTokenWei(currency1, LIQUIDITY_AMOUNT));
    }

    function test_swap_SmallAmount_ShouldSucceed() public {
        uint256 amountIn = 1000;

        uint256 swapperBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);

        _executeExactInputSwap(true, amountIn);

        uint256 swapperBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);

        assertEq(swapperBalance0After, swapperBalance0Before - amountIn);
    }

    function test_swap_LargeAmount_ShouldSucceed() public {
        // Swap 50% of liquidity - should have noticeable price impact
        uint256 largeSwapAmount = LIQUIDITY_AMOUNT / 2;
        uint256 amountIn = _toTokenWei(currency0, largeSwapAmount);

        uint256 swapperBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        _executeExactInputSwap(true, amountIn);

        uint256 swapperBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        uint256 expectedOutput = _subtractFeesFromAmount(_toTokenWei(currency1, largeSwapAmount));

        assertEq(swapperBalance0After, swapperBalance0Before - amountIn);
        assertGt(swapperBalance1After, swapperBalance1Before);
        // Large swaps have price impact, so we allow 1% tolerance
        assertApproxEqRel(swapperBalance1After - swapperBalance1Before, expectedOutput, 0.01e18);
    }

    function test_swap_WithZeroHookAndProtocolFees_ShouldOnlyChargeLpFees() public {
        // Set hook and protocol fees to 0
        vm.startPrank(defaultAdmin);
        hooks.setHookFeePercentage(0);
        hooks.setProtocolFeePercentage(0);
        vm.stopPrank();

        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        _executeExactInputSwap(true, amountIn);

        // With zero hook/protocol fees, no fees should accumulate in those buckets
        assertEq(hooks.protocolFees(0), 0);
        assertEq(hooks.protocolFees(1), 0);
        assertEq(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);
    }

    // ==========================================================================
    // Multi-Currency (hooks3)
    // ==========================================================================

    function test_hooks3_swap_ZeroToOne_ShouldSwapCorrectly() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 swapperBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        _executeExactInputSwap3(currency0, currency1, amountIn);

        uint256 swapperBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        assertEq(swapperBalance0After, swapperBalance0Before - amountIn);
        assertGt(swapperBalance1After, swapperBalance1Before);
    }

    function test_hooks3_swap_ZeroToTwo_ShouldSwapCorrectly() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 swapperBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance2Before = IERC20(Currency.unwrap(currency2)).balanceOf(swapper);

        _executeExactInputSwap3(currency0, currency2, amountIn);

        uint256 swapperBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance2After = IERC20(Currency.unwrap(currency2)).balanceOf(swapper);

        assertEq(swapperBalance0After, swapperBalance0Before - amountIn);
        assertGt(swapperBalance2After, swapperBalance2Before);
    }

    function test_hooks3_swap_OneToTwo_ShouldSwapCorrectly() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 amountIn = _toTokenWei(currency1, SWAP_AMOUNT);

        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        uint256 swapperBalance2Before = IERC20(Currency.unwrap(currency2)).balanceOf(swapper);

        _executeExactInputSwap3(currency1, currency2, amountIn);

        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        uint256 swapperBalance2After = IERC20(Currency.unwrap(currency2)).balanceOf(swapper);

        assertEq(swapperBalance1After, swapperBalance1Before - amountIn);
        assertGt(swapperBalance2After, swapperBalance2Before);
    }

    function test_hooks3_swap_ShouldUpdateCorrectReserves() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 reserves0Before = hooks3.reserves(0);
        uint256 reserves1Before = hooks3.reserves(1);
        uint256 reserves2Before = hooks3.reserves(2);

        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        _executeExactInputSwap3(currency0, currency2, amountIn);

        // currency0 reserves should increase, currency2 should decrease, currency1 unchanged
        assertEq(hooks3.reserves(0), reserves0Before + amountIn);
        assertEq(hooks3.reserves(1), reserves1Before);
        assertLt(hooks3.reserves(2), reserves2Before);
    }

    function test_hooks3_swap_MultipleSwaps_ShouldMaintainConsistency() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        // Execute swaps across all pairs
        _executeExactInputSwap3(currency0, currency1, amountIn);
        _executeExactInputSwap3(currency1, currency2, _toTokenWei(currency1, SWAP_AMOUNT));
        _executeExactInputSwap3(currency2, currency0, _toTokenWei(currency2, SWAP_AMOUNT));

        // All reserves should still be positive and reasonable
        assertGt(hooks3.reserves(0), 0);
        assertGt(hooks3.reserves(1), 0);
        assertGt(hooks3.reserves(2), 0);
    }

    // ==========================================================================
    // Edge Cases
    // ==========================================================================

    function test_swap_ImbalancedPool_ShouldHavePriceImpact() public {
        // Pool starts balanced from setUp
        // Create imbalance by swapping currency0 -> currency1 multiple times
        // This makes currency0 abundant and currency1 scarce
        uint256 swapAmount = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 4);
        _executeExactInputSwap(true, swapAmount);
        _executeExactInputSwap(true, swapAmount);

        // Now pool is imbalanced: more currency0, less currency1
        uint256 reserves0 = hooks.reserves(0);
        uint256 reserves1 = hooks.reserves(1);
        assertGt(reserves0, reserves1); // currency0 is now abundant

        // Swap currency0 -> currency1 (buying the scarce asset)
        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);
        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        _executeExactInputSwap(true, amountIn);

        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        uint256 amountOut = swapperBalance1After - swapperBalance1Before;

        // Output should be less than input due to imbalance (buying scarce asset)
        // Even accounting for fees, the price impact should be significant
        assertLt(amountOut, amountIn);
    }

    function test_swap_ImbalancedPool_ReverseDirection_ShouldHaveBetterRate() public {
        // Pool starts balanced from setUp
        // Create imbalance by swapping currency0 -> currency1 multiple times
        // This makes currency0 abundant and currency1 scarce
        uint256 swapAmount = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 4);
        _executeExactInputSwap(true, swapAmount);
        _executeExactInputSwap(true, swapAmount);

        // Now pool is imbalanced: more currency0, less currency1
        uint256 reserves0 = hooks.reserves(0);
        uint256 reserves1 = hooks.reserves(1);
        assertGt(reserves0, reserves1); // currency0 is now abundant

        // Swap currency1 -> currency0 (selling the scarce asset for abundant one)
        // With imbalanced pool, this direction should give better rate than the other direction
        uint256 amountIn = _toTokenWei(currency1, SWAP_AMOUNT / 10);
        uint256 swapperBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);

        _executeExactInputSwap(false, amountIn);

        uint256 swapperBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 amountOut = swapperBalance0After - swapperBalance0Before;

        // In an imbalanced pool, selling the scarce asset should give better rate than
        // selling the abundant asset. Let's verify we get a non-zero output and
        // the rate is reasonable (pool dynamics + fees may reduce output)
        assertGt(amountOut, 0);

        // The key insight: selling scarce asset for abundant asset should give better rate
        // than the opposite direction. Let's compare by doing an equal swap the other way.
        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        _executeExactInputSwap(true, amountIn); // Same amount but opposite direction
        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        uint256 reverseAmountOut = swapperBalance1After - swapperBalance1Before;

        // Selling scarce (currency1) for abundant (currency0) should yield more output
        // than selling abundant (currency0) for scarce (currency1)
        assertGt(amountOut, reverseAmountOut);
    }

    function test_swap_VerySmallAmount_ShouldSucceed() public {
        // Test with 1 wei
        uint256 amountIn = 1;

        uint256 swapperBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);

        _executeExactInputSwap(true, amountIn);

        uint256 swapperBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);

        assertEq(swapperBalance0After, swapperBalance0Before - amountIn);
    }

    function test_swap_ConsecutiveSwaps_ShouldAccumulatePriceImpact() public {
        uint256 swapAmount = _toTokenWei(currency0, SWAP_AMOUNT * 10);

        // First swap
        uint256 balance1Before1 = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        _executeExactInputSwap(true, swapAmount);
        uint256 balance1After1 = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        uint256 output1 = balance1After1 - balance1Before1;

        // Second identical swap - should get less output due to price impact
        uint256 balance1Before2 = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        _executeExactInputSwap(true, swapAmount);
        uint256 balance1After2 = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        uint256 output2 = balance1After2 - balance1Before2;

        // Second swap should yield less due to accumulated price impact
        assertLt(output2, output1);
    }

    function test_swap_RoundTrip_ShouldLoseToFees() public {
        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 initialBalance0 = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 initialBalance1 = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        // Swap currency0 -> currency1
        _executeExactInputSwap(true, amountIn);

        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        uint256 received1 = balance1After - initialBalance1;

        // Swap only the received currency1 back to currency0
        _executeExactInputSwap(false, received1);

        uint256 finalBalance0 = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);

        // Should have less than started due to fees on both swaps
        assertLt(finalBalance0, initialBalance0);
    }

    function test_swap_ExactOutput_NearFullReserves_ShouldSucceed() public {
        // Try to swap out 80% of reserves (significant but not draining)
        uint256 reserve1 = hooks.reserves(1);
        uint256 amountOut = reserve1 * 80 / 100;

        uint256 swapperBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        _executeExactOutputSwap(true, amountOut);

        uint256 swapperBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        assertEq(swapperBalance1After, swapperBalance1Before + amountOut);
        assertLt(swapperBalance0After, swapperBalance0Before);
    }

    // ==========================================================================
    // Event Emission
    // ==========================================================================

    function test_swap_ExactInput_ZeroForOne_ShouldEmitCorrectEvent() public {
        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);
        uint256 balanceBefore = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        vm.recordLogs();
        _executeExactInputSwap(true, amountIn);

        uint256 actualAmountOut = IERC20(Currency.unwrap(currency1)).balanceOf(swapper) - balanceBefore;
        StableSwapEventData memory eventData = _findStableSwapEvent(vm.getRecordedLogs());

        // Verify indexed params
        assertNotEq(eventData.sender, address(0));
        assertEq(eventData.currencyIn, Currency.unwrap(currency0));
        assertEq(eventData.currencyOut, Currency.unwrap(currency1));

        // Verify amounts match actual transfers
        assertEq(eventData.amountIn, amountIn);
        assertEq(eventData.amountOut, actualAmountOut);

        // Verify fee ratios match configured percentages
        _assertFeeRatios(eventData);
    }

    function test_swap_ExactInput_OneForZero_ShouldEmitCorrectEvent() public {
        uint256 amountIn = _toTokenWei(currency1, SWAP_AMOUNT);
        uint256 balanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);

        vm.recordLogs();
        _executeExactInputSwap(false, amountIn);

        uint256 actualAmountOut = IERC20(Currency.unwrap(currency0)).balanceOf(swapper) - balanceBefore;
        StableSwapEventData memory eventData = _findStableSwapEvent(vm.getRecordedLogs());

        // Verify currencies are swapped for oneForZero
        assertEq(eventData.currencyIn, Currency.unwrap(currency1));
        assertEq(eventData.currencyOut, Currency.unwrap(currency0));

        // Verify amounts
        assertEq(eventData.amountIn, amountIn);
        assertEq(eventData.amountOut, actualAmountOut);
    }

    function test_swap_ExactOutput_ZeroForOne_ShouldEmitCorrectEvent() public {
        uint256 amountOut = _toTokenWei(currency1, SWAP_AMOUNT);
        uint256 balanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);

        vm.recordLogs();
        _executeExactOutputSwap(true, amountOut);

        uint256 actualAmountIn = balanceBefore - IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        StableSwapEventData memory eventData = _findStableSwapEvent(vm.getRecordedLogs());

        // Verify indexed params
        assertNotEq(eventData.sender, address(0));
        assertEq(eventData.currencyIn, Currency.unwrap(currency0));
        assertEq(eventData.currencyOut, Currency.unwrap(currency1));

        // Verify amounts match actual transfers
        assertEq(eventData.amountIn, actualAmountIn);
        assertEq(eventData.amountOut, amountOut);

        // Verify fee ratios (fees grossed up into the input for exact output)
        _assertFeeRatios(eventData);
    }

    function test_swap_ExactOutput_OneForZero_ShouldEmitCorrectEvent() public {
        uint256 amountOut = _toTokenWei(currency0, SWAP_AMOUNT);
        uint256 balanceBefore = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        vm.recordLogs();
        _executeExactOutputSwap(false, amountOut);

        uint256 actualAmountIn = balanceBefore - IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        StableSwapEventData memory eventData = _findStableSwapEvent(vm.getRecordedLogs());

        // Verify currencies are swapped for oneForZero
        assertEq(eventData.currencyIn, Currency.unwrap(currency1));
        assertEq(eventData.currencyOut, Currency.unwrap(currency0));

        // Verify amounts
        assertEq(eventData.amountIn, actualAmountIn);
        assertEq(eventData.amountOut, amountOut);
    }
}

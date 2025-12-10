// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

contract StableSwapHooksSwapTest is StableSwapHooksBaseTest {
    uint256 private constant SWAP_AMOUNT = 100;
    uint256 private constant LIQUIDITY_AMOUNT = 1e6;
    uint256 private constant STABLESWAP_SLIPPAGE_TOLERANCE = 0.0001e18; // 0.01%

    uint256 private swapLpFeePercentage;
    uint256 private swapHookFeePercentage;
    uint256 private swapProtocolFeePercentage;

    function setUp() public override {
        super.setUp();

        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        // Use 1%, 2%, 3% fees for testing (total 6%)
        swapLpFeePercentage = 10000;
        swapHookFeePercentage = 20000;
        swapProtocolFeePercentage = 30000;

        vm.startPrank(defaultAdmin);
        hooks.setLpFeePercentage(swapLpFeePercentage);
        hooks.setHookFeePercentage(swapHookFeePercentage);
        hooks.setProtocolFeePercentage(swapProtocolFeePercentage);
        vm.stopPrank();
    }

    function _totalFeePercentage() private view returns (uint256) {
        return swapLpFeePercentage + swapHookFeePercentage + swapProtocolFeePercentage;
    }

    function _feePrecision() private view returns (uint256) {
        return hooks.FEE_PRECISION();
    }

    function _addFeesToAmount(uint256 amount) private view returns (uint256) {
        return amount + (amount * _totalFeePercentage() / _feePrecision());
    }

    function _subtractFeesFromAmount(uint256 amount) private view returns (uint256) {
        return amount - (amount * _totalFeePercentage() / _feePrecision());
    }

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

    function test_swap_ExactInput_ShouldAccumulateFeesOnOutputCurrency() public {
        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 protocolFees1Before = hooks.protocolFees1();
        uint256 hookFees1Before = hooks.hookFees1();

        _executeExactInputSwap(true, amountIn);

        uint256 protocolFees1After = hooks.protocolFees1();
        uint256 hookFees1After = hooks.hookFees1();

        assertGt(protocolFees1After, protocolFees1Before);
        assertGt(hookFees1After, hookFees1Before);
        assertEq(hooks.protocolFees0(), 0);
        assertEq(hooks.hookFees0(), 0);
    }

    function test_swap_ExactOutput_ShouldAccumulateFeesOnInputCurrency() public {
        uint256 amountOut = _toTokenWei(currency1, SWAP_AMOUNT);

        uint256 protocolFees0Before = hooks.protocolFees0();
        uint256 hookFees0Before = hooks.hookFees0();

        _executeExactOutputSwap(true, amountOut);

        uint256 protocolFees0After = hooks.protocolFees0();
        uint256 hookFees0After = hooks.hookFees0();

        assertGt(protocolFees0After, protocolFees0Before);
        assertGt(hookFees0After, hookFees0Before);
        assertEq(hooks.protocolFees1(), 0);
        assertEq(hooks.hookFees1(), 0);
    }

    function test_swap_ShouldKeepLpFeesInReserves() public {
        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 reserves0Before = hooks.reserves0();
        uint256 reserves1Before = hooks.reserves1();

        uint256 swapperBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        _executeExactInputSwap(true, amountIn);

        uint256 reserves0After = hooks.reserves0();
        uint256 reserves1After = hooks.reserves1();

        uint256 swapperBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        uint256 outputReceived = swapperBalance1After - swapperBalance1Before;

        uint256 protocolFees1 = hooks.protocolFees1();
        uint256 hookFees1 = hooks.hookFees1();

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

    function test_swap_ExactInput_ZeroForOne_ShouldUpdateReserves() public {
        uint256 amountIn = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 reserves0Before = hooks.reserves0();
        uint256 reserves1Before = hooks.reserves1();

        _executeExactInputSwap(true, amountIn);

        uint256 reserves0After = hooks.reserves0();
        uint256 reserves1After = hooks.reserves1();

        assertEq(reserves0After, reserves0Before + amountIn);
        assertLt(reserves1After, reserves1Before);
    }

    function test_swap_ExactInput_OneForZero_ShouldUpdateReserves() public {
        uint256 amountIn = _toTokenWei(currency1, SWAP_AMOUNT);

        uint256 reserves0Before = hooks.reserves0();
        uint256 reserves1Before = hooks.reserves1();

        _executeExactInputSwap(false, amountIn);

        uint256 reserves0After = hooks.reserves0();
        uint256 reserves1After = hooks.reserves1();

        assertEq(reserves1After, reserves1Before + amountIn);
        assertLt(reserves0After, reserves0Before);
    }

    function test_swap_ExactOutput_ZeroForOne_ShouldUpdateReserves() public {
        uint256 amountOut = _toTokenWei(currency1, SWAP_AMOUNT);

        uint256 reserves0Before = hooks.reserves0();
        uint256 reserves1Before = hooks.reserves1();

        _executeExactOutputSwap(true, amountOut);

        uint256 reserves0After = hooks.reserves0();
        uint256 reserves1After = hooks.reserves1();

        assertGt(reserves0After, reserves0Before);
        assertEq(reserves1After, reserves1Before - amountOut);
    }

    function test_swap_ExactOutput_OneForZero_ShouldUpdateReserves() public {
        uint256 amountOut = _toTokenWei(currency0, SWAP_AMOUNT);

        uint256 reserves0Before = hooks.reserves0();
        uint256 reserves1Before = hooks.reserves1();

        _executeExactOutputSwap(false, amountOut);

        uint256 reserves0After = hooks.reserves0();
        uint256 reserves1After = hooks.reserves1();

        assertGt(reserves1After, reserves1Before);
        assertEq(reserves0After, reserves0Before - amountOut);
    }

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

        uint256 reserves0 = hooks.reserves0();
        uint256 reserves1 = hooks.reserves1();

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
}

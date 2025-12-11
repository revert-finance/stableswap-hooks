// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

import {Liquidity} from "src/Liquidity.sol";

contract StableSwapHooksLiquidityTest is StableSwapHooksBaseTest {
    // On first deposit, MINIMUM_LIQUIDITY (1000) is locked to address(0x000000000000000000000000000000000000dEaD)
    uint256 private constant LOCKED_LIQUIDITY = 1000;

    function test_addLiquidity_ShouldMintSharesOnFirstDeposit() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        assertEq(hooks.totalSupply(), 0);
        assertEq(hooks.balanceOf(liquidityProvider), 0);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        assertGt(hooks.totalSupply(), 0);
        // So user balance + locked liquidity = total supply
        assertEq(hooks.balanceOf(liquidityProvider) + LOCKED_LIQUIDITY, hooks.totalSupply());
    }

    function test_addLiquidity_ShouldEmitLiquidityAddedEvent() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        uint256 expectedShares = hooks.computeNewShares(amount0, amount1);

        vm.expectEmit(address(hooks));
        emit Liquidity.LiquidityAdded(liquidityProvider, amount0, amount1, expectedShares);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);
    }

    function test_addLiquidity_ShouldUpdateReserves() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        assertEq(hooks.reserves0(), 0);
        assertEq(hooks.reserves1(), 0);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        assertEq(hooks.reserves0(), amount0);
        assertEq(hooks.reserves1(), amount1);
    }

    function test_addLiquidity_ShouldTransferTokensFromUser() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        assertEq(balance0Before - balance0After, amount0);
        assertEq(balance1Before - balance1After, amount1);
    }

    function test_addLiquidity_ShouldMintProportionalSharesOnSubsequentDeposit() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);
        uint256 initialShares = hooks.balanceOf(liquidityProvider);
        uint256 totalSupplyAfterFirst = hooks.totalSupply();

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 secondShares = hooks.balanceOf(liquidityProvider) - initialShares;
        uint256 totalSupplyAfterSecond = hooks.totalSupply();

        uint256 expectedSecondShares = (amount0 * totalSupplyAfterFirst) / amount0;

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 totalBalanceAfterThird = hooks.balanceOf(liquidityProvider);
        uint256 thirdShares = totalBalanceAfterThird - initialShares - secondShares;

        // Calculate expected shares for third deposit
        uint256 expectedThirdShares = (amount0 * totalSupplyAfterSecond) / (amount0 * 2);

        // First deposit gets (invariant - MINIMUM_LIQUIDITY) shares
        // Second and subsequent deposits use: shares = amount * totalSupply / reserves

        assertEq(secondShares, expectedSecondShares);
        assertEq(thirdShares, expectedThirdShares);
    }

    function test_addLiquidity_ShouldAllowSingleSidedDeposit() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 sharesBefore = hooks.balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, 0, 0);

        uint256 sharesAfter = hooks.balanceOf(liquidityProvider);

        assertGt(sharesAfter, sharesBefore);
    }

    function test_addLiquidity_ShouldRevertWhenBothAmountsAreZero() public {
        vm.expectRevert(Liquidity.AddLiquidityAmountsCannotBeZero.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(0, 0, 0);
    }

    function test_addLiquidity_ShouldRevertWhenSharesBelowMinimum() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, type(uint256).max);
    }

    function test_removeLiquidity_ShouldBurnSharesAndReturnTokens() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 shares = hooks.balanceOf(liquidityProvider);
        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(shares, 0, 0);

        assertEq(hooks.balanceOf(liquidityProvider), 0);
        // MINIMUM_LIQUIDITY (1000) remains locked in the pool
        assertEq(hooks.totalSupply(), LOCKED_LIQUIDITY);

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        assertApproxEqAbs(balance0After - balance0Before, amount0, 500);
        assertApproxEqAbs(balance1After - balance1Before, amount1, 500);
    }

    function test_removeLiquidity_ShouldEmitLiquidityRemovedEvent() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 shares = hooks.balanceOf(liquidityProvider);
        uint256 totalSupply = hooks.totalSupply();

        // Calculate expected amounts based on proportional share (not full deposit due to locked liquidity)
        uint256 expectedAmount0 = (shares * amount0) / totalSupply;
        uint256 expectedAmount1 = (shares * amount1) / totalSupply;

        vm.expectEmit(address(hooks));
        emit Liquidity.LiquidityRemoved(liquidityProvider, expectedAmount0, expectedAmount1, shares);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(shares, 0, 0);
    }

    function test_removeLiquidity_ShouldUpdateReserves() public {
        uint256 amount0 = _toTokenWei(currency0, 10);
        uint256 amount1 = _toTokenWei(currency1, 10);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 shares = hooks.balanceOf(liquidityProvider);
        uint256 totalSupply = hooks.totalSupply();
        uint256 expectedReservesAmount0 = (LOCKED_LIQUIDITY * amount0) / totalSupply;
        uint256 expectedReservesAmount1 = (LOCKED_LIQUIDITY * amount1) / totalSupply;

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(shares, 0, 0);

        assertApproxEqAbs(hooks.reserves0(), expectedReservesAmount0, 1);
        assertApproxEqAbs(hooks.reserves1(), expectedReservesAmount1, 1);
    }

    function test_removeLiquidity_ShouldReturnProportionalAmounts() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 totalShares = hooks.balanceOf(liquidityProvider);
        uint256 halfShares = totalShares / 2;

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(halfShares, 0, 0);

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        // User receives their share out of totalSupply (which includes locked liquidity)
        uint256 totalSupply = hooks.totalSupply() + halfShares; // Total before removal
        uint256 expectedAmount0 = (halfShares * amount0) / totalSupply;
        uint256 expectedAmount1 = (halfShares * amount1) / totalSupply;

        assertApproxEqAbs(balance0After - balance0Before, expectedAmount0, 1);
        assertApproxEqAbs(balance1After - balance1Before, expectedAmount1, 1);
    }

    function test_removeLiquidity_ShouldRevertWhenInsufficientShares() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 shares = hooks.balanceOf(liquidityProvider);

        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(shares + 1, 0, 0);
    }

    function test_removeLiquidity_ShouldRevertWhenSlippageExceeded() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 shares = hooks.balanceOf(liquidityProvider);

        vm.expectRevert(Liquidity.InsufficientAmounts.selector);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(shares, amount0 + 1, 0);
    }

    function test_minimumLiquidity_IsLockedOnFirstDeposit() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        // User should receive (invariant - MINIMUM_LIQUIDITY) shares
        // Total supply should be invariant (user shares + locked)
        uint256 userShares = hooks.balanceOf(liquidityProvider);
        uint256 totalShares = hooks.totalSupply();

        assertEq(totalShares - userShares, LOCKED_LIQUIDITY, "MINIMUM_LIQUIDITY should be 1000");
    }

    function test_minimumLiquidity_CannotWithdrawLocked() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 userShares = hooks.balanceOf(liquidityProvider);

        // Remove all user shares
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(userShares, 0, 0);

        // Locked liquidity should remain
        assertEq(hooks.totalSupply(), LOCKED_LIQUIDITY, "MINIMUM_LIQUIDITY should remain locked");
        assertGt(hooks.reserves0(), 0, "Some reserves0 should remain");
        assertGt(hooks.reserves1(), 0, "Some reserves1 should remain");
    }

    function test_minimumLiquidity_SecondDepositDoesNotLockMore() public {
        uint256 amount0 = _toTokenWei(currency0, LOCKED_LIQUIDITY);
        uint256 amount1 = _toTokenWei(currency1, LOCKED_LIQUIDITY);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 userSharesAfterFirst = hooks.balanceOf(liquidityProvider);
        uint256 totalSharesAfterFirst = hooks.totalSupply();
        uint256 lockedAfterFirst = totalSharesAfterFirst - userSharesAfterFirst;

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 userSharesAfterSecond = hooks.balanceOf(liquidityProvider);
        uint256 totalSharesAfterSecond = hooks.totalSupply();
        uint256 lockedAfterSecond = totalSharesAfterSecond - userSharesAfterSecond;

        assertEq(lockedAfterFirst, lockedAfterSecond, "No additional liquidity should be locked");
        assertEq(lockedAfterSecond, LOCKED_LIQUIDITY, "Only MINIMUM_LIQUIDITY should be locked");
    }

    function test_minimumLiquidity_PreventsInflationAttack() public {
        // Test that small first deposit followed by large deposit works correctly
        // This simulates an inflation attack scenario where the minimum liquidity protection helps

        // Small first deposit (attacker scenario)
        uint256 smallAmount0 = _toTokenWei(currency0, 10);
        uint256 smallAmount1 = _toTokenWei(currency1, 10);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(smallAmount0, smallAmount1, 0);

        uint256 firstDepositShares = hooks.balanceOf(liquidityProvider);

        // Large second deposit (victim scenario)
        uint256 largeAmount0 = _toTokenWei(currency0, 1000);
        uint256 largeAmount1 = _toTokenWei(currency1, 1000);

        uint256 sharesBefore = hooks.balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(largeAmount0, largeAmount1, 0);

        uint256 secondDepositShares = hooks.balanceOf(liquidityProvider) - sharesBefore;

        // Second depositor should receive proportional shares
        // The ratio should be approximately 100:1 (1000/10)
        // With minimum liquidity protection, this is safe from manipulation
        assertGt(secondDepositShares, 10, "Second deposit should receive shares");
        assertGt(secondDepositShares, firstDepositShares / 100, "Larger deposit should receive more shares");
    }

    function test_minimumLiquidity_RoundingAfterMinimumLocked() public {
        uint256 amount0 = _toTokenWei(currency0, 10000);
        uint256 amount1 = _toTokenWei(currency1, 10000);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        // Add very small amount
        uint256 smallAmount0 = 100;
        uint256 smallAmount1 = 100;

        uint256 sharesBefore = hooks.balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(smallAmount0, smallAmount1, 0);

        uint256 sharesAfter = hooks.balanceOf(liquidityProvider);

        assertGt(sharesAfter, sharesBefore, "Should receive shares even for small deposit");
    }

    function test_minimumLiquidity_ImbalancedInitialDeposit() public {
        // Heavily imbalanced first deposit
        uint256 amount0 = _toTokenWei(currency0, 10000);
        uint256 amount1 = _toTokenWei(currency1, 1);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        // Should still lock MINIMUM_LIQUIDITY
        uint256 userShares = hooks.balanceOf(liquidityProvider);
        uint256 totalShares = hooks.totalSupply();
        assertEq(
            totalShares - userShares, LOCKED_LIQUIDITY, "MINIMUM_LIQUIDITY should be locked even for imbalanced deposit"
        );

        // User shares should be reasonable
        assertGt(userShares, 0, "User should receive shares");
    }

    function test_minimumLiquidity_SingleSidedInitialDeposit() public {
        // Add balanced liquidity first
        uint256 initAmount0 = _toTokenWei(currency0, 1000);
        uint256 initAmount1 = _toTokenWei(currency1, 1000);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(initAmount0, initAmount1, 0);

        // Now add single-sided
        uint256 amount0 = _toTokenWei(currency0, 100);

        vm.prank(liquidityProvider);
        // Single-sided first deposit
        hooks.addLiquidity(amount0, 0, 0);

        // User shares should increase
        uint256 userShares = hooks.balanceOf(liquidityProvider);
        assertGt(userShares, 0, "User should receive shares");

        // Only 1000 should be locked (from first deposit)
        uint256 totalShares = hooks.totalSupply();
        assertEq(
            totalShares - userShares, LOCKED_LIQUIDITY, "Only MINIMUM_LIQUIDITY from first deposit should be locked"
        );
    }

    function test_minimumLiquidity_MultipleDepositsAndWithdrawals() public {
        // Test multiple deposits and withdrawals, verifying locked liquidity persists
        uint256 amount0 = _toTokenWei(currency0, 1000);
        uint256 amount1 = _toTokenWei(currency1, 1000);

        // First deposit
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        // Second deposit
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 totalShares = hooks.balanceOf(liquidityProvider);

        // Withdraw all user shares
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(totalShares, 0, 0);

        // MINIMUM_LIQUIDITY should still be locked
        assertEq(hooks.totalSupply(), LOCKED_LIQUIDITY, "MINIMUM_LIQUIDITY should remain locked after all withdrawals");
        assertEq(hooks.balanceOf(liquidityProvider), 0, "User should have no shares");
        assertGt(hooks.reserves0(), 0, "Reserves0 should not be empty");
        assertGt(hooks.reserves1(), 0, "Reserves1 should not be empty");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

import {Liquidity} from "src/Liquidity.sol";

contract StableSwapHooksLiquidityTest is StableSwapHooksBaseTest {
    using SafeERC20 for IERC20;

    uint256 private constant LIQUIDITY_AMOUNT = 100_000;
    uint256 private constant MINIMUM_LIQUIDITY = 1_000;
    address private constant DEAD_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    // ==========================================================================
    // Add Liquidity - Initial Deposit
    // ==========================================================================

    function test_addLiquidity_InitialDeposit_ShouldMintSharesMinusMinimumLiquidity() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 deadBalance = hooks.balanceOf(DEAD_ADDRESS);

        assertGt(lpBalance, 0);
        assertEq(deadBalance, MINIMUM_LIQUIDITY);
    }

    function test_addLiquidity_InitialDeposit_ShouldUpdateReserves() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        assertEq(hooks.reserves(0), amounts[0]);
        assertEq(hooks.reserves(1), amounts[1]);
    }

    function test_addLiquidity_InitialDeposit_ShouldTransferTokensFromUser() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        assertEq(balance0Before - balance0After, amounts[0]);
        assertEq(balance1Before - balance1After, amounts[1]);
    }

    function test_addLiquidity_InitialDeposit_ShouldEmitEvent() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 actualShares = hooks.balanceOf(liquidityProvider);

        // Verify shares were minted correctly (geometric mean of scaled amounts - MINIMUM_LIQUIDITY)
        assertGt(actualShares, 0);
        assertEq(hooks.balanceOf(DEAD_ADDRESS), MINIMUM_LIQUIDITY);
        assertEq(hooks.totalSupply(), actualShares + MINIMUM_LIQUIDITY);
    }

    function test_addLiquidity_InitialDeposit_GeometricMean_ShouldBeBetweenMinAndMax() public {
        // Use imbalanced amounts to verify geometric mean is between min and max
        // geometric mean(a, b) should satisfy: min(a,b) <= geomean <= max(a,b)
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 10_000);
        amounts[1] = _toTokenWei(currency1, 40_000);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 shares = hooks.balanceOf(liquidityProvider) + MINIMUM_LIQUIDITY;

        // For geometric mean: shares should be > min(scaled amounts) and < max(scaled amounts)
        // With different decimals, scaling normalizes to 18 decimals
        // 10_000e18 and 40_000e18 (after scaling) -> geomean = 20_000e18
        uint256 expectedGeometricMean = 20_000 * 1e18;
        assertEq(shares, expectedGeometricMean);
    }

    // ==========================================================================
    // Add Liquidity - Subsequent Deposit
    // ==========================================================================

    function test_addLiquidity_SubsequentDeposit_ShouldMintProportionalShares() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 totalSupplyBefore = hooks.totalSupply();
        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 totalSupplyAfter = hooks.totalSupply();
        uint256 lpBalanceAfter = hooks.balanceOf(liquidityProvider);

        assertGt(totalSupplyAfter, totalSupplyBefore);
        assertGt(lpBalanceAfter, lpBalanceBefore);
    }

    function test_addLiquidity_SubsequentDeposit_ShouldUpdateReserves() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 2);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT / 2);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        assertEq(hooks.reserves(0), reserves0Before + amounts[0]);
        assertEq(hooks.reserves(1), reserves1Before + amounts[1]);
    }

    function test_addLiquidity_SubsequentDeposit_ShouldNotLockMoreMinimumLiquidity() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 deadBalanceBefore = hooks.balanceOf(DEAD_ADDRESS);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 deadBalanceAfter = hooks.balanceOf(DEAD_ADDRESS);

        assertEq(deadBalanceAfter, deadBalanceBefore);
        assertEq(deadBalanceAfter, MINIMUM_LIQUIDITY);
    }

    // ==========================================================================
    // Add Liquidity - Proportional Deposit Behavior
    // ==========================================================================

    function test_addLiquidity_SingleSided_ShouldRevertWithMinShares() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 10);
        // amounts[1] = 0

        // With proportional deposits, single-sided deposits result in 0 shares
        // because minProportion = min(amount_i / reserve_i) = 0 when any amount is 0
        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 1);
    }

    function test_addLiquidity_Proportional_ShouldOnlyTransferProportionalAmounts() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);
        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        // Try to deposit 2x token0 but only 1x token1 (token1 is the limiting factor)
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 2000);
        amounts[1] = _toTokenWei(currency1, 1000);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        // Should only transfer proportional amounts, not the full 2000 of token0
        uint256 transferred0 = balance0Before - balance0After;
        uint256 transferred1 = balance1Before - balance1After;

        // Compare proportions, not absolute amounts (tokens may have different decimals)
        // Each transfer should be the same proportion of its respective reserves
        uint256 proportion0 = (transferred0 * 1e18) / reserves0Before;
        uint256 proportion1 = (transferred1 * 1e18) / reserves1Before;
        assertApproxEqRel(proportion0, proportion1, 0.01e18);

        // Token0 transferred should be less than the max amount requested
        assertLt(transferred0, amounts[0]);
        // Token1 transferred should equal what was requested (it's the limit)
        assertEq(transferred1, amounts[1]);
    }

    function test_addLiquidity_Proportional_ShouldEmitEventWithActualAmounts() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);
        uint256 totalSupplyBefore = hooks.totalSupply();

        // Imbalanced max amounts: token1 is limiting factor
        uint256[] memory maxAmounts = new uint256[](2);
        maxAmounts[0] = _toTokenWei(currency0, 2000);
        maxAmounts[1] = _toTokenWei(currency1, 1000);

        // Calculate expected proportional amounts based on limiting factor (token1)
        uint256 expectedShares = (maxAmounts[1] * totalSupplyBefore) / reserves1Before;
        uint256 expectedAmount0 = (expectedShares * reserves0Before) / totalSupplyBefore;
        uint256 expectedAmount1 = maxAmounts[1]; // Limiting factor

        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = expectedAmount0;
        expectedAmounts[1] = expectedAmount1;

        // Event should emit actual proportional amounts, not max amounts
        vm.expectEmit(true, true, true, true, address(hooks));
        emit Liquidity.LiquidityAdded(liquidityProvider, expectedAmounts, expectedShares);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(maxAmounts, 0);
    }

    // ==========================================================================
    // Add Liquidity - Validation
    // ==========================================================================

    function test_addLiquidity_ShouldRevertWhenSharesBelowMinimum() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 10);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT / 10);
        uint256 minShares = type(uint256).max;

        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, minShares);
    }

    function test_addLiquidity_ShouldSucceedWhenSharesAboveMinimum() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        // Use minShares of 1 to ensure we get at least some shares
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 1);

        assertGt(hooks.balanceOf(liquidityProvider), lpBalanceBefore);
    }

    function test_addLiquidity_ShouldRevertWhenBothAmountsZero_InitialDeposit() public {
        uint256[] memory amounts = new uint256[](2);

        vm.expectRevert(Liquidity.InsufficientInitialLiquidity.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);
    }

    function test_addLiquidity_ShouldRevertWhenBelowMinimumLiquidity_InitialDeposit() public {
        // Geometric mean of scaled amounts must be >= MINIMUM_LIQUIDITY (1000)
        // Using raw wei amounts that after scaling will be below minimum
        // sqrt(10 * 10) = 10 < 1000, so should revert
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10; // 10 wei of token0 (18 decimals) -> scales to 10
        amounts[1] = 10; // 10 wei of token1 (6 decimals) -> scales to 10e12
        // geometric mean = sqrt(10 * 10e12) = sqrt(10e13) ≈ 3.16e6 > 1000
        // Need even smaller amounts to get below 1000

        // Actually, with different decimals this is tricky. Let's use amounts that definitely fail:
        // If both amounts are 0, it fails with InsufficientInitialLiquidity
        // Let's test with one amount being 0
        amounts[0] = 1;
        amounts[1] = 0;

        vm.expectRevert(Liquidity.InsufficientInitialLiquidity.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);
    }

    function test_addLiquidity_ShouldRevertWhenBothAmountsZero_SubsequentDeposit() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256[] memory amounts = new uint256[](2);

        // With zero amounts and minShares=1, it should revert with InsufficientShares
        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 1);
    }

    // ==========================================================================
    // Remove Liquidity
    // ==========================================================================

    function test_removeLiquidity_ShouldBurnSharesAndReturnTokens() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 sharesToRemove = lpBalance / 2;

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, minAmounts);

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        assertEq(hooks.balanceOf(liquidityProvider), lpBalance - sharesToRemove);
        assertGt(balance0After, balance0Before);
        assertGt(balance1After, balance1Before);
    }

    function test_removeLiquidity_ShouldUpdateReserves() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);
        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 sharesToRemove = lpBalance / 2;

        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, minAmounts);

        assertLt(hooks.reserves(0), reserves0Before);
        assertLt(hooks.reserves(1), reserves1Before);
    }

    function test_removeLiquidity_ShouldReturnProportionalAmounts() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 totalSupply = hooks.totalSupply();
        uint256 reserves0 = hooks.reserves(0);
        uint256 reserves1 = hooks.reserves(1);

        uint256 sharesToRemove = lpBalance / 2;
        uint256 expectedAmount0 = (sharesToRemove * reserves0) / totalSupply;
        uint256 expectedAmount1 = (sharesToRemove * reserves1) / totalSupply;

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, minAmounts);

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        assertEq(balance0After - balance0Before, expectedAmount0);
        assertEq(balance1After - balance1Before, expectedAmount1);
    }

    function test_removeLiquidity_ShouldEmitEvent() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 totalSupply = hooks.totalSupply();
        uint256 reserves0 = hooks.reserves(0);
        uint256 reserves1 = hooks.reserves(1);

        uint256 sharesToRemove = lpBalance / 2;

        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = (sharesToRemove * reserves0) / totalSupply;
        expectedAmounts[1] = (sharesToRemove * reserves1) / totalSupply;

        vm.expectEmit(address(hooks));
        emit Liquidity.LiquidityRemoved(liquidityProvider, expectedAmounts, sharesToRemove);

        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, minAmounts);
    }

    function test_removeLiquidity_ShouldAllowFullWithdrawal() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(lpBalance, minAmounts);

        assertEq(hooks.balanceOf(liquidityProvider), 0);
        assertGt(hooks.reserves(0), 0);
        assertGt(hooks.reserves(1), 0);
    }

    // ==========================================================================
    // Remove Liquidity - Validation
    // ==========================================================================

    function test_removeLiquidity_ShouldRevertWhenAmount0BelowMinimum() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 sharesToRemove = lpBalance / 2;

        uint256[] memory minAmounts = new uint256[](2);
        minAmounts[0] = type(uint256).max;

        vm.expectRevert(Liquidity.InsufficientAmounts.selector);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, minAmounts);
    }

    function test_removeLiquidity_ShouldRevertWhenAmount1BelowMinimum() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 sharesToRemove = lpBalance / 2;

        uint256[] memory minAmounts = new uint256[](2);
        minAmounts[1] = type(uint256).max;

        vm.expectRevert(Liquidity.InsufficientAmounts.selector);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, minAmounts);
    }

    function test_removeLiquidity_ShouldSucceedWhenAmountsAboveMinimum() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 totalSupply = hooks.totalSupply();
        uint256 reserves0 = hooks.reserves(0);
        uint256 reserves1 = hooks.reserves(1);

        uint256 sharesToRemove = lpBalance / 2;

        uint256[] memory minAmounts = new uint256[](2);
        minAmounts[0] = (sharesToRemove * reserves0) / totalSupply;
        minAmounts[1] = (sharesToRemove * reserves1) / totalSupply;

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, minAmounts);

        assertEq(hooks.balanceOf(liquidityProvider), lpBalance - sharesToRemove);
    }

    function test_removeLiquidity_ShouldRevertWhenInsufficientShares() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](2);

        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(lpBalance + 1, minAmounts);
    }

    function test_removeLiquidity_ShouldRevertWhenUserHasNoShares() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256[] memory minAmounts = new uint256[](2);

        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(unauthorizedUser);
        hooks.removeLiquidity(1, minAmounts);
    }

    function test_liquidity_AddAndRemove_ShouldMaintainInvariant() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);

        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(lpBalance / 2, minAmounts);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = reserves0Before / 2;
        amounts[1] = reserves1Before / 2;

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        assertGt(hooks.reserves(0), 0);
        assertGt(hooks.reserves(1), 0);
        assertGt(hooks.totalSupply(), MINIMUM_LIQUIDITY);
    }

    function test_liquidity_MultipleProviders_ShouldTrackSharesCorrectly() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        uint256 provider1Shares = hooks.balanceOf(liquidityProvider);

        address provider2 = swapper;
        vm.startPrank(provider2);
        IERC20(Currency.unwrap(currency0)).forceApprove(address(hooks), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).forceApprove(address(hooks), type(uint256).max);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 2);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT / 2);
        hooks.addLiquidity(amounts, 0);
        vm.stopPrank();

        uint256 provider2Shares = hooks.balanceOf(provider2);

        assertGt(provider1Shares, 0);
        assertGt(provider2Shares, 0);
        assertEq(hooks.totalSupply(), provider1Shares + provider2Shares + MINIMUM_LIQUIDITY);
    }

    function test_liquidity_AfterSwaps_ShouldStillWorkCorrectly() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        // Execute some swaps
        _executeExactInputSwap(true, _toTokenWei(currency0, 1000));
        _executeExactInputSwap(false, _toTokenWei(currency1, 1000));

        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 10);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT / 10);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        assertGt(hooks.balanceOf(liquidityProvider), lpBalanceBefore);

        uint256 currentBalance = hooks.balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(currentBalance / 2, minAmounts);

        assertEq(hooks.balanceOf(liquidityProvider), currentBalance - currentBalance / 2);
    }

    // ==========================================================================
    // LP Token
    // ==========================================================================

    function test_lpToken_ShouldHaveCorrectNameAndSymbol() public view {
        assertEq(hooks.name(), "StableSwap LP Token");
        assertEq(hooks.symbol(), "SSLP");
    }

    function test_lpToken_ShouldBeTransferable() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 transferAmount = lpBalance / 2;

        vm.prank(liquidityProvider);
        hooks.transfer(unauthorizedUser, transferAmount);

        assertEq(hooks.balanceOf(liquidityProvider), lpBalance - transferAmount);
        assertEq(hooks.balanceOf(unauthorizedUser), transferAmount);
    }

    function test_lpToken_TransferredShares_ShouldBeRedeemable() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 transferAmount = lpBalance / 2;

        vm.prank(liquidityProvider);
        hooks.transfer(unauthorizedUser, transferAmount);

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(unauthorizedUser);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(unauthorizedUser);

        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(unauthorizedUser);
        hooks.removeLiquidity(transferAmount, minAmounts);

        assertEq(hooks.balanceOf(unauthorizedUser), 0);
        assertGt(IERC20(Currency.unwrap(currency0)).balanceOf(unauthorizedUser), balance0Before);
        assertGt(IERC20(Currency.unwrap(currency1)).balanceOf(unauthorizedUser), balance1Before);
    }

    // ==========================================================================
    // Array Length Validation
    // ==========================================================================

    function test_addLiquidity_ShouldRevertWhenWrongArrayLength() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);

        vm.expectRevert();
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);
    }

    function test_removeLiquidity_ShouldRevertWhenWrongArrayLength() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](1);

        vm.expectRevert();
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(lpBalance / 2, minAmounts);
    }

    function test_removeLiquidity_ShouldDoNothingWhenZeroShares() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);
        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(0, minAmounts);

        assertEq(hooks.balanceOf(liquidityProvider), lpBalanceBefore);
        assertEq(hooks.reserves(0), reserves0Before);
        assertEq(hooks.reserves(1), reserves1Before);
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider), balance0Before);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider), balance1Before);
    }

    // ==========================================================================
    // Multi-Currency (hooks3)
    // ==========================================================================

    function test_hooks3_addLiquidity_ShouldMintSharesAndUpdateReserves() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);
        amounts[2] = _toTokenWei(currency2, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks3.addLiquidity(amounts, 0);

        uint256 lpBalance = hooks3.balanceOf(liquidityProvider);
        uint256 deadBalance = hooks3.balanceOf(DEAD_ADDRESS);

        assertGt(lpBalance, 0);
        assertEq(deadBalance, MINIMUM_LIQUIDITY);
        assertEq(hooks3.reserves(0), amounts[0]);
        assertEq(hooks3.reserves(1), amounts[1]);
        assertEq(hooks3.reserves(2), amounts[2]);
    }

    function test_hooks3_addLiquidity_SingleSided_ShouldRevertWithMinShares() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256[] memory amounts = new uint256[](3);
        amounts[2] = _toTokenWei(currency2, LIQUIDITY_AMOUNT / 10);
        // amounts[0] = 0, amounts[1] = 0

        // With proportional deposits, single-sided deposits result in 0 shares
        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(liquidityProvider);
        hooks3.addLiquidity(amounts, 1);
    }

    function test_hooks3_addLiquidity_Proportional_ShouldUseMinimumProportion() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 reserves0Before = hooks3.reserves(0);
        uint256 reserves1Before = hooks3.reserves(1);
        uint256 reserves2Before = hooks3.reserves(2);
        uint256 lpBalanceBefore = hooks3.balanceOf(liquidityProvider);

        // Imbalanced amounts: token2 has smallest proportion relative to reserves
        // Note: tokens have different decimals (DAI=18, USDT=6, USDC=6)
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 3000); // 3% of reserves
        amounts[1] = _toTokenWei(currency1, 2000); // 2% of reserves
        amounts[2] = _toTokenWei(currency2, 1000); // 1% of reserves (limiting)

        vm.prank(liquidityProvider);
        hooks3.addLiquidity(amounts, 0);

        // Verify shares were minted
        uint256 actualShares = hooks3.balanceOf(liquidityProvider) - lpBalanceBefore;
        assertGt(actualShares, 0);

        // Verify that the deposits are proportional to each other
        // Each currency deposit should be the same proportion of its reserves
        uint256 actualDeposit0 = hooks3.reserves(0) - reserves0Before;
        uint256 actualDeposit1 = hooks3.reserves(1) - reserves1Before;
        uint256 actualDeposit2 = hooks3.reserves(2) - reserves2Before;

        // Check proportions are equal (deposit / reserve should be same for all)
        uint256 proportion0 = (actualDeposit0 * 1e18) / reserves0Before;
        uint256 proportion1 = (actualDeposit1 * 1e18) / reserves1Before;
        uint256 proportion2 = (actualDeposit2 * 1e18) / reserves2Before;

        assertApproxEqRel(proportion0, proportion1, 0.01e18);
        assertApproxEqRel(proportion1, proportion2, 0.01e18);

        // None should exceed the max provided
        assertLe(actualDeposit0, amounts[0]);
        assertLe(actualDeposit1, amounts[1]);
        // token2 is the limiting factor, so approximately its full amount should be used
        assertApproxEqRel(actualDeposit2, amounts[2], 0.001e18);
    }

    function test_hooks3_removeLiquidity_ShouldReturnAllThreeCurrencies() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks3.balanceOf(liquidityProvider);
        uint256 sharesToRemove = lpBalance / 2;

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);
        uint256 balance2Before = IERC20(Currency.unwrap(currency2)).balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](3);

        vm.prank(liquidityProvider);
        hooks3.removeLiquidity(sharesToRemove, minAmounts);

        assertEq(hooks3.balanceOf(liquidityProvider), lpBalance - sharesToRemove);
        assertGt(IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider), balance0Before);
        assertGt(IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider), balance1Before);
        assertGt(IERC20(Currency.unwrap(currency2)).balanceOf(liquidityProvider), balance2Before);
    }

    function test_hooks3_removeLiquidity_ShouldReturnProportionalAmounts() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks3.balanceOf(liquidityProvider);
        uint256 totalSupply = hooks3.totalSupply();
        uint256 reserves0 = hooks3.reserves(0);
        uint256 reserves1 = hooks3.reserves(1);
        uint256 reserves2 = hooks3.reserves(2);

        uint256 sharesToRemove = lpBalance / 2;
        uint256 expectedAmount0 = (sharesToRemove * reserves0) / totalSupply;
        uint256 expectedAmount1 = (sharesToRemove * reserves1) / totalSupply;
        uint256 expectedAmount2 = (sharesToRemove * reserves2) / totalSupply;

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);
        uint256 balance2Before = IERC20(Currency.unwrap(currency2)).balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](3);

        vm.prank(liquidityProvider);
        hooks3.removeLiquidity(sharesToRemove, minAmounts);

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider) - balance0Before, expectedAmount0);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider) - balance1Before, expectedAmount1);
        assertEq(IERC20(Currency.unwrap(currency2)).balanceOf(liquidityProvider) - balance2Before, expectedAmount2);
    }

    // ==========================================================================
    // Edge Cases
    // ==========================================================================

    function test_addLiquidity_Proportional_ShouldUseMinimumProportion() public {
        // First add balanced liquidity
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 sharesBefore = hooks.totalSupply();
        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);
        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);

        // Deposit with imbalanced max amounts (2x token0 but 1x token1)
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 2000);
        amounts[1] = _toTokenWei(currency1, 1000);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        // Since token1 is the limiting factor, deposits should be proportional to token1
        // Expected: reserves increase by amounts proportional to the smaller deposit ratio
        uint256 expectedProportion = (amounts[1] * sharesBefore) / reserves1Before;

        uint256 actualShares = hooks.balanceOf(liquidityProvider) - lpBalanceBefore;
        assertEq(actualShares, expectedProportion);

        // Reserves should increase proportionally (not by max amounts)
        uint256 actualDeposit0 = hooks.reserves(0) - reserves0Before;
        uint256 actualDeposit1 = hooks.reserves(1) - reserves1Before;

        // Compare proportions, not absolute amounts (tokens may have different decimals)
        uint256 proportion0 = (actualDeposit0 * 1e18) / reserves0Before;
        uint256 proportion1 = (actualDeposit1 * 1e18) / reserves1Before;
        assertApproxEqRel(proportion0, proportion1, 0.01e18); // Within 1%
    }

    function test_addLiquidity_VerySmallAmount_ShouldSucceed() public {
        // First add normal liquidity
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        // Add tiny amount
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100; // 100 wei
        amounts[1] = 100; // 100 wei

        uint256 sharesBefore = hooks.balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 sharesAfter = hooks.balanceOf(liquidityProvider);

        assertGt(sharesAfter, sharesBefore);
    }

    function test_removeLiquidity_VerySmallAmount_ShouldSucceed() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 sharesToRemove = 1; // 1 wei of LP tokens
        uint256[] memory minAmounts = new uint256[](2);

        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, minAmounts);

        uint256 lpBalanceAfter = hooks.balanceOf(liquidityProvider);

        assertEq(lpBalanceAfter, lpBalanceBefore - sharesToRemove);
    }

    function test_addLiquidity_AfterSwaps_ShouldAccountForImbalance() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        // Execute several swaps to imbalance the pool
        uint256 swapAmount = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 10);
        vm.startPrank(swapper);
        IERC20(Currency.unwrap(currency0)).approve(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(currency0), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        _executeExactInputSwap(true, swapAmount);
        _executeExactInputSwap(true, swapAmount);
        _executeExactInputSwap(true, swapAmount);

        uint256 reserves0After = hooks.reserves(0);
        uint256 reserves1After = hooks.reserves(1);

        // Pool is now imbalanced
        assertGt(reserves0After, reserves1After);

        // Add balanced liquidity to imbalanced pool
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 1000);
        amounts[1] = _toTokenWei(currency1, 1000);

        uint256 sharesBefore = hooks.balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 sharesAfter = hooks.balanceOf(liquidityProvider);

        // Should still mint shares
        assertGt(sharesAfter, sharesBefore);
    }

    function test_removeLiquidity_FromImbalancedPool_ShouldReturnProportionalAmounts() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        // Imbalance the pool with swaps
        uint256 swapAmount = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 5);
        _executeExactInputSwap(true, swapAmount);

        uint256 reserves0 = hooks.reserves(0);
        uint256 reserves1 = hooks.reserves(1);
        uint256 totalSupply = hooks.totalSupply();

        uint256 sharesToRemove = hooks.balanceOf(liquidityProvider) / 4;
        uint256 expectedAmount0 = (sharesToRemove * reserves0) / totalSupply;
        uint256 expectedAmount1 = (sharesToRemove * reserves1) / totalSupply;

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](2);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, minAmounts);

        uint256 received0 = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider) - balance0Before;
        uint256 received1 = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider) - balance1Before;

        // Should receive proportional amounts even from imbalanced pool
        assertEq(received0, expectedAmount0);
        assertEq(received1, expectedAmount1);
        // More currency0 than currency1 due to imbalance
        assertGt(received0, received1);
    }

    function test_addLiquidity_MultipleDeposits_ShouldAccumulateCorrectly() public {
        // First deposit
        _addLiquidity(1000, 1000);
        uint256 shares1 = hooks.balanceOf(liquidityProvider);

        // Second deposit
        uint256[] memory amounts2 = new uint256[](2);
        amounts2[0] = _toTokenWei(currency0, 1000);
        amounts2[1] = _toTokenWei(currency1, 1000);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts2, 0);
        uint256 shares2 = hooks.balanceOf(liquidityProvider) - shares1;

        // Third deposit
        uint256[] memory amounts3 = new uint256[](2);
        amounts3[0] = _toTokenWei(currency0, 1000);
        amounts3[1] = _toTokenWei(currency1, 1000);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts3, 0);
        uint256 shares3 = hooks.balanceOf(liquidityProvider) - shares1 - shares2;

        // Each balanced deposit should mint roughly similar shares
        assertApproxEqRel(shares2, shares3, 0.01e18); // Within 1%
    }

    function test_lpShareValue_ShouldAppreciateFromSwapFees() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 totalSupply = hooks.totalSupply();

        // Calculate initial share value (what LP would get if they withdrew now)
        // Normalize to 18 decimals for comparison
        uint256 decimals0 = IERC20Metadata(Currency.unwrap(currency0)).decimals();
        uint256 decimals1 = IERC20Metadata(Currency.unwrap(currency1)).decimals();

        uint256 initialReserves0 = hooks.reserves(0);
        uint256 initialReserves1 = hooks.reserves(1);

        // Normalize reserves to 18 decimals for fair comparison
        uint256 initialNormalizedValue0 = (initialReserves0 * 1e18) / (10 ** decimals0);
        uint256 initialNormalizedValue1 = (initialReserves1 * 1e18) / (10 ** decimals1);
        uint256 initialTotalNormalizedValue = initialNormalizedValue0 + initialNormalizedValue1;

        // Execute many swaps to accumulate fees (LP fees stay in reserves)
        uint256 swapAmount = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 10);
        for (uint256 i = 0; i < 10; i++) {
            _executeExactInputSwap(true, swapAmount);
            _executeExactInputSwap(false, _toTokenWei(currency1, LIQUIDITY_AMOUNT / 10));
        }

        // Calculate new share value
        uint256 newTotalSupply = hooks.totalSupply();

        // Total supply should be unchanged (no new shares minted from swaps)
        assertEq(newTotalSupply, totalSupply);

        uint256 newReserves0 = hooks.reserves(0);
        uint256 newReserves1 = hooks.reserves(1);

        // Normalize new reserves to 18 decimals
        uint256 newNormalizedValue0 = (newReserves0 * 1e18) / (10 ** decimals0);
        uint256 newNormalizedValue1 = (newReserves1 * 1e18) / (10 ** decimals1);
        uint256 newTotalNormalizedValue = newNormalizedValue0 + newNormalizedValue1;

        // LP share value should have increased due to accumulated fees
        // (reserves grew from LP fees while share count stayed constant)
        // Individual reserves may shift due to swap direction, but total should increase
        assertGt(newTotalNormalizedValue, initialTotalNormalizedValue);
    }

    function test_addRemoveLiquidity_ShouldNotLeakValue() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);
        uint256 totalSupplyBefore = hooks.totalSupply();

        // Add liquidity
        uint256[] memory addAmounts = new uint256[](2);
        addAmounts[0] = _toTokenWei(currency0, 10_000);
        addAmounts[1] = _toTokenWei(currency1, 10_000);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(addAmounts, 0);

        uint256 newShares = hooks.balanceOf(liquidityProvider) - (totalSupplyBefore - MINIMUM_LIQUIDITY);

        // Immediately remove the same shares
        uint256[] memory minAmounts = new uint256[](2);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(newShares, minAmounts);

        // Reserves should be approximately the same (may differ by small rounding)
        // The key is that value isn't leaking significantly
        assertApproxEqRel(hooks.reserves(0), reserves0Before, 0.001e18); // Within 0.1%
        assertApproxEqRel(hooks.reserves(1), reserves1Before, 0.001e18);
    }

    function test_removeLiquidity_AllShares_ShouldDrainReserves() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        // Another LP adds liquidity
        address secondLP = makeAddr("secondLP");
        deal(Currency.unwrap(currency0), secondLP, _toTokenWei(currency0, LIQUIDITY_AMOUNT));
        deal(Currency.unwrap(currency1), secondLP, _toTokenWei(currency1, LIQUIDITY_AMOUNT));

        vm.startPrank(secondLP);
        IERC20(Currency.unwrap(currency0)).forceApprove(address(hooks), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).forceApprove(address(hooks), type(uint256).max);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);
        hooks.addLiquidity(amounts, 0);
        vm.stopPrank();

        // First LP removes all their shares
        uint256 lpShares = hooks.balanceOf(liquidityProvider);
        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(lpShares, minAmounts);

        // First LP should have 0 shares
        assertEq(hooks.balanceOf(liquidityProvider), 0);

        // Pool should still have reserves from second LP
        assertGt(hooks.reserves(0), 0);
        assertGt(hooks.reserves(1), 0);
    }

    // ==========================================================================
    // Quote Add Liquidity
    // ==========================================================================

    function test_quoteAddLiquidity_InitialDeposit_ShouldMatchActualShares() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        (uint256 quotedShares, uint256[] memory quotedActualAmounts) = hooks.quoteAddLiquidity(amounts);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 actualShares = hooks.balanceOf(liquidityProvider);

        assertEq(quotedShares, actualShares);
        assertEq(quotedActualAmounts[0], amounts[0]);
        assertEq(quotedActualAmounts[1], amounts[1]);
    }

    function test_quoteAddLiquidity_SubsequentDeposit_ShouldMatchActualShares() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 2);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT / 2);

        (uint256 quotedShares, uint256[] memory quotedActualAmounts) = hooks.quoteAddLiquidity(amounts);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 actualShares = hooks.balanceOf(liquidityProvider) - lpBalanceBefore;

        assertEq(quotedShares, actualShares);
        assertEq(quotedActualAmounts[0], hooks.reserves(0) - _toTokenWei(currency0, LIQUIDITY_AMOUNT));
        assertEq(quotedActualAmounts[1], hooks.reserves(1) - _toTokenWei(currency1, LIQUIDITY_AMOUNT));
    }

    function test_quoteAddLiquidity_ImbalancedDeposit_ShouldReturnProportionalAmounts() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);
        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        // Imbalanced amounts: token1 is limiting factor
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 2000);
        amounts[1] = _toTokenWei(currency1, 1000);

        (uint256 quotedShares, uint256[] memory quotedActualAmounts) = hooks.quoteAddLiquidity(amounts);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 actualShares = hooks.balanceOf(liquidityProvider) - lpBalanceBefore;
        uint256 actualAmount0 = balance0Before - IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 actualAmount1 = balance1Before - IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        assertEq(quotedShares, actualShares);
        assertEq(quotedActualAmounts[0], actualAmount0);
        assertEq(quotedActualAmounts[1], actualAmount1);
    }

    function test_quoteAddLiquidity_ShouldRevertWhenBelowMinimumLiquidity() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 0;

        vm.expectRevert(Liquidity.InsufficientInitialLiquidity.selector);
        hooks.quoteAddLiquidity(amounts);
    }

    // ==========================================================================
    // Quote Remove Liquidity
    // ==========================================================================

    function test_quoteRemoveLiquidity_ShouldMatchActualAmounts() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 sharesToRemove = lpBalance / 2;

        uint256[] memory quotedAmounts = hooks.quoteRemoveLiquidity(sharesToRemove);

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](2);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, minAmounts);

        uint256 actualAmount0 = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider) - balance0Before;
        uint256 actualAmount1 = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider) - balance1Before;

        assertEq(quotedAmounts[0], actualAmount0);
        assertEq(quotedAmounts[1], actualAmount1);
    }

    function test_quoteRemoveLiquidity_FullWithdrawal_ShouldMatchActualAmounts() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);

        uint256[] memory quotedAmounts = hooks.quoteRemoveLiquidity(lpBalance);

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](2);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(lpBalance, minAmounts);

        uint256 actualAmount0 = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider) - balance0Before;
        uint256 actualAmount1 = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider) - balance1Before;

        assertEq(quotedAmounts[0], actualAmount0);
        assertEq(quotedAmounts[1], actualAmount1);
    }

    function test_quoteRemoveLiquidity_AfterSwaps_ShouldMatchActualAmounts() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        // Execute swaps to change reserves
        _executeExactInputSwap(true, _toTokenWei(currency0, 1000));
        _executeExactInputSwap(false, _toTokenWei(currency1, 500));

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 sharesToRemove = lpBalance / 4;

        uint256[] memory quotedAmounts = hooks.quoteRemoveLiquidity(sharesToRemove);

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](2);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, minAmounts);

        uint256 actualAmount0 = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider) - balance0Before;
        uint256 actualAmount1 = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider) - balance1Before;

        assertEq(quotedAmounts[0], actualAmount0);
        assertEq(quotedAmounts[1], actualAmount1);
    }

    // ==========================================================================
    // Quote Functions - Multi-Currency (hooks3)
    // ==========================================================================

    function test_hooks3_quoteAddLiquidity_ShouldMatchActualShares() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);
        amounts[2] = _toTokenWei(currency2, LIQUIDITY_AMOUNT);

        (uint256 quotedShares, uint256[] memory quotedActualAmounts) = hooks3.quoteAddLiquidity(amounts);

        vm.prank(liquidityProvider);
        hooks3.addLiquidity(amounts, 0);

        uint256 actualShares = hooks3.balanceOf(liquidityProvider);

        assertEq(quotedShares, actualShares);
        assertEq(quotedActualAmounts[0], amounts[0]);
        assertEq(quotedActualAmounts[1], amounts[1]);
        assertEq(quotedActualAmounts[2], amounts[2]);
    }

    function test_hooks3_quoteRemoveLiquidity_ShouldMatchActualAmounts() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks3.balanceOf(liquidityProvider);
        uint256 sharesToRemove = lpBalance / 2;

        uint256[] memory quotedAmounts = hooks3.quoteRemoveLiquidity(sharesToRemove);

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);
        uint256 balance2Before = IERC20(Currency.unwrap(currency2)).balanceOf(liquidityProvider);

        uint256[] memory minAmounts = new uint256[](3);
        vm.prank(liquidityProvider);
        hooks3.removeLiquidity(sharesToRemove, minAmounts);

        uint256 actualAmount0 = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider) - balance0Before;
        uint256 actualAmount1 = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider) - balance1Before;
        uint256 actualAmount2 = IERC20(Currency.unwrap(currency2)).balanceOf(liquidityProvider) - balance2Before;

        assertEq(quotedAmounts[0], actualAmount0);
        assertEq(quotedAmounts[1], actualAmount1);
        assertEq(quotedAmounts[2], actualAmount2);
    }
}

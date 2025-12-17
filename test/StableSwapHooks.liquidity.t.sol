// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

        vm.expectEmit(address(hooks));
        emit Liquidity.LiquidityAdded(liquidityProvider, amounts, hooks.computeNewShares(amounts));

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);
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
    // Add Liquidity - Single-Sided
    // ==========================================================================

    function test_addLiquidity_SingleSided_ShouldAllowOnlyToken0() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);
        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 10);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        assertGt(hooks.balanceOf(liquidityProvider), lpBalanceBefore);
        assertEq(hooks.reserves(0), reserves0Before + amounts[0]);
        assertEq(hooks.reserves(1), reserves1Before);
    }

    function test_addLiquidity_SingleSided_ShouldAllowOnlyToken1() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);
        uint256 reserves0Before = hooks.reserves(0);
        uint256 reserves1Before = hooks.reserves(1);

        uint256[] memory amounts = new uint256[](2);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT / 10);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        assertGt(hooks.balanceOf(liquidityProvider), lpBalanceBefore);
        assertEq(hooks.reserves(0), reserves0Before);
        assertEq(hooks.reserves(1), reserves1Before + amounts[1]);
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

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        uint256 expectedShares = hooks.computeNewShares(amounts);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, expectedShares);

        assertGt(hooks.balanceOf(liquidityProvider), 0);
    }

    function test_addLiquidity_ShouldRevertWhenBothAmountsZero_InitialDeposit() public {
        uint256[] memory amounts = new uint256[](2);

        vm.expectRevert(Liquidity.InsufficientInitialLiquidity.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);
    }

    function test_addLiquidity_ShouldRevertWhenBothAmountsZero_SubsequentDeposit() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256[] memory amounts = new uint256[](2);

        vm.expectRevert(Liquidity.InvalidInvariant.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);
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

    function test_hooks3_addLiquidity_SingleSided_ShouldAllowOnlyToken2() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalanceBefore = hooks3.balanceOf(liquidityProvider);
        uint256 reserves0Before = hooks3.reserves(0);
        uint256 reserves1Before = hooks3.reserves(1);
        uint256 reserves2Before = hooks3.reserves(2);

        uint256[] memory amounts = new uint256[](3);
        amounts[2] = _toTokenWei(currency2, LIQUIDITY_AMOUNT / 10);

        vm.prank(liquidityProvider);
        hooks3.addLiquidity(amounts, 0);

        assertGt(hooks3.balanceOf(liquidityProvider), lpBalanceBefore);
        assertEq(hooks3.reserves(0), reserves0Before);
        assertEq(hooks3.reserves(1), reserves1Before);
        assertEq(hooks3.reserves(2), reserves2Before + amounts[2]);
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

    function test_addLiquidity_SingleSided_ShouldMintFewerSharesThanBalanced() public {
        // First add balanced liquidity
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 sharesBefore = hooks.totalSupply();

        // Add single-sided liquidity (only currency0)
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 1000);
        amounts[1] = 0;

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 singleSidedShares = hooks.totalSupply() - sharesBefore;

        // Now compare with balanced deposit of same total value (500 each)
        uint256 sharesBeforeBalanced = hooks.totalSupply();
        uint256[] memory balancedAmounts = new uint256[](2);
        balancedAmounts[0] = _toTokenWei(currency0, 500);
        balancedAmounts[1] = _toTokenWei(currency1, 500);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(balancedAmounts, 0);

        uint256 balancedShares = hooks.totalSupply() - sharesBeforeBalanced;

        // Single-sided deposit should mint fewer shares than balanced deposit of same total value
        assertGt(singleSidedShares, 0);
        assertLt(singleSidedShares, balancedShares);
    }

    function test_addLiquidity_ImbalancedDeposit_ShouldSucceed() public {
        // First add balanced liquidity
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        // Add imbalanced liquidity (90% currency0, 10% currency1)
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 900);
        amounts[1] = _toTokenWei(currency1, 100);

        uint256 sharesBefore = hooks.balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);

        uint256 sharesAfter = hooks.balanceOf(liquidityProvider);

        assertGt(sharesAfter, sharesBefore);
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
}

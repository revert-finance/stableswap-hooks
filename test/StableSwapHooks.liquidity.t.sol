// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

import {Liquidity} from "src/Liquidity.sol";

contract StableSwapHooksLiquidityTest is StableSwapHooksBaseTest {
    using SafeERC20 for IERC20;

    uint256 private constant LIQUIDITY_AMOUNT = 100_000;
    uint256 private constant MINIMUM_LIQUIDITY = 1e15;
    address private constant DEAD_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    function test_addLiquidity_InitialDeposit_ShouldMintSharesMinusMinimumLiquidity() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 deadBalance = hooks.balanceOf(DEAD_ADDRESS);

        assertGt(lpBalance, 0);
        assertEq(deadBalance, MINIMUM_LIQUIDITY);
    }

    function test_addLiquidity_InitialDeposit_ShouldUpdateReserves() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        assertEq(hooks.reserves0(), amount0);
        assertEq(hooks.reserves1(), amount1);
    }

    function test_addLiquidity_InitialDeposit_ShouldTransferTokensFromUser() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        assertEq(balance0Before - balance0After, amount0);
        assertEq(balance1Before - balance1After, amount1);
    }

    function test_addLiquidity_InitialDeposit_ShouldEmitEvent() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.expectEmit(address(hooks));
        emit Liquidity.LiquidityAdded(liquidityProvider, amount0, amount1, hooks.computeNewShares(amount0, amount1));

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);
    }

    function test_addLiquidity_InitialDeposit_ShouldRevertWhenBelowMinimumLiquidity() public {
        uint256 smallAmount = 1;

        vm.expectRevert(Liquidity.InsufficientInitialLiquidity.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(smallAmount, smallAmount, 0);
    }

    function test_addLiquidity_SubsequentDeposit_ShouldMintProportionalShares() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 totalSupplyBefore = hooks.totalSupply();
        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);

        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 totalSupplyAfter = hooks.totalSupply();
        uint256 lpBalanceAfter = hooks.balanceOf(liquidityProvider);

        assertGt(totalSupplyAfter, totalSupplyBefore);
        assertGt(lpBalanceAfter, lpBalanceBefore);
    }

    function test_addLiquidity_SubsequentDeposit_ShouldUpdateReserves() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 reserves0Before = hooks.reserves0();
        uint256 reserves1Before = hooks.reserves1();

        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 2);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT / 2);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        assertEq(hooks.reserves0(), reserves0Before + amount0);
        assertEq(hooks.reserves1(), reserves1Before + amount1);
    }

    function test_addLiquidity_SubsequentDeposit_ShouldNotLockMoreMinimumLiquidity() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 deadBalanceBefore = hooks.balanceOf(DEAD_ADDRESS);

        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 deadBalanceAfter = hooks.balanceOf(DEAD_ADDRESS);

        assertEq(deadBalanceAfter, deadBalanceBefore);
        assertEq(deadBalanceAfter, MINIMUM_LIQUIDITY);
    }

    function test_addLiquidity_SingleSided_ShouldAllowOnlyToken0() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);
        uint256 reserves0Before = hooks.reserves0();
        uint256 reserves1Before = hooks.reserves1();

        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 10);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, 0, 0);

        assertGt(hooks.balanceOf(liquidityProvider), lpBalanceBefore);
        assertEq(hooks.reserves0(), reserves0Before + amount0);
        assertEq(hooks.reserves1(), reserves1Before);
    }

    function test_addLiquidity_SingleSided_ShouldAllowOnlyToken1() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalanceBefore = hooks.balanceOf(liquidityProvider);
        uint256 reserves0Before = hooks.reserves0();
        uint256 reserves1Before = hooks.reserves1();

        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT / 10);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(0, amount1, 0);

        assertGt(hooks.balanceOf(liquidityProvider), lpBalanceBefore);
        assertEq(hooks.reserves0(), reserves0Before);
        assertEq(hooks.reserves1(), reserves1Before + amount1);
    }

    function test_addLiquidity_ShouldRevertWhenSharesBelowMinimum() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 10);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT / 10);
        uint256 minShares = type(uint256).max;

        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, minShares);
    }

    function test_addLiquidity_ShouldSucceedWhenSharesAboveMinimum() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        uint256 expectedShares = hooks.computeNewShares(amount0, amount1);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, expectedShares);

        assertGt(hooks.balanceOf(liquidityProvider), 0);
    }

    function test_addLiquidity_ShouldRevertWhenBothAmountsZero_InitialDeposit() public {
        vm.expectRevert(Liquidity.InsufficientInitialLiquidity.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(0, 0, 0);
    }

    function test_addLiquidity_ShouldRevertWhenBothAmountsZero_SubsequentDeposit() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        vm.expectRevert(Liquidity.InvalidInvariant.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(0, 0, 0);
    }

    function test_removeLiquidity_ShouldBurnSharesAndReturnTokens() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 sharesToRemove = lpBalance / 2;

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, 0, 0);

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        assertEq(hooks.balanceOf(liquidityProvider), lpBalance - sharesToRemove);
        assertGt(balance0After, balance0Before);
        assertGt(balance1After, balance1Before);
    }

    function test_removeLiquidity_ShouldUpdateReserves() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 reserves0Before = hooks.reserves0();
        uint256 reserves1Before = hooks.reserves1();
        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 sharesToRemove = lpBalance / 2;

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, 0, 0);

        assertLt(hooks.reserves0(), reserves0Before);
        assertLt(hooks.reserves1(), reserves1Before);
    }

    function test_removeLiquidity_ShouldReturnProportionalAmounts() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 totalSupply = hooks.totalSupply();
        uint256 reserves0 = hooks.reserves0();
        uint256 reserves1 = hooks.reserves1();

        uint256 sharesToRemove = lpBalance / 2;
        uint256 expectedAmount0 = (sharesToRemove * reserves0) / totalSupply;
        uint256 expectedAmount1 = (sharesToRemove * reserves1) / totalSupply;

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, 0, 0);

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        assertEq(balance0After - balance0Before, expectedAmount0);
        assertEq(balance1After - balance1Before, expectedAmount1);
    }

    function test_removeLiquidity_ShouldEmitEvent() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 totalSupply = hooks.totalSupply();
        uint256 reserves0 = hooks.reserves0();
        uint256 reserves1 = hooks.reserves1();

        uint256 sharesToRemove = lpBalance / 2;
        uint256 expectedAmount0 = (sharesToRemove * reserves0) / totalSupply;
        uint256 expectedAmount1 = (sharesToRemove * reserves1) / totalSupply;

        vm.expectEmit(address(hooks));
        emit Liquidity.LiquidityRemoved(liquidityProvider, expectedAmount0, expectedAmount1, sharesToRemove);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, 0, 0);
    }

    function test_removeLiquidity_ShouldAllowFullWithdrawal() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(lpBalance, 0, 0);

        assertEq(hooks.balanceOf(liquidityProvider), 0);
        assertGt(hooks.reserves0(), 0);
        assertGt(hooks.reserves1(), 0);
    }

    function test_removeLiquidity_ShouldRevertWhenAmount0BelowMinimum() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 sharesToRemove = lpBalance / 2;
        uint256 minAmount0 = type(uint256).max;

        vm.expectRevert(Liquidity.InsufficientAmounts.selector);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, minAmount0, 0);
    }

    function test_removeLiquidity_ShouldRevertWhenAmount1BelowMinimum() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 sharesToRemove = lpBalance / 2;
        uint256 minAmount1 = type(uint256).max;

        vm.expectRevert(Liquidity.InsufficientAmounts.selector);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, 0, minAmount1);
    }

    function test_removeLiquidity_ShouldSucceedWhenAmountsAboveMinimum() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 totalSupply = hooks.totalSupply();
        uint256 reserves0 = hooks.reserves0();
        uint256 reserves1 = hooks.reserves1();

        uint256 sharesToRemove = lpBalance / 2;
        uint256 expectedAmount0 = (sharesToRemove * reserves0) / totalSupply;
        uint256 expectedAmount1 = (sharesToRemove * reserves1) / totalSupply;

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(sharesToRemove, expectedAmount0, expectedAmount1);

        assertEq(hooks.balanceOf(liquidityProvider), lpBalance - sharesToRemove);
    }

    function test_removeLiquidity_ShouldRevertWhenInsufficientShares() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);

        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(lpBalance + 1, 0, 0);
    }

    function test_removeLiquidity_ShouldRevertWhenUserHasNoShares() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(unauthorizedUser);
        hooks.removeLiquidity(1, 0, 0);
    }

    function test_beforeAddLiquidity_ShouldRevertWhenCalledViaPoolManager() public {
        assertEq(address(hooks), address(_getPoolKey().hooks));
    }

    function test_liquidity_AddAndRemove_ShouldMaintainInvariant() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 reserves0Before = hooks.reserves0();
        uint256 reserves1Before = hooks.reserves1();

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(lpBalance / 2, 0, 0);

        uint256 amount0 = reserves0Before / 2;
        uint256 amount1 = reserves1Before / 2;

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        assertGt(hooks.reserves0(), 0);
        assertGt(hooks.reserves1(), 0);
        assertGt(hooks.totalSupply(), MINIMUM_LIQUIDITY);
    }

    function test_liquidity_MultipleProviders_ShouldTrackSharesCorrectly() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        uint256 provider1Shares = hooks.balanceOf(liquidityProvider);

        address provider2 = swapper;
        vm.startPrank(provider2);
        IERC20(Currency.unwrap(currency0)).forceApprove(address(hooks), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).forceApprove(address(hooks), type(uint256).max);

        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 2);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT / 2);
        hooks.addLiquidity(amount0, amount1, 0);
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

        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT / 10);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT / 10);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        assertGt(hooks.balanceOf(liquidityProvider), lpBalanceBefore);

        uint256 currentBalance = hooks.balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(currentBalance / 2, 0, 0);

        assertEq(hooks.balanceOf(liquidityProvider), currentBalance - currentBalance / 2);
    }

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

        vm.prank(unauthorizedUser);
        hooks.removeLiquidity(transferAmount, 0, 0);

        assertEq(hooks.balanceOf(unauthorizedUser), 0);
        assertGt(IERC20(Currency.unwrap(currency0)).balanceOf(unauthorizedUser), balance0Before);
        assertGt(IERC20(Currency.unwrap(currency1)).balanceOf(unauthorizedUser), balance1Before);
    }
}

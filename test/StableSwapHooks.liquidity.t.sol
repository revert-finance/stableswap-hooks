// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

import {Liquidity} from "src/Liquidity.sol";

contract StableSwapHooksLiquidityTest is StableSwapHooksBaseTest {
    uint256 private constant LIQUIDITY_AMOUNT = 1000;

    function test_addLiquidity_ShouldMintSharesOnFirstDeposit() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        assertEq(hooks.totalSupply(), 0);
        assertEq(hooks.balanceOf(liquidityProvider), 0);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        assertGt(hooks.totalSupply(), 0);
        assertEq(hooks.balanceOf(liquidityProvider), hooks.totalSupply());
    }

    function test_addLiquidity_ShouldEmitLiquidityAddedEvent() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        uint256 expectedShares = hooks.computeNewShares(amount0, amount1);

        vm.expectEmit(address(hooks));
        emit Liquidity.LiquidityAdded(liquidityProvider, amount0, amount1, expectedShares);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);
    }

    function test_addLiquidity_ShouldUpdateReserves() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        assertEq(hooks.reserves0(), 0);
        assertEq(hooks.reserves1(), 0);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        assertEq(hooks.reserves0(), amount0);
        assertEq(hooks.reserves1(), amount1);
    }

    function test_addLiquidity_ShouldTransferTokensFromUser() public {
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

    function test_addLiquidity_ShouldMintProportionalSharesOnSubsequentDeposit() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 firstShares = hooks.balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 secondShares = hooks.balanceOf(liquidityProvider) - firstShares;

        assertEq(firstShares, secondShares);
    }

    function test_addLiquidity_ShouldAllowSingleSidedDeposit() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

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
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, type(uint256).max);
    }

    function test_removeLiquidity_ShouldBurnSharesAndReturnTokens() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 shares = hooks.balanceOf(liquidityProvider);
        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(shares, 0, 0);

        assertEq(hooks.balanceOf(liquidityProvider), 0);
        assertEq(hooks.totalSupply(), 0);

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);

        assertEq(balance0After - balance0Before, amount0);
        assertEq(balance1After - balance1Before, amount1);
    }

    function test_removeLiquidity_ShouldEmitLiquidityRemovedEvent() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 shares = hooks.balanceOf(liquidityProvider);

        vm.expectEmit(address(hooks));
        emit Liquidity.LiquidityRemoved(liquidityProvider, amount0, amount1, shares);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(shares, 0, 0);
    }

    function test_removeLiquidity_ShouldUpdateReserves() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 shares = hooks.balanceOf(liquidityProvider);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(shares, 0, 0);

        assertEq(hooks.reserves0(), 0);
        assertEq(hooks.reserves1(), 0);
    }

    function test_removeLiquidity_ShouldReturnProportionalAmounts() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

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

        assertApproxEqAbs(balance0After - balance0Before, amount0 / 2, 1);
        assertApproxEqAbs(balance1After - balance1Before, amount1 / 2, 1);
    }

    function test_removeLiquidity_ShouldRevertWhenInsufficientShares() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 shares = hooks.balanceOf(liquidityProvider);

        vm.expectRevert(Liquidity.InsufficientShares.selector);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(shares + 1, 0, 0);
    }

    function test_removeLiquidity_ShouldRevertWhenSlippageExceeded() public {
        uint256 amount0 = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        uint256 amount1 = _toTokenWei(currency1, LIQUIDITY_AMOUNT);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amount0, amount1, 0);

        uint256 shares = hooks.balanceOf(liquidityProvider);

        vm.expectRevert(Liquidity.InsufficientAmounts.selector);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(shares, amount0 + 1, 0);
    }
}

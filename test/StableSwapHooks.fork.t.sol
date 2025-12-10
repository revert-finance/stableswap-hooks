// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Commands} from "test/testUtils/external/libraries/Commands.sol";
import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

import {StableSwapHooks} from "src/StableSwapHooks.sol";

contract StableSwapHooksForkTest is StableSwapHooksBaseTest {
    /// Tests
    function test_AddThenRemoveLiquidity() public {
        // Add liquidity

        uint256 amount0 = _toTokenWei(currency0, 100);
        uint256 amount1 = _toTokenWei(currency1, 100);

        uint256 balance0 = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1 = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);
        uint256 balanceS = hooks.balanceOf(liquidityProvider);

        uint256 expectedShares = 200e18;

        vm.startPrank(liquidityProvider);
        vm.expectEmit(address(hooks));
        emit StableSwapHooks.LiquidityAdded(liquidityProvider, amount0, amount1, expectedShares);
        hooks.addLiquidity(amount0, amount1, 0);
        vm.stopPrank();

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider), balance0 - amount0);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider), balance1 - amount1);
        assertEq(hooks.balanceOf(liquidityProvider), balanceS + expectedShares);

        // Remove liquidity

        vm.startPrank(liquidityProvider);
        vm.expectEmit(address(hooks));
        emit StableSwapHooks.LiquidityRemoved(liquidityProvider, amount0, amount1, expectedShares);
        hooks.removeLiquidity(expectedShares, 0, 0);
        vm.stopPrank();

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider), balance0);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider), balance1);
        assertEq(hooks.balanceOf(liquidityProvider), balanceS);
    }

    function test_AddLiquidityThenSwap() public {
        // Add liquidity

        uint256 amount0 = _toTokenWei(currency0, 100);
        uint256 amount1 = _toTokenWei(currency1, 100);

        uint256 balance0 = IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider);
        uint256 balance1 = IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider);
        uint256 balanceS = hooks.balanceOf(liquidityProvider);

        uint256 expectedShares = 200e18;

        vm.startPrank(liquidityProvider);
        vm.expectEmit(address(hooks));
        emit StableSwapHooks.LiquidityAdded(liquidityProvider, amount0, amount1, expectedShares);
        hooks.addLiquidity(amount0, amount1, 0);
        vm.stopPrank();

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(liquidityProvider), balance0 - amount0);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(liquidityProvider), balance1 - amount1);
        assertEq(hooks.balanceOf(liquidityProvider), balanceS + expectedShares);

        // Swap

        PoolKey memory poolKey = _getPoolKey();
        uint256 amount0In = _toTokenWei(currency0, 1);

        // V4 Router Actions

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: true,
                amountIn: uint128(amount0In),
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(poolKey.currency0, amount0In);
        params[2] = abi.encode(poolKey.currency1, 0);

        // Universal Router Command

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // Execute swap

        uint256 swapperBalance0 = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 swapperBalance1 = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        vm.prank(swapper);
        universalRouter.execute(commands, inputs, block.timestamp + 100);

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(swapper), swapperBalance0 - amount0In);
        assertApproxEqRel(
            IERC20(Currency.unwrap(currency1)).balanceOf(swapper), swapperBalance1 + _toTokenWei(currency1, 1), 2e14
        );
    }
}

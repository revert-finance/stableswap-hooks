// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {IUniversalRouter} from "test/testUtils/external/interfaces/IUniversalRouter.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";
import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

contract StableSwapHooksForkTest is StableSwapHooksBaseTest {
    function setUp() public override {
        vm.selectFork(vm.createFork(vm.envString("MAINNET_RPC_URL")));
        super.setUp();
    }

    /// Helpers

    /// @dev Initialize the pool via the pool manager
    function _initializePool() private returns (int24) {
        return IPoolManager(address(poolManager)).initialize(_getPoolKey(), 1 << 96);
    }

    /// Tests

    function test_DeployHook() public view {
        assertEq(address(hooks.poolManager()), address(poolManager));
        assertEq(hooks.A(), 100);
        assertEq(hooks.rate0(), 1e18);
        assertEq(hooks.rate1(), 1e30);
        assertEq(PoolId.unwrap(hooks.poolId()), PoolId.unwrap(_getPoolKey().toId()));
    }

    function test_InitializePool() public {
        _initializePool();
    }

    function test_AddThenRemoveLiquidity() public {
        _initializePool();

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
        _initializePool();

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

        vm.prank(swapper);
        universalRouter.execute(commands, inputs, block.timestamp + 100);

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(swapper), swapperBalance0 - amount0In);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(swapper), 1000994925);
    }
}

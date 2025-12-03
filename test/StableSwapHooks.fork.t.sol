// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {IAllowanceTransfer} from "@uniswap/v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {StableSwapHooks} from "../src/StableSwapHooks.sol";
import {IUniversalRouter} from "./interfaces/IUniversalRouter.sol";
import {Commands} from "./libraries/Commands.sol";

contract StableSwapHooksForkTest is Test {
    using SafeERC20 for IERC20;

    address private token0;
    address private token1;
    address private poolManager;
    address private universalRouter;
    address private permit2;
    address private liquidityProvider;
    address private swapper;

    uint256 private decimals0;
    uint256 private decimals1;
    uint256 private initialAmp;

    function setUp() public {
        token0 = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // dai
        token1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // usdt
        poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        universalRouter = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
        permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        liquidityProvider = makeAddr("liquidityProvider");
        swapper = makeAddr("swapper");

        decimals0 = 18;
        decimals1 = 6;
        initialAmp = 1e3;

        vm.selectFork(vm.createFork(vm.envString("MAINNET_RPC_URL")));

        // Deal tokens to the accounts
        uint256 amount0 = 1000 * 10 ** decimals0;
        uint256 amount1 = 1000 * 10 ** decimals1;
        deal(token0, liquidityProvider, amount0);
        deal(token1, liquidityProvider, amount1);
        deal(token0, swapper, amount0);
        deal(token1, swapper, amount1);
    }

    /// Helpers

    /// @dev Deploy the hook with create2 and the correct hook flags
    function _deployHook() private returns (StableSwapHooks) {
        // Hooks flags based on getHookPermissions()
        uint160 flags = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;

        // Mine a salt that produces an address with the correct hook flags
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(StableSwapHooks).creationCode,
            abi.encode(initialAmp, poolManager, token0, token1)
        );

        // Deploy hook using CREATE2 with the mined salt
        return new StableSwapHooks{salt: salt}(
            initialAmp, IPoolManager(poolManager), Currency.wrap(token0), Currency.wrap(token1)
        );
    }

    /// @dev Initialize the pool via the position manager
    function _initializePool(StableSwapHooks hooks) private returns (int24) {
        return IPoolManager(poolManager).initialize(_getPoolKey(hooks), 1 << 96);
    }

    /// @dev Get the pool key with the provided hook
    function _getPoolKey(StableSwapHooks hooks) private returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: hooks.FEE(),
            tickSpacing: hooks.TICK_SPACING(),
            hooks: IHooks(address(hooks))
        });
    }

    /// Tests

    function test_DeployHook() public {
        StableSwapHooks hooks = _deployHook();

        assertEq(address(hooks.poolManager()), poolManager);
        assertEq(hooks.A(), initialAmp);
        assertEq(hooks.rate0(), 1e18);
        assertEq(hooks.rate1(), 1e30);
        assertEq(PoolId.unwrap(hooks.poolId()), PoolId.unwrap(_getPoolKey(hooks).toId()));
    }

    function test_InitializePool() public {
        StableSwapHooks hooks = _deployHook();

        _initializePool(hooks);
    }

    function test_AddThenRemoveLiquidity() public {
        StableSwapHooks hooks = _deployHook();

        _initializePool(hooks);

        // Add liquidity

        uint256 amount0 = 100 * 10 ** decimals0;
        uint256 amount1 = 100 * 10 ** decimals1;

        uint256 balance0 = IERC20(token0).balanceOf(liquidityProvider);
        uint256 balance1 = IERC20(token1).balanceOf(liquidityProvider);
        uint256 balanceS = hooks.balanceOf(liquidityProvider);

        uint256 expectedShares = 200e18;

        vm.startPrank(liquidityProvider);
        IERC20(token0).forceApprove(address(hooks), amount0);
        IERC20(token1).forceApprove(address(hooks), amount1);
        vm.expectEmit(address(hooks));
        emit StableSwapHooks.LiquidityAdded(liquidityProvider, amount0, amount1, expectedShares);
        hooks.addLiquidity(amount0, amount1, 0);
        vm.stopPrank();

        assertEq(IERC20(token0).balanceOf(liquidityProvider), balance0 - amount0);
        assertEq(IERC20(token1).balanceOf(liquidityProvider), balance1 - amount1);
        assertEq(hooks.balanceOf(liquidityProvider), balanceS + expectedShares);

        // Remove liquidity

        vm.startPrank(liquidityProvider);
        vm.expectEmit(address(hooks));
        emit StableSwapHooks.LiquidityRemoved(liquidityProvider, amount0, amount1, expectedShares);
        hooks.removeLiquidity(expectedShares, 0, 0);
        vm.stopPrank();

        assertEq(IERC20(token0).balanceOf(liquidityProvider), balance0);
        assertEq(IERC20(token1).balanceOf(liquidityProvider), balance1);
        assertEq(hooks.balanceOf(liquidityProvider), balanceS);
    }

    function test_AddLiquidityThenSwap() public {
        StableSwapHooks hooks = _deployHook();

        _initializePool(hooks);

        // Add liquidity

        uint256 amount0 = 100 * 10 ** decimals0;
        uint256 amount1 = 100 * 10 ** decimals1;

        uint256 balance0 = IERC20(token0).balanceOf(liquidityProvider);
        uint256 balance1 = IERC20(token1).balanceOf(liquidityProvider);
        uint256 balanceS = hooks.balanceOf(liquidityProvider);

        uint256 expectedShares = 200e18;

        vm.startPrank(liquidityProvider);
        IERC20(token0).forceApprove(address(hooks), amount0);
        IERC20(token1).forceApprove(address(hooks), amount1);
        vm.expectEmit(address(hooks));
        emit StableSwapHooks.LiquidityAdded(liquidityProvider, amount0, amount1, expectedShares);
        hooks.addLiquidity(amount0, amount1, 0);
        vm.stopPrank();

        assertEq(IERC20(token0).balanceOf(liquidityProvider), balance0 - amount0);
        assertEq(IERC20(token1).balanceOf(liquidityProvider), balance1 - amount1);
        assertEq(hooks.balanceOf(liquidityProvider), balanceS + expectedShares);

        // Approval

        vm.prank(swapper);
        IERC20(token0).approve(permit2, type(uint256).max);

        vm.prank(swapper);
        IAllowanceTransfer(permit2).approve(token0, universalRouter, type(uint160).max, uint48(block.timestamp + 100));

        // Swap

        PoolKey memory poolKey = _getPoolKey(hooks);
        uint256 amount0In = 1 * 10 ** decimals0;

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

        uint256 swapperBalance0 = IERC20(token0).balanceOf(swapper);

        vm.prank(swapper);
        IUniversalRouter(universalRouter).execute(commands, inputs, block.timestamp + 100);

        assertEq(IERC20(token0).balanceOf(swapper), swapperBalance0 - amount0In);
        assertEq(IERC20(token1).balanceOf(swapper), 1000998991);
    }
}

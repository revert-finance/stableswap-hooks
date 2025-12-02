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
import {StableSwapHooks} from "src/StableSwapHooks.sol";

contract StableSwapHooksForkTest is Test {
    using SafeERC20 for IERC20;

    address private token0;
    address private token1;
    address private poolManager;
    address private positionManager;
    address private permit2;
    address private account0;

    uint256 private decimals0;
    uint256 private decimals1;
    uint256 private initialAmp;

    function setUp() public {
        token0 = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // dai
        token1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // usdt
        poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        account0 = makeAddr("account0");

        decimals0 = 18;
        decimals1 = 6;
        initialAmp = 1e3;

        vm.selectFork(vm.createFork(vm.envString("MAINNET_RPC_URL")));

        // Deal tokens to account0
        uint256 amount0 = 1000 * 10 ** decimals0;
        uint256 amount1 = 1000 * 10 ** decimals1;
        deal(token0, account0, amount0);
        deal(token1, account0, amount1);
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

    function test_AddLiquidity() public {
        StableSwapHooks hooks = _deployHook();

        _initializePool(hooks);

        uint256 amount0 = 100 * 10 ** decimals0;
        uint256 amount1 = 100 * 10 ** decimals1;

        uint256 balance0 = IERC20(token0).balanceOf(account0);
        uint256 balance1 = IERC20(token1).balanceOf(account0);

        vm.startPrank(account0);
        IERC20(token0).forceApprove(address(hooks), amount0);
        IERC20(token1).forceApprove(address(hooks), amount1);
        vm.expectEmit(address(hooks));
        emit StableSwapHooks.LiquidityAdded(account0, amount0, amount1, 200e18);
        hooks.addLiquidity(amount0, amount1, 0);
        vm.stopPrank();

        assertEq(IERC20(token0).balanceOf(account0), balance0 - amount0);
        assertEq(IERC20(token1).balanceOf(account0), balance1 - amount1);
    }

    function test_RemoveLiquidity() public {
        StableSwapHooks hooks = _deployHook();

        _initializePool(hooks);

        uint256 amount0 = 100 * 10 ** decimals0;
        uint256 amount1 = 100 * 10 ** decimals1;

        uint256 balance0 = IERC20(token0).balanceOf(account0);
        uint256 balance1 = IERC20(token1).balanceOf(account0);

        vm.startPrank(account0);
        IERC20(token0).forceApprove(address(hooks), amount0);
        IERC20(token1).forceApprove(address(hooks), amount1);
        hooks.addLiquidity(amount0, amount1, 0);
        vm.stopPrank();

        vm.startPrank(account0);
        vm.expectEmit(address(hooks));
        emit StableSwapHooks.LiquidityRemoved(account0, amount0, amount1, 200e18);
        hooks.removeLiquidity(200e18, 0, 0);
        vm.stopPrank();

        assertEq(IERC20(token0).balanceOf(account0), balance0);
        assertEq(IERC20(token1).balanceOf(account0), balance1);
    }
}

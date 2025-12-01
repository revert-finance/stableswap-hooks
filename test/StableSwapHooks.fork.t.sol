// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";

contract StableSwapHooksForkTest is Test {
    function test_Foo() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));

        vm.selectFork(mainnetFork);

        uint256 initialAmp = 1e3;

        address poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        address token0 = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // dai
        address token1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // usdt
        uint256 decimals0 = 18;
        uint256 decimals1 = 6;

        // Hooks flags based on getHookPermissions()
        uint160 flags = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;

        // Mine a salt that produces an address with the correct hook flags
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(StableSwapHooks).creationCode,
            abi.encode(initialAmp, poolManager, token0, token1)
        );

        // Deploy hook using CREATE2 with the mined salt
        StableSwapHooks hooks = new StableSwapHooks{salt: salt}(
            initialAmp, IPoolManager(poolManager), Currency.wrap(token0), Currency.wrap(token1)
        );

        // Verify hook deployed to the expected address
        assertEq(address(hooks), hookAddress);

        // Verify variables have been initialized correctly
        assertEq(address(hooks.poolManager()), poolManager);
        assertEq(hooks.amp(), initialAmp);
        assertEq(hooks.rate0(), 10 ** (36 - decimals0)); // 1e18 for 18 decimals
        assertEq(hooks.rate1(), 10 ** (36 - decimals1)); // 1e30 for 6 decimals
        assertEq(
            PoolId.unwrap(hooks.poolId()),
            PoolId.unwrap(
                PoolKey({
                        currency0: Currency.wrap(token0),
                        currency1: Currency.wrap(token1),
                        fee: hooks.FEE(),
                        tickSpacing: hooks.TICK_SPACING(),
                        hooks: IHooks(address(hooks))
                    }).toId()
            )
        );

        address positionManager = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;

        // Initialize the pool via the position manager
        int24 tick = IPositionManager(positionManager)
            .initializePool(
                PoolKey({
                    currency0: Currency.wrap(token0),
                    currency1: Currency.wrap(token1),
                    fee: hooks.FEE(),
                    tickSpacing: hooks.TICK_SPACING(),
                    hooks: IHooks(address(hooks))
                }),
                uint160(Math.sqrt((10 ** decimals1 << 192) / 10 ** decimals0)) // sqrtPriceX96 for 1:1 value ratio
            );

        // Validate that the tick is not failure
        assertNotEq(tick, type(int24).max);
    }
}

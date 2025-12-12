// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Pool} from "@uniswap/v4-core/src/libraries/Pool.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

import {Base} from "src/Base.sol";

contract StableSwapHooksInitTest is StableSwapHooksBaseTest {
    function test_initialize_ShouldRevertWhenPoolAlreadyInitialized() public {
        PoolKey memory poolKey = _getPoolKey();

        vm.expectRevert(Pool.PoolAlreadyInitialized.selector);
        poolManager.initialize(poolKey, BASE_SQRT_PRICE_X96);
    }

    function test_initialize_ShouldRevertWhenAnotherPoolUsesHook() public {
        PoolKey memory poolKey = _getPoolKey();
        poolKey.fee = poolKey.fee + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hooks),
                IHooks.beforeInitialize.selector,
                abi.encodeWithSelector(Base.InvalidPoolId.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        poolManager.initialize(poolKey, BASE_SQRT_PRICE_X96);
    }

    function test_initialize_ShouldSetCorrectPoolId() public view {
        PoolKey memory poolKey = _getPoolKey();
        PoolId expectedPoolId = poolKey.toId();

        assertEq(PoolId.unwrap(hooks.poolId()), PoolId.unwrap(expectedPoolId));
    }
}

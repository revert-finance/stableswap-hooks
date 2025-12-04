// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {stdError} from "forge-std/Test.sol";
import {StableSwapHooksBaseTest} from "./StableSwapHooks.base.t.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";

/// @title StableSwapHooksTest
/// @notice Tests for core swap functionality
contract StableSwapHooksTest is StableSwapHooksBaseTest {
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    // TODO: Uncomment or refactor
    // function testFuzz_beforeSwap_ShouldReturnCorrectDelta(int128 amountSpecified) public {
    //     vm.assume(amountSpecified != type(int128).min);

    //     SwapParams memory params =
    //         SwapParams({zeroForOne: false, amountSpecified: amountSpecified, sqrtPriceLimitX96: 0});

    //     vm.prank(poolManager);
    //     (bytes4 selector, BeforeSwapDelta delta, uint24 lpFeeOverride) =
    //         hooks.beforeSwap(address(this), key, params, "");

    //     assertEq(selector, BaseHook.beforeSwap.selector);
    //     assertEq(lpFeeOverride, 0);

    //     int128 specified = delta.getSpecifiedDelta();
    //     int128 unspecified = delta.getUnspecifiedDelta();

    //     assertEq(specified, -amountSpecified);
    //     assertEq(unspecified, 0);
    // }

    // function test_beforeSwap_RevertWhenAmountSpecifiedGreaterThanInt128Max() public {
    //     SwapParams memory params =
    //         SwapParams({zeroForOne: false, amountSpecified: int256(type(int128).max) + 1, sqrtPriceLimitX96: 0});

    //     vm.prank(poolManager);
    //     vm.expectRevert(SafeCast.SafeCastOverflow.selector);
    //     hooks.beforeSwap(address(this), key, params, "");
    // }

    // function test_beforeSwap_RevertWhenAmountSpecifiedIsEqualToInt128Min() public {
    //     SwapParams memory params =
    //         SwapParams({zeroForOne: false, amountSpecified: int256(type(int128).min), sqrtPriceLimitX96: 0});

    //     vm.prank(poolManager);
    //     vm.expectRevert(stdError.arithmeticError);
    //     hooks.beforeSwap(address(this), key, params, "");
    // }

    // function test_beforeSwap_RevertWhenAmountSpecifiedIsLowerThanInt128Min() public {
    //     SwapParams memory params =
    //         SwapParams({zeroForOne: false, amountSpecified: int256(type(int128).min) - 1, sqrtPriceLimitX96: 0});

    //     vm.prank(poolManager);
    //     vm.expectRevert(SafeCast.SafeCastOverflow.selector);
    //     hooks.beforeSwap(address(this), key, params, "");
    // }
}

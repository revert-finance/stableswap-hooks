// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, stdError} from "forge-std/Test.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {StableSwapHooks} from "../src/StableSwapHooks.sol";

contract StableSwapHooksTest is Test {
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    StableSwapHooks private hooks;
    PoolKey private key;

    function setUp() public {
        hooks = new StableSwapHooks(1e3, Currency.wrap(address(0x1)), Currency.wrap(address(0x2)), 0);

        key = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 0,
            tickSpacing: 0,
            hooks: IHooks(address(hooks))
        });
    }

    function testFuzz_beforeSwap_ShouldReturnCorrectDelta(int128 amountSpecified) public {
        vm.assume(amountSpecified != type(int128).min);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: amountSpecified, sqrtPriceLimitX96: 0});

        (bytes4 selector, BeforeSwapDelta delta, uint24 lpFeeOverride) =
            hooks.beforeSwap(address(this), key, params, "");

        assertEq(selector, StableSwapHooks.beforeSwap.selector);
        assertEq(lpFeeOverride, 0);

        int128 specified = delta.getSpecifiedDelta();
        int128 unspecified = delta.getUnspecifiedDelta();

        assertEq(specified, -amountSpecified);
        assertEq(unspecified, 0);
    }

    function test_beforeSwap_RevertWhenAmountSpecifiedGreaterThanInt128Max() public {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false, amountSpecified: int256(type(int128).max) + 1, sqrtPriceLimitX96: 0
        });

        vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        hooks.beforeSwap(address(this), key, params, "");
    }

    function test_beforeSwap_RevertWhenAmountSpecifiedIsEqualToInt128Min() public {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false, amountSpecified: int256(type(int128).min), sqrtPriceLimitX96: 0
        });

        vm.expectRevert(stdError.arithmeticError);
        hooks.beforeSwap(address(this), key, params, "");
    }

    function test_beforeSwap_RevertWhenAmountSpecifiedIsLowerThanInt128Min() public {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false, amountSpecified: int256(type(int128).min) - 1, sqrtPriceLimitX96: 0
        });

        vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        hooks.beforeSwap(address(this), key, params, "");
    }
}

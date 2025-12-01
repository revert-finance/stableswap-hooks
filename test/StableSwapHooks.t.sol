// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, stdError} from "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";

// TODO: Move to mocks folder
contract MockERC20 {
    uint8 public decimals = 18;
}

contract StableSwapHooksTest is Test {
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    StableSwapHooks private hooks;
    PoolKey private key;
    address private poolManager;

    function setUp() public {
        MockERC20 mockToken0 = new MockERC20();
        MockERC20 mockToken1 = new MockERC20();

        poolManager = address(0x1);

        uint256 initialAmp = 1e3;

        uint160 flags = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;

        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(StableSwapHooks).creationCode,
            abi.encode(initialAmp, poolManager, address(mockToken0), address(mockToken1))
        );

        hooks = new StableSwapHooks{salt: salt}(
            initialAmp,
            IPoolManager(poolManager),
            Currency.wrap(address(mockToken0)),
            Currency.wrap(address(mockToken1))
        );

        key = PoolKey({
            currency0: Currency.wrap(address(mockToken0)),
            currency1: Currency.wrap(address(mockToken1)),
            fee: hooks.FEE(),
            tickSpacing: hooks.TICK_SPACING(),
            hooks: IHooks(address(hooks))
        });
    }

    function testFuzz_beforeSwap_ShouldReturnCorrectDelta(int128 amountSpecified) public {
        vm.assume(amountSpecified != type(int128).min);

        SwapParams memory params =
            SwapParams({zeroForOne: false, amountSpecified: amountSpecified, sqrtPriceLimitX96: 0});

        vm.prank(poolManager);
        (bytes4 selector, BeforeSwapDelta delta, uint24 lpFeeOverride) =
            hooks.beforeSwap(address(this), key, params, "");

        assertEq(selector, BaseHook.beforeSwap.selector);
        assertEq(lpFeeOverride, 0);

        int128 specified = delta.getSpecifiedDelta();
        int128 unspecified = delta.getUnspecifiedDelta();

        assertEq(specified, -amountSpecified);
        assertEq(unspecified, 0);
    }

    function test_beforeSwap_RevertWhenAmountSpecifiedGreaterThanInt128Max() public {
        SwapParams memory params =
            SwapParams({zeroForOne: false, amountSpecified: int256(type(int128).max) + 1, sqrtPriceLimitX96: 0});

        vm.prank(poolManager);
        vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        hooks.beforeSwap(address(this), key, params, "");
    }

    function test_beforeSwap_RevertWhenAmountSpecifiedIsEqualToInt128Min() public {
        SwapParams memory params =
            SwapParams({zeroForOne: false, amountSpecified: int256(type(int128).min), sqrtPriceLimitX96: 0});

        vm.prank(poolManager);
        vm.expectRevert(stdError.arithmeticError);
        hooks.beforeSwap(address(this), key, params, "");
    }

    function test_beforeSwap_RevertWhenAmountSpecifiedIsLowerThanInt128Min() public {
        SwapParams memory params =
            SwapParams({zeroForOne: false, amountSpecified: int256(type(int128).min) - 1, sqrtPriceLimitX96: 0});

        vm.prank(poolManager);
        vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        hooks.beforeSwap(address(this), key, params, "");
    }
}

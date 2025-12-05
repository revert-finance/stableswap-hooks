// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";

/// @title StableSwapHooksAmpTest
/// @notice Tests for amplification parameter management
contract StableSwapHooksAmpTest is StableSwapHooksBaseTest {
    function test_rampA_ShouldRampUpSuccessfully() public {
        uint256 futureA = 200;
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(amplificationAdmin);
        vm.expectEmit(true, true, true, true);
        emit StableSwapHooks.RampedA(100, futureA, block.timestamp, futureTime);
        hooks.rampA(futureA, futureTime);

        assertEq(hooks.initialA(), 100);
        assertEq(hooks.futureA(), futureA);
        assertEq(hooks.initialATime(), block.timestamp);
        assertEq(hooks.futureATime(), futureTime);
    }

    function test_rampA_ShouldRampDownSuccessfully() public {
        uint256 futureA = 50;
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(amplificationAdmin);
        vm.expectEmit(true, true, true, true);
        emit StableSwapHooks.RampedA(100, futureA, block.timestamp, futureTime);
        hooks.rampA(futureA, futureTime);

        assertEq(hooks.initialA(), 100);
        assertEq(hooks.futureA(), futureA);
    }

    function test_amp_ShouldInterpolateWhileRamping() public {
        uint256 futureA = 200;
        uint256 futureTime = block.timestamp + 2 days;

        vm.prank(amplificationAdmin);
        hooks.rampA(futureA, futureTime);

        // Fast forward halfway through ramping
        vm.warp(block.timestamp + 1 days);

        // Should be approximately halfway through the ramp from 100 up to 200
        uint256 currentAmp = hooks.A();
        assertApproxEqAbs(currentAmp, 150, 1);
    }

    function test_amp_ShouldReturnFutureAAfterRampingComplete() public {
        uint256 futureA = 200;
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(amplificationAdmin);
        hooks.rampA(futureA, futureTime);

        // Fast forward past ramping completion
        vm.warp(futureTime + 1);

        assertEq(hooks.A(), futureA);
    }

    function test_rampA_ShouldRevertWhenFutureAGreaterEqualThanMaxA() public {
        uint256 futureA = hooks.MAX_A();
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(amplificationAdmin);
        vm.expectRevert(StableSwapHooks.InvalidA.selector);
        hooks.rampA(futureA, futureTime);
    }

    function test_rampA_ShouldRevertWhenFutureTimeInPast() public {
        uint256 futureA = 200;
        uint256 futureTime = block.timestamp - 1;

        vm.prank(amplificationAdmin);
        vm.expectRevert(StableSwapHooks.InsufficientRampTime.selector);
        hooks.rampA(futureA, futureTime);
    }

    function test_stopRampA_ShouldStopRampingAtCurrentValue() public {
        uint256 futureA = 200;
        uint256 futureTime = block.timestamp + 2 days;

        vm.prank(amplificationAdmin);
        hooks.rampA(futureA, futureTime);

        // Fast forward halfway through ramping
        vm.warp(block.timestamp + 1 days);
        uint256 currentAmpBeforeStop = hooks.A();

        // Stop ramping
        vm.prank(amplificationAdmin);
        vm.expectEmit(true, true, true, true);
        emit StableSwapHooks.StoppedRampA(currentAmpBeforeStop, block.timestamp);
        hooks.stopRampA();

        // Verify amp is frozen at current value
        assertEq(hooks.A(), currentAmpBeforeStop);
        assertEq(hooks.initialA(), currentAmpBeforeStop);
        assertEq(hooks.futureA(), currentAmpBeforeStop);
        assertEq(hooks.initialATime(), block.timestamp);
        assertEq(hooks.futureATime(), block.timestamp);

        // Warp further and verify amp doesn't change
        vm.warp(block.timestamp + 1 days);
        assertEq(hooks.A(), currentAmpBeforeStop);
    }

    function test_rampA_ShouldRevertWhenInsufficientTimeSinceLastRamp() public {
        uint256 futureA = 200;
        uint256 futureTime = block.timestamp + 1 days;

        // First ramp
        vm.prank(amplificationAdmin);
        hooks.rampA(futureA, futureTime);

        vm.prank(amplificationAdmin);
        vm.expectRevert(StableSwapHooks.InsufficientTimeSinceLastAChange.selector);
        hooks.rampA(300, block.timestamp + 2 days);
    }

    function test_rampA_ShouldSucceedAfterMinRampTimePassed() public {
        uint256 futureA = 200;
        uint256 futureTime = block.timestamp + 1 days;

        // First ramp
        vm.prank(amplificationAdmin);
        hooks.rampA(futureA, futureTime);

        // Wait for MIN_RAMP_TIME
        vm.warp(block.timestamp + hooks.MIN_RAMP_TIME());

        // Should succeed now
        vm.prank(amplificationAdmin);
        hooks.rampA(300, block.timestamp + 2 days);

        assertEq(hooks.futureA(), 300);
    }

    function test_rampA_ShouldRevertWhenRampDurationTooShort() public {
        uint256 futureA = 200;
        uint256 futureTime = block.timestamp + 1 hours; // Less than MIN_RAMP_TIME

        vm.prank(amplificationAdmin);
        vm.expectRevert(StableSwapHooks.InsufficientRampTime.selector);
        hooks.rampA(futureA, futureTime);
    }

    function test_rampA_ShouldRevertWhenFutureAIsZero() public {
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(amplificationAdmin);
        vm.expectRevert(StableSwapHooks.InvalidA.selector);
        hooks.rampA(0, futureTime);
    }

    function test_rampA_ShouldRevertWhenRampingUpTooMuch() public {
        // Current A is 100, max allowed is 100 * 10 = 1000
        uint256 futureA = 1100; // 11x increase (too much)
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(amplificationAdmin);
        vm.expectRevert(StableSwapHooks.ExcessiveAmpChange.selector);
        hooks.rampA(futureA, futureTime);
    }

    function test_rampA_ShouldSucceedWhenRampingUpExactlyMaxChange() public {
        // Current A is 100; 10x increase to the max allowed of 1000
        uint256 futureA = 1000; // Exactly a 10x increase
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(amplificationAdmin);
        hooks.rampA(futureA, futureTime);

        assertEq(hooks.futureA(), futureA);
    }

    function test_rampA_ShouldRevertWhenRampingDownTooMuch() public {
        // Current A is 100, min allowed is 10 (10x decrease limit)
        uint256 futureA = 1; // More than a 10x decrease (too much)
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(amplificationAdmin);
        vm.expectRevert(StableSwapHooks.ExcessiveAmpChange.selector);
        hooks.rampA(futureA, futureTime);
    }

    function test_rampA_ShouldSucceedWhenRampingDownExactlyMaxChange() public {
        // Current A is 100, min allowed is 10 (10x decrease)
        uint256 futureA = 10; // Exactly a 10x decrease
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(amplificationAdmin);
        hooks.rampA(futureA, futureTime);

        assertEq(hooks.futureA(), futureA);
    }

    function test_rampA_ShouldRespectMaxChangeAfterPartialRA() public {
        // Start ramp from 100 up to 200
        vm.prank(amplificationAdmin);
        hooks.rampA(200, block.timestamp + 2 days);

        // Warp halfway (current A should be ~150)
        vm.warp(block.timestamp + 1 days);

        uint256 currentA = hooks.A();
        assertApproxEqAbs(currentA, 150, 1);

        // Wait for MIN_RAMP_TIME
        vm.warp(block.timestamp + hooks.MIN_RAMP_TIME());

        // Now max allowed change from ~150 is 150 * 10 = 1500 (up) or 150 / 10 = 15 (down)
        uint256 maxAllowedUp = currentA * hooks.MAX_A_CHANGE();

        // This should succeed
        vm.prank(amplificationAdmin);
        hooks.rampA(maxAllowedUp, block.timestamp + 2 days);

        assertEq(hooks.futureA(), maxAllowedUp);
    }

    function testFuzz_rampA_ShouldEnforceMaxChange(uint256 multiplier) public {
        // Bound multiplier to reasonable range (1 to 20x)
        multiplier = bound(multiplier, 1, 20);

        uint256 currentA = hooks.A();
        uint256 futureA = currentA * multiplier;

        // Ensure futureA doesn't exceed MAX_A
        if (futureA >= hooks.MAX_A()) {
            return;
        }

        uint256 futureTime = block.timestamp + 1 days;

        if (multiplier > hooks.MAX_A_CHANGE()) {
            vm.prank(amplificationAdmin);
            // Should revert if change is too large
            vm.expectRevert(StableSwapHooks.ExcessiveAmpChange.selector);
            hooks.rampA(futureA, futureTime);
        } else {
            vm.prank(amplificationAdmin);
            // Should succeed if within limits
            hooks.rampA(futureA, futureTime);
            assertEq(hooks.futureA(), futureA);
        }
    }

    function testFuzz_rampA_ShouldHandleValidAmpValues(uint256 futureA) public {
        vm.assume(futureA > 0 && futureA < hooks.MAX_A());

        uint256 currentA = hooks.A();

        // Ensure futureA is within MAX_A_CHANGE bounds
        if (futureA < currentA) {
            vm.assume(futureA * hooks.MAX_A_CHANGE() >= currentA);
        } else {
            vm.assume(futureA <= currentA * hooks.MAX_A_CHANGE());
        }

        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(amplificationAdmin);
        hooks.rampA(futureA, futureTime);

        assertEq(hooks.futureA(), futureA);
    }
}

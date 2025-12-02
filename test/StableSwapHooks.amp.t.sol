// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StableSwapHooksBaseTest} from "./StableSwapHooks.base.t.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";

/// @title StableSwapHooksAmpTest
/// @notice Tests for amplification parameter management
contract StableSwapHooksAmpTest is StableSwapHooksBaseTest {
    function test_rampA_ShouldRampUpSuccessfully() public {
        uint256 futureA = 2e3;
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(ampAdmin);
        vm.expectEmit(true, true, true, true);
        emit StableSwapHooks.RampedA(1e3, futureA, block.timestamp, futureTime);
        hooks.rampA(futureA, futureTime);

        assertEq(hooks.initialA(), 1e3);
        assertEq(hooks.futureA(), futureA);
        assertEq(hooks.initialATime(), block.timestamp);
        assertEq(hooks.futureATime(), futureTime);
    }

    function test_rampA_ShouldRampDownSuccessfully() public {
        uint256 futureA = 500;
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(ampAdmin);
        vm.expectEmit(true, true, true, true);
        emit StableSwapHooks.RampedA(1e3, futureA, block.timestamp, futureTime);
        hooks.rampA(futureA, futureTime);

        assertEq(hooks.initialA(), 1e3);
        assertEq(hooks.futureA(), futureA);
    }

    function test_amp_ShouldInterpolateWhileRamping() public {
        uint256 futureA = 2e3;
        uint256 futureTime = block.timestamp + 2 days;

        vm.prank(ampAdmin);
        hooks.rampA(futureA, futureTime);

        // Fast forward halfway through ramping
        vm.warp(block.timestamp + 1 days);

        // Should be approximately halfway between 1e3 and 2e3
        uint256 currentAmp = hooks.amp();
        assertApproxEqAbs(currentAmp, 1500, 1);
    }

    function test_amp_ShouldReturnFutureAAfterRampingComplete() public {
        uint256 futureA = 2e3;
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(ampAdmin);
        hooks.rampA(futureA, futureTime);

        // Fast forward past ramping completion
        vm.warp(futureTime + 1);

        assertEq(hooks.amp(), futureA);
    }

    function test_rampA_ShouldRevertWhenFutureAGreaterThanMaxAmp() public {
        uint256 futureA = hooks.MAX_AMP();
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(ampAdmin);
        vm.expectRevert(StableSwapHooks.InvalidAmp.selector);
        hooks.rampA(futureA, futureTime);
    }

    function test_rampA_ShouldRevertWhenFutureTimeInPast() public {
        uint256 futureA = 2e3;
        uint256 futureTime = block.timestamp - 1;

        vm.prank(ampAdmin);
        vm.expectRevert(StableSwapHooks.InsufficientRampTime.selector);
        hooks.rampA(futureA, futureTime);
    }

    function test_stopRampA_ShouldStopRampingAtCurrentValue() public {
        uint256 futureA = 2e3;
        uint256 futureTime = block.timestamp + 2 days;

        vm.prank(ampAdmin);
        hooks.rampA(futureA, futureTime);

        // Fast forward halfway through ramping
        vm.warp(block.timestamp + 1 days);
        uint256 currentAmpBeforeStop = hooks.amp();

        // Stop ramping
        vm.prank(ampAdmin);
        vm.expectEmit(true, true, true, true);
        emit StableSwapHooks.StoppedRampA(currentAmpBeforeStop, block.timestamp);
        hooks.stopRampA();

        // Verify amp is frozen at current value
        assertEq(hooks.amp(), currentAmpBeforeStop);
        assertEq(hooks.initialA(), currentAmpBeforeStop);
        assertEq(hooks.futureA(), currentAmpBeforeStop);
        assertEq(hooks.initialATime(), block.timestamp);
        assertEq(hooks.futureATime(), block.timestamp);

        // Warp further and verify amp doesn't change
        vm.warp(block.timestamp + 1 days);
        assertEq(hooks.amp(), currentAmpBeforeStop);
    }

    function test_rampA_ShouldRevertWhenInsufficientTimeSinceLastRamp() public {
        uint256 futureA = 2e3;
        uint256 futureTime = block.timestamp + 1 days;

        // First ramp
        vm.prank(ampAdmin);
        hooks.rampA(futureA, futureTime);

        vm.prank(ampAdmin);
        vm.expectRevert(StableSwapHooks.InsufficientRampTime.selector);
        hooks.rampA(3e3, block.timestamp + 2 days);
    }

    function test_rampA_ShouldSucceedAfterMinRampTimePassed() public {
        uint256 futureA = 2e3;
        uint256 futureTime = block.timestamp + 1 days;

        // First ramp
        vm.prank(ampAdmin);
        hooks.rampA(futureA, futureTime);

        // Wait for MIN_RAMP_TIME
        vm.warp(block.timestamp + hooks.MIN_RAMP_TIME());

        // Should succeed now
        vm.prank(ampAdmin);
        hooks.rampA(3e3, block.timestamp + 2 days);

        assertEq(hooks.futureA(), 3e3);
    }

    function test_rampA_ShouldRevertWhenRampDurationTooShort() public {
        uint256 futureA = 2e3;
        uint256 futureTime = block.timestamp + 1 hours; // Less than MIN_RAMP_TIME

        vm.prank(ampAdmin);
        vm.expectRevert(StableSwapHooks.InsufficientRampTime.selector);
        hooks.rampA(futureA, futureTime);
    }

    function test_rampA_ShouldRevertWhenFutureAIsZero() public {
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(ampAdmin);
        vm.expectRevert(StableSwapHooks.InvalidAmp.selector);
        hooks.rampA(0, futureTime);
    }

    function test_rampA_ShouldRevertWhenRampingUpTooMuch() public {
        // Current A is 1000, max allowed is 1000 * 10 = 10000
        uint256 futureA = 11000; // 11x increase (too much)
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(ampAdmin);
        vm.expectRevert(StableSwapHooks.ExcessiveAmpChange.selector);
        hooks.rampA(futureA, futureTime);
    }

    function test_rampA_ShouldSucceedWhenRampingUpExactlyMaxChange() public {
        // Current A is 1000, max allowed is 1000 * 10 = 10000
        uint256 futureA = 10000; // Exactly 10x increase
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(ampAdmin);
        hooks.rampA(futureA, futureTime);

        assertEq(hooks.futureA(), futureA);
    }

    function test_rampA_ShouldRevertWhenRampingDownTooMuch() public {
        // Current A is 1000, min allowed is 1000 / 10 = 100
        uint256 futureA = 99; // More than 10x decrease (too much)
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(ampAdmin);
        vm.expectRevert(StableSwapHooks.ExcessiveAmpChange.selector);
        hooks.rampA(futureA, futureTime);
    }

    function test_rampA_ShouldSucceedWhenRampingDownExactlyMaxChange() public {
        // Current A is 1000, min allowed is 1000 / 10 = 100
        uint256 futureA = 100; // Exactly 10x decrease
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(ampAdmin);
        hooks.rampA(futureA, futureTime);

        assertEq(hooks.futureA(), futureA);
    }

    function test_rampA_ShouldRespectMaxChangeAfterPartialRamp() public {
        // Start ramp from 1000 to 2000
        vm.prank(ampAdmin);
        hooks.rampA(2e3, block.timestamp + 2 days);

        // Warp halfway (current A should be ~1500)
        vm.warp(block.timestamp + 1 days);

        uint256 currentA = hooks.amp();
        assertApproxEqAbs(currentA, 1500, 1);

        // Wait for MIN_RAMP_TIME
        vm.warp(block.timestamp + hooks.MIN_RAMP_TIME());

        // Now max allowed change from ~1500 is 1500 * 10 = 15000 (up) or 1500 / 10 = 150 (down)
        uint256 maxAllowedUp = currentA * hooks.MAX_A_CHANGE();

        // This should succeed
        vm.prank(ampAdmin);
        hooks.rampA(maxAllowedUp, block.timestamp + 2 days);

        assertEq(hooks.futureA(), maxAllowedUp);
    }

    function testFuzz_rampA_ShouldEnforceMaxChange(uint256 multiplier) public {
        // Bound multiplier to reasonable range (1 to 20x)
        multiplier = bound(multiplier, 1, 20);

        uint256 currentA = hooks.amp();
        uint256 futureA = currentA * multiplier;

        // Ensure futureA doesn't exceed MAX_AMP
        if (futureA >= hooks.MAX_AMP()) {
            return;
        }

        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(ampAdmin);

        if (multiplier > hooks.MAX_A_CHANGE()) {
            // Should revert if change is too large
            vm.expectRevert(StableSwapHooks.ExcessiveAmpChange.selector);
            hooks.rampA(futureA, futureTime);
        } else {
            // Should succeed if within limits
            hooks.rampA(futureA, futureTime);
            assertEq(hooks.futureA(), futureA);
        }
    }

    function testFuzz_rampA_ShouldHandleValidAmpValues(uint256 futureA) public {
        vm.assume(futureA > 0 && futureA < hooks.MAX_AMP());

        uint256 currentA = hooks.amp();

        // Ensure futureA is within MAX_A_CHANGE bounds
        if (futureA < currentA) {
            vm.assume(futureA * hooks.MAX_A_CHANGE() >= currentA);
        } else {
            vm.assume(futureA <= currentA * hooks.MAX_A_CHANGE());
        }

        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(ampAdmin);
        hooks.rampA(futureA, futureTime);

        assertEq(hooks.futureA(), futureA);
    }
}

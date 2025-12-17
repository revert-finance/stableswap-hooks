// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

import {Amp} from "src/Amp.sol";
import {StableSwapMath} from "src/libraries/StableSwapMath.sol";

contract StableSwapHooksAmpTest is StableSwapHooksBaseTest {
    // ==========================================================================
    // Start Amp Ramp
    // ==========================================================================

    function test_startAmpRamp_ShouldRampUpSuccessfully() public {
        uint256 nextAmp = 200;
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        vm.expectEmit(address(hooks));
        emit Amp.AmpRampStarted(
            defaultAdmin, 100 * StableSwapMath.AMP_PRECISION, 200 * StableSwapMath.AMP_PRECISION, block.timestamp, nextAmpTime
        );

        vm.prank(defaultAdmin);
        hooks.startAmpRamp(nextAmp, nextAmpTime);

        assertEq(hooks.baseAmp(), 100 * StableSwapMath.AMP_PRECISION);
        assertEq(hooks.nextAmp(), 200 * StableSwapMath.AMP_PRECISION);
        assertEq(hooks.baseAmpTime(), block.timestamp);
        assertEq(hooks.nextAmpTime(), nextAmpTime);
    }

    function test_startAmpRamp_ShouldRampDownSuccessfully() public {
        uint256 nextAmp = 50;
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        vm.expectEmit(address(hooks));
        emit Amp.AmpRampStarted(
            defaultAdmin, 100 * StableSwapMath.AMP_PRECISION, 50 * StableSwapMath.AMP_PRECISION, block.timestamp, nextAmpTime
        );

        vm.prank(defaultAdmin);
        hooks.startAmpRamp(nextAmp, nextAmpTime);

        assertEq(hooks.baseAmp(), 100 * StableSwapMath.AMP_PRECISION);
        assertEq(hooks.nextAmp(), 50 * StableSwapMath.AMP_PRECISION);
    }

    function test_startAmpRamp_ShouldInterpolateWhileRamping() public {
        uint256 nextAmp = 200;
        uint256 nextAmpTime = block.timestamp + 2 days;

        vm.prank(defaultAdmin);
        hooks.startAmpRamp(nextAmp, nextAmpTime);

        // Fast forward halfway through ramping
        vm.warp(block.timestamp + 1 days);

        // Should be approximately halfway through the ramp from 100 up to 200 (in scaled values: 10000 to 20000)
        uint256 currentAmp = hooks.currentAmp();
        assertApproxEqAbs(currentAmp, 150 * StableSwapMath.AMP_PRECISION, StableSwapMath.AMP_PRECISION);
    }

    function test_startAmpRamp_ShouldReturnFutureAAfterRampingComplete() public {
        uint256 nextAmp = 200;
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        vm.prank(defaultAdmin);
        hooks.startAmpRamp(nextAmp, nextAmpTime);

        // Fast forward past ramping completion
        vm.warp(nextAmpTime + 1);

        assertEq(hooks.currentAmp(), 200 * StableSwapMath.AMP_PRECISION);
    }

    function test_startAmpRamp_ShouldRevertWhenFutureAGreaterEqualThanMaxA() public {
        uint256 nextAmp = hooks.MAX_AMP();
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        vm.prank(defaultAdmin);
        vm.expectRevert(Amp.InvalidAmp.selector);
        hooks.startAmpRamp(nextAmp, nextAmpTime);
    }

    function test_startAmpRamp_ShouldRevertWhenFutureTimeInPast() public {
        uint256 nextAmp = 200;
        uint256 nextAmpTime = block.timestamp - 1;

        vm.prank(defaultAdmin);
        vm.expectRevert(Amp.InsufficientRampTime.selector);
        hooks.startAmpRamp(nextAmp, nextAmpTime);
    }

    // ==========================================================================
    // Stop Amp Ramp
    // ==========================================================================

    function test_stopAmpRamp_ShouldStopRampingAtCurrentValue() public {
        uint256 nextAmp = 200;
        uint256 nextAmpTime = block.timestamp + 2 days;

        vm.prank(defaultAdmin);
        hooks.startAmpRamp(nextAmp, nextAmpTime);

        // Fast forward halfway through ramping
        vm.warp(block.timestamp + 1 days);
        uint256 currentAmpBeforeStop = hooks.currentAmp();

        // Stop ramping
        vm.prank(defaultAdmin);
        vm.expectEmit(address(hooks));
        emit Amp.AmpRampStopped(defaultAdmin, currentAmpBeforeStop, block.timestamp);
        hooks.stopAmpRamp();

        // Verify amp is frozen at current value
        assertEq(hooks.currentAmp(), currentAmpBeforeStop);
        assertEq(hooks.baseAmp(), currentAmpBeforeStop);
        assertEq(hooks.nextAmp(), currentAmpBeforeStop);
        assertEq(hooks.baseAmpTime(), block.timestamp);
        assertEq(hooks.nextAmpTime(), block.timestamp);

        // Warp further and verify amp doesn't change
        vm.warp(block.timestamp + 1 days);
        assertEq(hooks.currentAmp(), currentAmpBeforeStop);
    }

    // ==========================================================================
    // Validation
    // ==========================================================================

    function test_startAmpRamp_ShouldRevertWhenInsufficientTimeSinceLastRamp() public {
        uint256 nextAmp = 200;
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        // First ramp
        vm.prank(defaultAdmin);
        hooks.startAmpRamp(nextAmp, nextAmpTime);

        vm.prank(defaultAdmin);
        vm.expectRevert(Amp.InsufficientTimeSinceLastAmpChange.selector);
        hooks.startAmpRamp(300, block.timestamp + 2 days);
    }

    function test_startAmpRamp_ShouldSucceedAfterMinRampTimePassed() public {
        uint256 nextAmp = 200;
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        // First ramp
        vm.prank(defaultAdmin);
        hooks.startAmpRamp(nextAmp, nextAmpTime);

        // Wait for MIN_RAMP_TIME
        vm.warp(block.timestamp + hooks.MIN_AMP_RAMP_TIME() + 1);

        // Should succeed now
        vm.prank(defaultAdmin);
        hooks.startAmpRamp(300, block.timestamp + 2 days);

        assertEq(hooks.nextAmp(), 300 * StableSwapMath.AMP_PRECISION);
    }

    function test_startAmpRamp_ShouldRevertWhenRampDurationTooShort() public {
        uint256 nextAmp = 200;
        uint256 nextAmpTime = block.timestamp + 1 hours; // Less than MIN_RAMP_TIME

        vm.prank(defaultAdmin);
        vm.expectRevert(Amp.InsufficientRampTime.selector);
        hooks.startAmpRamp(nextAmp, nextAmpTime);
    }

    function test_startAmpRamp_ShouldRevertWhenFutureAIsZero() public {
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        vm.prank(defaultAdmin);
        vm.expectRevert(Amp.InvalidAmp.selector);
        hooks.startAmpRamp(0, nextAmpTime);
    }

    function test_startAmpRamp_ShouldRevertWhenRampingUpTooMuch() public {
        // Current A is 100, max allowed is 100 * 10 = 1000
        uint256 nextAmp = 1100; // 11x increase (too much)
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        vm.prank(defaultAdmin);
        vm.expectRevert(Amp.ExcessiveAmpChange.selector);
        hooks.startAmpRamp(nextAmp, nextAmpTime);
    }

    function test_startAmpRamp_ShouldSucceedWhenRampingUpExactlyMaxChange() public {
        // Current A is 100; 10x increase to the max allowed of 1000
        uint256 nextAmp = 1000; // Exactly a 10x increase
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        vm.prank(defaultAdmin);
        hooks.startAmpRamp(nextAmp, nextAmpTime);

        assertEq(hooks.nextAmp(), 1000 * StableSwapMath.AMP_PRECISION);
    }

    function test_startAmpRamp_ShouldRevertWhenRampingDownTooMuch() public {
        // Current A is 100, min allowed is 10 (10x decrease limit)
        uint256 nextAmp = 1; // More than a 10x decrease (too much)
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        vm.prank(defaultAdmin);
        vm.expectRevert(Amp.ExcessiveAmpChange.selector);
        hooks.startAmpRamp(nextAmp, nextAmpTime);
    }

    function test_startAmpRamp_ShouldSucceedWhenRampingDownExactlyMaxChange() public {
        // Current A is 100, min allowed is 10 (10x decrease)
        uint256 nextAmp = 10; // Exactly a 10x decrease
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        vm.prank(defaultAdmin);
        hooks.startAmpRamp(nextAmp, nextAmpTime);

        assertEq(hooks.nextAmp(), 10 * StableSwapMath.AMP_PRECISION);
    }

    function test_startAmpRamp_ShouldRespectMaxChangeAfterPartialRamp() public {
        // Start ramp from 100 up to 200
        vm.prank(defaultAdmin);
        hooks.startAmpRamp(200, block.timestamp + 2 days);

        // Warp halfway (current A should be ~150 scaled = 15000)
        vm.warp(block.timestamp + 1 days);

        uint256 currentA = hooks.currentAmp();
        assertApproxEqAbs(currentA, 150 * StableSwapMath.AMP_PRECISION, StableSwapMath.AMP_PRECISION);

        // Wait for MIN_RAMP_TIME
        vm.warp(block.timestamp + hooks.MIN_AMP_RAMP_TIME() + 1);

        // Now max allowed change from ~150 is 150 * 10 = 1500 (up) or 150 / 10 = 15 (down)
        // currentA is scaled, so divide by AMP_PRECISION to get unscaled value for startAmpRamp
        uint256 currentAUnscaled = currentA / StableSwapMath.AMP_PRECISION;
        uint256 maxAllowedUp = currentAUnscaled * hooks.MAX_AMP_MULTIPLIER();

        // This should succeed
        vm.prank(defaultAdmin);
        hooks.startAmpRamp(maxAllowedUp, block.timestamp + 2 days);

        assertEq(hooks.nextAmp(), maxAllowedUp * StableSwapMath.AMP_PRECISION);
    }

    // ==========================================================================
    // Access Control
    // ==========================================================================

    function test_startAmpRamp_ShouldRevertWhenCalledByUnauthorizedUser() public {
        uint256 nextAmp = 200;
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorizedUser, hooks.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(unauthorizedUser);
        hooks.startAmpRamp(nextAmp, nextAmpTime);
    }

    function test_stopAmpRamp_ShouldRevertWhenCalledByUnauthorizedUser() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorizedUser, hooks.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(unauthorizedUser);
        hooks.stopAmpRamp();
    }

    function test_startAmpRamp_ShouldSucceedWhenCalledByDefaultAdmin() public {
        uint256 nextAmp = 200;
        uint256 nextAmpTime = block.timestamp + 1 days + 1;

        vm.prank(defaultAdmin);
        hooks.startAmpRamp(nextAmp, nextAmpTime);

        assertEq(hooks.nextAmp(), 200 * StableSwapMath.AMP_PRECISION);
    }

    function test_stopAmpRamp_ShouldSucceedWhenCalledByDefaultAdmin() public {
        // First ramp
        vm.prank(defaultAdmin);
        hooks.startAmpRamp(200, block.timestamp + 1 days + 1);

        // Then stop
        vm.prank(defaultAdmin);
        hooks.stopAmpRamp();

        assertEq(hooks.baseAmp(), hooks.nextAmp());
    }
}

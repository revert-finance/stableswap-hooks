// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title StableSwapHooksAccessTest
/// @notice Tests for role-based access control
contract StableSwapHooksAccessTest is StableSwapHooksBaseTest {
    function test_rampA_ShouldRevertWhenCalledByUnauthorizedUser() public {
        uint256 futureA = 200;
        uint256 futureTime = block.timestamp + 1 days;

        bytes32 ampAdminRole = hooks.A_ADMIN_ROLE();

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorizedUser, ampAdminRole
            )
        );
        hooks.rampA(futureA, futureTime);
    }

    function test_stopRampA_ShouldRevertWhenCalledByUnauthorizedUser() public {
        bytes32 ampAdminRole = hooks.A_ADMIN_ROLE();

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorizedUser, ampAdminRole
            )
        );
        hooks.stopRampA();
    }

    function test_rampA_ShouldSucceedWhenCalledByAmpAdmin() public {
        uint256 futureA = 200;
        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(amplificationAdmin);
        hooks.rampA(futureA, futureTime);

        assertEq(hooks.futureA(), futureA);
    }

    function test_stopRampA_ShouldSucceedWhenCalledByAmpAdmin() public {
        // First ramp
        vm.prank(amplificationAdmin);
        hooks.rampA(200, block.timestamp + 1 days);

        // Then stop
        vm.prank(amplificationAdmin);
        hooks.stopRampA();

        assertEq(hooks.initialA(), hooks.futureA());
    }
}

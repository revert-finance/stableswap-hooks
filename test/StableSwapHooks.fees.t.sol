// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

import {Fees} from "src/Fees.sol";
import {Actions} from "src/libraries/Actions.sol";

contract StableSwapHooksFeesTest is StableSwapHooksBaseTest {
    function test_constructor_ShouldAssignVariablesCorrectly() public view {
        assertEq(hooks.protocolFeeCollector(), protocolFeeCollector);
        assertEq(hooks.protocolFeePercentage(), BASE_PROTOCOL_FEE_PERCENTAGE);
        assertEq(hooks.hookFeePercentage(), BASE_HOOK_FEE_PERCENTAGE);
        assertEq(hooks.lpFeePercentage(), BASE_LP_FEE_PERCENTAGE);
    }

    function test_setProtocolFeeCollector_ShouldSucceedWhenCalledByAdmin() public {
        address newCollector = makeAddr("newCollector");

        vm.prank(defaultAdmin);
        vm.expectEmit(address(hooks));
        emit Fees.ProtocolFeeCollectorSet(defaultAdmin, newCollector);
        hooks.setProtocolFeeCollector(newCollector);

        assertEq(hooks.protocolFeeCollector(), newCollector);
    }

    function test_setProtocolFeeCollector_ShouldRevertWhenCalledByUnauthorized() public {
        address newCollector = makeAddr("newCollector");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorizedUser, hooks.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(unauthorizedUser);
        hooks.setProtocolFeeCollector(newCollector);
    }

    function test_setProtocolFeePercentage_ShouldSucceedWhenCalledByAdmin() public {
        uint256 newPercentage = 500; // 0.05%

        vm.prank(defaultAdmin);
        vm.expectEmit(address(hooks));
        emit Fees.ProtocolFeePercentageSet(defaultAdmin, newPercentage);
        hooks.setProtocolFeePercentage(newPercentage);

        assertEq(hooks.protocolFeePercentage(), newPercentage);
    }

    function test_setProtocolFeePercentage_ShouldRevertWhenCalledByUnauthorized() public {
        uint256 newPercentage = 500;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorizedUser, hooks.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(unauthorizedUser);
        hooks.setProtocolFeePercentage(newPercentage);
    }

    function test_setProtocolFeePercentage_ShouldRevertWhenExceedingPrecision() public {
        uint256 invalidPercentage = hooks.FEE_PRECISION() + 1;

        vm.prank(defaultAdmin);
        vm.expectRevert(Fees.InvalidFeePercentage.selector);
        hooks.setProtocolFeePercentage(invalidPercentage);
    }

    function test_setProtocolFeePercentage_ShouldRevertWhenSumExceedsPrecision() public {
        // Current: protocol=100, hook=200, lp=300, sum=600
        // Try to set protocol to FEE_PRECISION (1000000), sum would be 1000500
        uint256 invalidPercentage = hooks.FEE_PRECISION();

        vm.prank(defaultAdmin);
        vm.expectRevert(Fees.InvalidFeePercentage.selector);
        hooks.setProtocolFeePercentage(invalidPercentage);
    }

    function test_setHookFeePercentage_ShouldSucceedWhenCalledByAdmin() public {
        uint256 newPercentage = 1000; // 0.1%

        vm.prank(defaultAdmin);
        vm.expectEmit(address(hooks));
        emit Fees.HookFeePercentageSet(defaultAdmin, newPercentage);
        hooks.setHookFeePercentage(newPercentage);

        assertEq(hooks.hookFeePercentage(), newPercentage);
    }

    function test_setHookFeePercentage_ShouldRevertWhenCalledByUnauthorized() public {
        uint256 newPercentage = 1000;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorizedUser, hooks.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(unauthorizedUser);
        hooks.setHookFeePercentage(newPercentage);
    }

    function test_setHookFeePercentage_ShouldRevertWhenExceedingPrecision() public {
        uint256 invalidPercentage = hooks.FEE_PRECISION() + 1;

        vm.prank(defaultAdmin);
        vm.expectRevert(Fees.InvalidFeePercentage.selector);
        hooks.setHookFeePercentage(invalidPercentage);
    }

    function test_setHookFeePercentage_ShouldRevertWhenSumExceedsPrecision() public {
        // Current: protocol=100, hook=200, lp=300, sum=600
        // Try to set hook to FEE_PRECISION (1000000), sum would be 1000400
        uint256 invalidPercentage = hooks.FEE_PRECISION();

        vm.prank(defaultAdmin);
        vm.expectRevert(Fees.InvalidFeePercentage.selector);
        hooks.setHookFeePercentage(invalidPercentage);
    }

    function test_setLpFeePercentage_ShouldSucceedWhenCalledByAdmin() public {
        uint256 newPercentage = 1500; // 0.15%

        vm.prank(defaultAdmin);
        vm.expectEmit(address(hooks));
        emit Fees.LpFeePercentageSet(defaultAdmin, newPercentage);
        hooks.setLpFeePercentage(newPercentage);

        assertEq(hooks.lpFeePercentage(), newPercentage);
    }

    function test_setLpFeePercentage_ShouldRevertWhenCalledByUnauthorized() public {
        uint256 newPercentage = 1500;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorizedUser, hooks.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(unauthorizedUser);
        hooks.setLpFeePercentage(newPercentage);
    }

    function test_setLpFeePercentage_ShouldRevertWhenExceedingPrecision() public {
        uint256 invalidPercentage = hooks.FEE_PRECISION() + 1;

        vm.prank(defaultAdmin);
        vm.expectRevert(Fees.InvalidFeePercentage.selector);
        hooks.setLpFeePercentage(invalidPercentage);
    }

    function test_setLpFeePercentage_ShouldRevertWhenSumExceedsPrecision() public {
        // Current: protocol=100, hook=200, lp=300, sum=600
        // Try to set lp to FEE_PRECISION (1000000), sum would be 1000300
        uint256 invalidPercentage = hooks.FEE_PRECISION();

        vm.prank(defaultAdmin);
        vm.expectRevert(Fees.InvalidFeePercentage.selector);
        hooks.setLpFeePercentage(invalidPercentage);
    }

    function test_withdrawProtocolFees_ShouldCallPoolManagerUnlock() public {
        // Prepare the expected data
        bytes memory expectedData = abi.encode(Actions.WITHDRAW_PROTOCOL_FEES); // Actions.WITHDRAW_PROTOCOL_FEES = 0

        // Mock the poolManager.unlock call to return empty bytes
        vm.mockCall(
            address(poolManager),
            abi.encodeWithSelector(poolManager.unlock.selector, expectedData),
            abi.encode(bytes(""))
        );

        // Expect the unlock to be called with the correct data
        vm.expectCall(address(poolManager), abi.encodeWithSelector(poolManager.unlock.selector, expectedData));

        hooks.withdrawProtocolFees();
    }

    function test_withdrawHookFees_ShouldCallPoolManagerUnlock() public {
        address beneficiary = makeAddr("beneficiary");

        // Prepare the expected data
        bytes memory expectedData = abi.encode(Actions.WITHDRAW_HOOK_FEES, beneficiary);

        // Mock the poolManager.unlock call to return empty bytes
        vm.mockCall(
            address(poolManager),
            abi.encodeWithSelector(poolManager.unlock.selector, expectedData),
            abi.encode(bytes(""))
        );

        // Expect the unlock to be called with the correct data
        vm.expectCall(address(poolManager), abi.encodeWithSelector(poolManager.unlock.selector, expectedData));

        vm.prank(defaultAdmin);
        hooks.withdrawHookFees(beneficiary);
    }

    function test_withdrawHookFees_ShouldRevertWhenCalledByUnauthorized() public {
        address beneficiary = makeAddr("beneficiary");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorizedUser, hooks.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(unauthorizedUser);
        hooks.withdrawHookFees(beneficiary);
    }

    function test_handleWithdrawProtocolFeesCallback_ShouldResetFeesAndEmitEvent() public {
        // First, add some protocol fees
        uint256 protocolFee0 = 100e18;
        uint256 protocolFee1 = 200e18;

        hooks.addFees(true, protocolFee0, 0);
        hooks.addFees(false, protocolFee1, 0);

        // Mock the poolManager calls
        vm.mockCall(address(poolManager), abi.encodeWithSelector(poolManager.burn.selector), abi.encode());
        vm.mockCall(address(poolManager), abi.encodeWithSelector(poolManager.take.selector), abi.encode());

        // Expect burn to be called for currency0
        vm.expectCall(
            address(poolManager),
            abi.encodeWithSelector(poolManager.burn.selector, address(hooks), currency0.toId(), protocolFee0)
        );

        // Expect take to be called for currency0
        vm.expectCall(
            address(poolManager),
            abi.encodeWithSelector(poolManager.take.selector, currency0, protocolFeeCollector, protocolFee0)
        );

        // Expect burn to be called for currency1
        vm.expectCall(
            address(poolManager),
            abi.encodeWithSelector(poolManager.burn.selector, address(hooks), currency1.toId(), protocolFee1)
        );

        // Expect take to be called for currency1
        vm.expectCall(
            address(poolManager),
            abi.encodeWithSelector(poolManager.take.selector, currency1, protocolFeeCollector, protocolFee1)
        );

        // Expect the event to be emitted
        vm.expectEmit(address(hooks));
        emit Fees.ProtocolFeesWithdrawn(address(this), protocolFeeCollector, protocolFee0, protocolFee1);

        // Call the callback
        hooks.handleWithdrawProtocolFeesCallback();

        // Verify fees are reset to 0
        assertEq(hooks.protocolFees0(), 0);
        assertEq(hooks.protocolFees1(), 0);
    }

    function test_handleWithdrawProtocolFeesCallback_ShouldHandleZeroFees() public {
        // Verify no fees accumulated
        assertEq(hooks.protocolFees0(), 0);
        assertEq(hooks.protocolFees1(), 0);

        // Expect poolManager.burn and take to NOT be called (count = 0)
        vm.expectCall(
            address(poolManager),
            abi.encodeWithSelector(poolManager.burn.selector),
            0 // count = 0 means we expect it NOT to be called
        );
        vm.expectCall(
            address(poolManager),
            abi.encodeWithSelector(poolManager.take.selector),
            0 // count = 0 means we expect it NOT to be called
        );

        // Expect the event to be emitted with zero amounts
        vm.expectEmit(address(hooks));
        emit Fees.ProtocolFeesWithdrawn(address(this), protocolFeeCollector, 0, 0);

        // Call the callback
        hooks.handleWithdrawProtocolFeesCallback();

        // Verify fees remain 0
        assertEq(hooks.protocolFees0(), 0);
        assertEq(hooks.protocolFees1(), 0);
    }

    function test_handleWithdrawHookFeesCallback_ShouldResetFeesAndEmitEvent() public {
        // First, add some hook fees
        uint256 hookFee0 = 100e18;
        uint256 hookFee1 = 200e18;

        hooks.addFees(true, 0, hookFee0);
        hooks.addFees(false, 0, hookFee1);

        address beneficiary = makeAddr("beneficiary");

        // Mock the poolManager calls
        vm.mockCall(address(poolManager), abi.encodeWithSelector(poolManager.burn.selector), abi.encode());
        vm.mockCall(address(poolManager), abi.encodeWithSelector(poolManager.take.selector), abi.encode());

        // Expect burn to be called for currency0
        vm.expectCall(
            address(poolManager),
            abi.encodeWithSelector(poolManager.burn.selector, address(hooks), currency0.toId(), hookFee0)
        );

        // Expect take to be called for currency0
        vm.expectCall(
            address(poolManager), abi.encodeWithSelector(poolManager.take.selector, currency0, beneficiary, hookFee0)
        );

        // Expect burn to be called for currency1
        vm.expectCall(
            address(poolManager),
            abi.encodeWithSelector(poolManager.burn.selector, address(hooks), currency1.toId(), hookFee1)
        );

        // Expect take to be called for currency1
        vm.expectCall(
            address(poolManager), abi.encodeWithSelector(poolManager.take.selector, currency1, beneficiary, hookFee1)
        );

        // Expect the event to be emitted
        vm.expectEmit(address(hooks));
        emit Fees.HookFeesWithdrawn(address(this), beneficiary, hookFee0, hookFee1);

        // Call the callback
        bytes memory data = abi.encode(Actions.WITHDRAW_HOOK_FEES, beneficiary);
        hooks.handleWithdrawHookFeesCallback(data);

        // Verify fees are reset to 0
        assertEq(hooks.hookFees0(), 0);
        assertEq(hooks.hookFees1(), 0);
    }

    function test_handleWithdrawHookFeesCallback_ShouldHandleZeroFees() public {
        // Verify no fees accumulated
        assertEq(hooks.hookFees0(), 0);
        assertEq(hooks.hookFees1(), 0);

        address beneficiary = makeAddr("beneficiary");

        // Expect poolManager.burn and take to NOT be called (count = 0)
        vm.expectCall(
            address(poolManager),
            abi.encodeWithSelector(poolManager.burn.selector),
            0 // count = 0 means we expect it NOT to be called
        );
        vm.expectCall(
            address(poolManager),
            abi.encodeWithSelector(poolManager.take.selector),
            0 // count = 0 means we expect it NOT to be called
        );

        // Expect the event to be emitted with zero amounts
        vm.expectEmit(address(hooks));
        emit Fees.HookFeesWithdrawn(address(this), beneficiary, 0, 0);

        // Call the callback
        bytes memory data = abi.encode(Actions.WITHDRAW_HOOK_FEES, beneficiary);
        hooks.handleWithdrawHookFeesCallback(data);

        // Verify fees remain 0
        assertEq(hooks.hookFees0(), 0);
        assertEq(hooks.hookFees1(), 0);
    }

    function test_handleWithdrawHookFeesCallback_ShouldRevertWhenBeneficiaryIsZeroAddress() public {
        // Add some hook fees
        uint256 hookFee0 = 100e18;
        uint256 hookFee1 = 200e18;

        hooks.addFees(true, 0, hookFee0);
        hooks.addFees(false, 0, hookFee1);

        address beneficiary = address(0);

        // Expect the InvalidAddress error
        vm.expectRevert(Fees.InvalidAddress.selector);

        // Call the callback with zero address beneficiary
        bytes memory data = abi.encode(Actions.WITHDRAW_HOOK_FEES, beneficiary);
        hooks.handleWithdrawHookFeesCallback(data);
    }

    function test_getFees_ShouldCalculateFeesCorrectly() public {
        uint256 precision = hooks.FEE_PRECISION();
        uint256 amount = 1000e18;

        // Set custom fee percentages
        uint256 protocolFeePercentage = 1000; // 0.1%
        uint256 hookFeePercentage = 2000; // 0.2%
        uint256 lpFeePercentage = 3000; // 0.3%

        vm.startPrank(defaultAdmin);
        hooks.setProtocolFeePercentage(protocolFeePercentage);
        hooks.setHookFeePercentage(hookFeePercentage);
        hooks.setLpFeePercentage(lpFeePercentage);
        vm.stopPrank();

        (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = hooks.getFees(amount);

        assertEq(lpFees, amount * lpFeePercentage / precision);
        assertEq(hookFees, amount * hookFeePercentage / precision);
        assertEq(protocolFees, amount * protocolFeePercentage / precision);
    }

    function test_addFees_IncrementsOnlyCurrency0() public {
        uint256 p = 111e18;
        uint256 h = 222e18;

        assertEq(hooks.protocolFees0(), 0);
        assertEq(hooks.hookFees0(), 0);
        assertEq(hooks.protocolFees1(), 0);
        assertEq(hooks.hookFees1(), 0);

        hooks.addFees(true, p, h);

        assertEq(hooks.protocolFees0(), p);
        assertEq(hooks.hookFees0(), h);

        assertEq(hooks.protocolFees1(), 0);
        assertEq(hooks.hookFees1(), 0);
    }

    function test_addFees_IncrementsOnlyCurrency1() public {
        uint256 p = 333e18;
        uint256 h = 444e18;

        assertEq(hooks.protocolFees0(), 0);
        assertEq(hooks.hookFees0(), 0);
        assertEq(hooks.protocolFees1(), 0);
        assertEq(hooks.hookFees1(), 0);

        hooks.addFees(false, p, h);

        assertEq(hooks.protocolFees0(), 0);
        assertEq(hooks.hookFees0(), 0);

        assertEq(hooks.protocolFees1(), p);
        assertEq(hooks.hookFees1(), h);
    }
}

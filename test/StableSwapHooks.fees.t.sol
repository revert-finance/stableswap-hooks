// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

import {Fees} from "src/Fees.sol";
import {Actions} from "src/libraries/Actions.sol";

contract StableSwapHooksFeesTest is StableSwapHooksBaseTest {
    uint256 private constant LIQUIDITY_AMOUNT = 1e6;
    uint256 private constant SWAP_AMOUNT = 1000;

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

    function test_withdrawProtocolFees_ShouldTransferFeesAndEmitEvent() public {
        // Add liquidity and perform a swap to accumulate fees
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));

        uint256 protocolFees1 = hooks.protocolFees1();
        assertGt(protocolFees1, 0);

        uint256 collectorBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(protocolFeeCollector);

        // The sender in the event is the original caller of withdrawProtocolFees
        vm.expectEmit(address(hooks));
        emit Fees.ProtocolFeesWithdrawn(address(this), protocolFeeCollector, 0, protocolFees1);

        hooks.withdrawProtocolFees();

        uint256 collectorBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(protocolFeeCollector);

        assertEq(hooks.protocolFees0(), 0);
        assertEq(hooks.protocolFees1(), 0);
        assertEq(collectorBalance1After - collectorBalance1Before, protocolFees1);
    }

    function test_withdrawProtocolFees_ShouldHandleZeroFees() public {
        assertEq(hooks.protocolFees0(), 0);
        assertEq(hooks.protocolFees1(), 0);

        // The sender in the event is the original caller of withdrawProtocolFees
        vm.expectEmit(address(hooks));
        emit Fees.ProtocolFeesWithdrawn(address(this), protocolFeeCollector, 0, 0);

        hooks.withdrawProtocolFees();

        assertEq(hooks.protocolFees0(), 0);
        assertEq(hooks.protocolFees1(), 0);
    }

    function test_withdrawHookFees_ShouldTransferFeesAndEmitEvent() public {
        // Add liquidity and perform a swap to accumulate fees
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));

        uint256 hookFees1 = hooks.hookFees1();
        assertGt(hookFees1, 0);

        address beneficiary = makeAddr("beneficiary");
        uint256 beneficiaryBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(beneficiary);

        // The sender in the event is the original caller of withdrawHookFees
        vm.expectEmit(address(hooks));
        emit Fees.HookFeesWithdrawn(defaultAdmin, beneficiary, 0, hookFees1);

        vm.prank(defaultAdmin);
        hooks.withdrawHookFees(beneficiary);

        uint256 beneficiaryBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(beneficiary);

        assertEq(hooks.hookFees0(), 0);
        assertEq(hooks.hookFees1(), 0);
        assertEq(beneficiaryBalance1After - beneficiaryBalance1Before, hookFees1);
    }

    function test_withdrawHookFees_ShouldHandleZeroFees() public {
        assertEq(hooks.hookFees0(), 0);
        assertEq(hooks.hookFees1(), 0);

        address beneficiary = makeAddr("beneficiary");

        // The sender in the event is the original caller of withdrawHookFees
        vm.expectEmit(address(hooks));
        emit Fees.HookFeesWithdrawn(defaultAdmin, beneficiary, 0, 0);

        vm.prank(defaultAdmin);
        hooks.withdrawHookFees(beneficiary);

        assertEq(hooks.hookFees0(), 0);
        assertEq(hooks.hookFees1(), 0);
    }

    function test_withdrawHookFees_ShouldRevertWhenBeneficiaryIsZeroAddress() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));

        vm.expectRevert(Fees.InvalidAddress.selector);
        vm.prank(defaultAdmin);
        hooks.withdrawHookFees(address(0));
    }

    function test_getFees_ShouldCalculateFeesCorrectly() public {
        uint256 amount = 1000e18;

        // Set custom fee percentages: 0.1%, 0.2%, 0.3%
        vm.startPrank(defaultAdmin);
        hooks.setProtocolFeePercentage(1000);
        hooks.setHookFeePercentage(2000);
        hooks.setLpFeePercentage(3000);
        vm.stopPrank();

        (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = hooks.getFees(amount);

        assertEq(lpFees, 3e18);
        assertEq(hookFees, 2e18);
        assertEq(protocolFees, 1e18);
    }

    function test_swaps_ShouldAccumulateFees() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        assertEq(hooks.protocolFees0(), 0);
        assertEq(hooks.protocolFees1(), 0);
        assertEq(hooks.hookFees0(), 0);
        assertEq(hooks.hookFees1(), 0);

        // Exact input swap zeroForOne accumulates fees on currency1
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));

        assertEq(hooks.protocolFees0(), 0);
        assertGt(hooks.protocolFees1(), 0);
        assertEq(hooks.hookFees0(), 0);
        assertGt(hooks.hookFees1(), 0);
    }
}

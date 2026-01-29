// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

import {Base} from "src/Base.sol";
import {Fees} from "src/Fees.sol";
import {Swap} from "src/Swap.sol";

contract StableSwapHooksFeesTest is StableSwapHooksBaseTest {
    uint256 private constant LIQUIDITY_AMOUNT = 1_000_000;
    uint256 private constant SWAP_AMOUNT = 1_000;

    struct StableSwapEventData {
        uint256 lpFees;
        uint256 hookFees;
        uint256 protocolFees;
    }

    function _findStableSwapEvent(Vm.Log[] memory _logs) private pure returns (StableSwapEventData memory data) {
        for (uint256 i = 0; i < _logs.length; i++) {
            if (_logs[i].topics[0] == Swap.StableSwap.selector) {
                (,, data.lpFees, data.hookFees, data.protocolFees) =
                    abi.decode(_logs[i].data, (uint256, uint256, uint256, uint256, uint256));
                return data;
            }
        }
        revert("StableSwap event not found");
    }

    // ==========================================================================
    // Fee Percentage Setters
    // ==========================================================================

    function test_setProtocolFeePercentage_ShouldSucceedWhenCalledByFactoryOwner() public {
        uint256 newPercentage = 500;

        vm.prank(defaultAdmin);
        vm.expectEmit(address(hooks));
        emit Fees.ProtocolFeePercentageSet(defaultAdmin, newPercentage);
        hooks.setProtocolFeePercentage(newPercentage);

        assertEq(hooks.protocolFeePercentage(), newPercentage);
    }

    function test_setProtocolFeePercentage_ShouldRevertWhenCalledByNonFactoryOwner() public {
        vm.expectRevert(Base.OnlyFactoryOwner.selector);
        vm.prank(unauthorizedUser);
        hooks.setProtocolFeePercentage(500);
    }

    function test_setProtocolFeePercentage_ShouldRevertWhenFeesSumExceedsPrecision() public {
        uint256 invalidPercentage = hooks.FEE_PRECISION();

        vm.expectRevert(Fees.InvalidFeePercentage.selector);
        vm.prank(defaultAdmin);
        hooks.setProtocolFeePercentage(invalidPercentage);
    }

    function test_setHookFeePercentage_ShouldSucceedWhenCalledByFactoryOwner() public {
        uint256 newPercentage = 500;

        vm.prank(defaultAdmin);
        vm.expectEmit(address(hooks));
        emit Fees.HookFeePercentageSet(defaultAdmin, newPercentage);
        hooks.setHookFeePercentage(newPercentage);

        assertEq(hooks.hookFeePercentage(), newPercentage);
    }

    function test_setHookFeePercentage_ShouldRevertWhenCalledByNonFactoryOwner() public {
        vm.expectRevert(Base.OnlyFactoryOwner.selector);
        vm.prank(unauthorizedUser);
        hooks.setHookFeePercentage(500);
    }

    function test_setHookFeePercentage_ShouldRevertWhenFeesSumExceedsPrecision() public {
        uint256 invalidPercentage = hooks.FEE_PRECISION();

        vm.expectRevert(Fees.InvalidFeePercentage.selector);
        vm.prank(defaultAdmin);
        hooks.setHookFeePercentage(invalidPercentage);
    }

    function test_setFeePercentages_ShouldAllowHookPlusProtocolEqualToPrecision() public {
        uint256 feePrecision = hooks.FEE_PRECISION();

        vm.startPrank(defaultAdmin);
        hooks.setHookFeePercentage(feePrecision / 2);
        hooks.setProtocolFeePercentage(feePrecision / 2);
        vm.stopPrank();

        assertEq(hooks.hookFeePercentage(), feePrecision / 2);
        assertEq(hooks.protocolFeePercentage(), feePrecision / 2);
    }

    // ==========================================================================
    // Fee Withdrawal - Protocol Fees
    // ==========================================================================

    function test_withdrawProtocolFees_ShouldTransferFeesAndEmitEvent() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));

        uint256 protocolFees1 = hooks.protocolFees(1);
        assertGt(protocolFees1, 0);

        uint256 collectorBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(protocolFeeCollector);

        uint256[] memory expectedFees = new uint256[](2);
        expectedFees[0] = 0;
        expectedFees[1] = protocolFees1;

        vm.expectEmit(address(hooks));
        emit Fees.ProtocolFeesWithdrawn(address(this), protocolFeeCollector, expectedFees);

        hooks.withdrawProtocolFees();

        uint256 collectorBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(protocolFeeCollector);

        assertEq(hooks.protocolFees(0), 0);
        assertEq(hooks.protocolFees(1), 0);
        assertEq(collectorBalance1After - collectorBalance1Before, protocolFees1);
    }

    function test_withdrawProtocolFees_ShouldHandleZeroFees() public {
        assertEq(hooks.protocolFees(0), 0);
        assertEq(hooks.protocolFees(1), 0);

        uint256[] memory expectedFees = new uint256[](2);

        vm.expectEmit(address(hooks));
        emit Fees.ProtocolFeesWithdrawn(address(this), protocolFeeCollector, expectedFees);

        hooks.withdrawProtocolFees();

        assertEq(hooks.protocolFees(0), 0);
        assertEq(hooks.protocolFees(1), 0);
    }

    function test_withdrawProtocolFees_ShouldBeCallableByAnyone() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));

        uint256 protocolFees1 = hooks.protocolFees(1);
        assertGt(protocolFees1, 0);

        uint256 collectorBalanceBefore = IERC20(Currency.unwrap(currency1)).balanceOf(protocolFeeCollector);

        vm.prank(unauthorizedUser);
        hooks.withdrawProtocolFees();

        uint256 collectorBalanceAfter = IERC20(Currency.unwrap(currency1)).balanceOf(protocolFeeCollector);

        assertEq(hooks.protocolFees(1), 0);
        assertEq(collectorBalanceAfter - collectorBalanceBefore, protocolFees1);
    }

    // ==========================================================================
    // Fee Withdrawal - Hook Fees
    // ==========================================================================

    function test_withdrawHookFees_ShouldTransferFeesAndEmitEvent() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));

        uint256 hookFees1 = hooks.hookFees(1);
        assertGt(hookFees1, 0);

        uint256 hookFeeCollectorBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(hookFeeCollector);

        uint256[] memory expectedFees = new uint256[](2);
        expectedFees[0] = 0;
        expectedFees[1] = hookFees1;

        vm.expectEmit(address(hooks));
        emit Fees.HookFeesWithdrawn(address(this), hookFeeCollector, expectedFees);

        hooks.withdrawHookFees();

        uint256 hookFeeCollectorBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(hookFeeCollector);

        assertEq(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);
        assertEq(hookFeeCollectorBalance1After - hookFeeCollectorBalance1Before, hookFees1);
    }

    function test_withdrawHookFees_ShouldHandleZeroFees() public {
        assertEq(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);

        uint256[] memory expectedFees = new uint256[](2);

        vm.expectEmit(address(hooks));
        emit Fees.HookFeesWithdrawn(address(this), hookFeeCollector, expectedFees);

        hooks.withdrawHookFees();

        assertEq(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);
    }

    function test_withdrawHookFees_ShouldBeCallableByAnyone() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));

        uint256 hookFees1 = hooks.hookFees(1);
        assertGt(hookFees1, 0);

        uint256 collectorBalanceBefore = IERC20(Currency.unwrap(currency1)).balanceOf(hookFeeCollector);

        vm.prank(unauthorizedUser);
        hooks.withdrawHookFees();

        uint256 collectorBalanceAfter = IERC20(Currency.unwrap(currency1)).balanceOf(hookFeeCollector);

        assertEq(hooks.hookFees(1), 0);
        assertEq(collectorBalanceAfter - collectorBalanceBefore, hookFees1);
    }

    // ==========================================================================
    // Fee Accumulation
    // ==========================================================================

    function test_swaps_ShouldAccumulateFeesOnZeroForOne() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        assertEq(hooks.protocolFees(0), 0);
        assertEq(hooks.protocolFees(1), 0);
        assertEq(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);

        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));

        assertEq(hooks.protocolFees(0), 0);
        assertGt(hooks.protocolFees(1), 0);
        assertEq(hooks.hookFees(0), 0);
        assertGt(hooks.hookFees(1), 0);
    }

    function test_swaps_ShouldAccumulateFeesOnOneForZero() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        assertEq(hooks.protocolFees(0), 0);
        assertEq(hooks.protocolFees(1), 0);
        assertEq(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);

        _executeExactInputSwap(false, _toTokenWei(currency1, SWAP_AMOUNT));

        assertGt(hooks.protocolFees(0), 0);
        assertEq(hooks.protocolFees(1), 0);
        assertGt(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);
    }

    function test_swaps_ShouldAccumulateFeesOnExactOutput() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        assertEq(hooks.protocolFees(0), 0);
        assertEq(hooks.protocolFees(1), 0);
        assertEq(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);

        _executeExactOutputSwap(true, _toTokenWei(currency1, SWAP_AMOUNT));

        assertGt(hooks.protocolFees(0), 0);
        assertEq(hooks.protocolFees(1), 0);
        assertGt(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);
    }

    // ==========================================================================
    // Fee Calculation
    // ==========================================================================

    function test_feeCalculation_ShouldCalculateHookAndProtocolFeesAsPercentageOfGrossLpFees() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        vm.recordLogs();
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        StableSwapEventData memory eventData = _findStableSwapEvent(logs);

        uint256 grossLpFees = eventData.lpFees + eventData.hookFees + eventData.protocolFees;
        uint256 feePrecision = hooks.FEE_PRECISION();

        uint256 expectedHookFees = grossLpFees * BASE_HOOK_FEE_PERCENTAGE / feePrecision;
        uint256 expectedProtocolFees = grossLpFees * BASE_PROTOCOL_FEE_PERCENTAGE / feePrecision;
        uint256 expectedNetLpFees = grossLpFees - expectedHookFees - expectedProtocolFees;

        assertEq(eventData.hookFees, expectedHookFees);
        assertEq(eventData.protocolFees, expectedProtocolFees);
        assertEq(eventData.lpFees, expectedNetLpFees);
    }

    function test_feeCalculation_ShouldGiveAllFeesToLpsWhenHookAndProtocolAreZero() public {
        vm.startPrank(defaultAdmin);
        hooks.setHookFeePercentage(0);
        hooks.setProtocolFeePercentage(0);
        vm.stopPrank();

        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        vm.recordLogs();
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        StableSwapEventData memory eventData = _findStableSwapEvent(logs);

        uint256 grossLpFees = eventData.lpFees + eventData.hookFees + eventData.protocolFees;
        assertEq(eventData.lpFees, grossLpFees);
        assertEq(eventData.hookFees, 0);
        assertEq(eventData.protocolFees, 0);
    }

    function test_feeCalculation_ShouldGiveZeroToLpsWhenHookAndProtocolTakeAll() public {
        uint256 feePrecision = hooks.FEE_PRECISION();

        vm.startPrank(defaultAdmin);
        hooks.setHookFeePercentage(feePrecision / 2);
        hooks.setProtocolFeePercentage(feePrecision / 2);
        vm.stopPrank();

        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        vm.recordLogs();
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        StableSwapEventData memory eventData = _findStableSwapEvent(logs);

        uint256 grossLpFees = eventData.lpFees + eventData.hookFees + eventData.protocolFees;
        uint256 expectedHookFees = grossLpFees / 2;
        uint256 expectedProtocolFees = grossLpFees / 2;

        assertEq(eventData.lpFees, 0);
        assertEq(eventData.hookFees, expectedHookFees);
        assertEq(eventData.protocolFees, expectedProtocolFees);
    }

    // ==========================================================================
    // Multi-Currency (hooks3)
    // ==========================================================================

    function test_hooks3_ShouldAccumulateFeesOnAllCurrencies() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        assertEq(hooks3.protocolFees(0), 0);
        assertEq(hooks3.protocolFees(1), 0);
        assertEq(hooks3.protocolFees(2), 0);

        _executeExactInputSwap3(currency0, currency1, _toTokenWei(currency0, SWAP_AMOUNT));
        assertEq(hooks3.protocolFees(0), 0);
        assertGt(hooks3.protocolFees(1), 0);
        assertEq(hooks3.protocolFees(2), 0);

        uint256 fees1After01Swap = hooks3.protocolFees(1);

        _executeExactInputSwap3(currency0, currency2, _toTokenWei(currency0, SWAP_AMOUNT));
        assertEq(hooks3.protocolFees(0), 0);
        assertEq(hooks3.protocolFees(1), fees1After01Swap);
        assertGt(hooks3.protocolFees(2), 0);

        uint256 fees2After02Swap = hooks3.protocolFees(2);

        _executeExactInputSwap3(currency1, currency2, _toTokenWei(currency1, SWAP_AMOUNT));
        assertEq(hooks3.protocolFees(0), 0);
        assertEq(hooks3.protocolFees(1), fees1After01Swap);
        assertGt(hooks3.protocolFees(2), fees2After02Swap);
    }

    function test_hooks3_withdrawProtocolFees_ShouldTransferAllCurrencies() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        _executeExactInputSwap3(currency1, currency0, _toTokenWei(currency1, SWAP_AMOUNT));
        _executeExactInputSwap3(currency0, currency1, _toTokenWei(currency0, SWAP_AMOUNT));
        _executeExactInputSwap3(currency0, currency2, _toTokenWei(currency0, SWAP_AMOUNT));

        uint256 protocolFees0 = hooks3.protocolFees(0);
        uint256 protocolFees1 = hooks3.protocolFees(1);
        uint256 protocolFees2 = hooks3.protocolFees(2);

        assertGt(protocolFees0, 0);
        assertGt(protocolFees1, 0);
        assertGt(protocolFees2, 0);

        uint256 collectorBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(protocolFeeCollector);
        uint256 collectorBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(protocolFeeCollector);
        uint256 collectorBalance2Before = IERC20(Currency.unwrap(currency2)).balanceOf(protocolFeeCollector);

        hooks3.withdrawProtocolFees();

        uint256 collectorBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(protocolFeeCollector);
        uint256 collectorBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(protocolFeeCollector);
        uint256 collectorBalance2After = IERC20(Currency.unwrap(currency2)).balanceOf(protocolFeeCollector);

        assertEq(hooks3.protocolFees(0), 0);
        assertEq(hooks3.protocolFees(1), 0);
        assertEq(hooks3.protocolFees(2), 0);
        assertEq(collectorBalance0After - collectorBalance0Before, protocolFees0);
        assertEq(collectorBalance1After - collectorBalance1Before, protocolFees1);
        assertEq(collectorBalance2After - collectorBalance2Before, protocolFees2);
    }

    function test_hooks3_withdrawHookFees_ShouldTransferAllCurrencies() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        _executeExactInputSwap3(currency1, currency0, _toTokenWei(currency1, SWAP_AMOUNT));
        _executeExactInputSwap3(currency0, currency1, _toTokenWei(currency0, SWAP_AMOUNT));
        _executeExactInputSwap3(currency0, currency2, _toTokenWei(currency0, SWAP_AMOUNT));

        uint256 hookFees0 = hooks3.hookFees(0);
        uint256 hookFees1 = hooks3.hookFees(1);
        uint256 hookFees2 = hooks3.hookFees(2);

        assertGt(hookFees0, 0);
        assertGt(hookFees1, 0);
        assertGt(hookFees2, 0);

        uint256 hookFeeCollectorBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(hookFeeCollector);
        uint256 hookFeeCollectorBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(hookFeeCollector);
        uint256 hookFeeCollectorBalance2Before = IERC20(Currency.unwrap(currency2)).balanceOf(hookFeeCollector);

        hooks3.withdrawHookFees();

        uint256 hookFeeCollectorBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(hookFeeCollector);
        uint256 hookFeeCollectorBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(hookFeeCollector);
        uint256 hookFeeCollectorBalance2After = IERC20(Currency.unwrap(currency2)).balanceOf(hookFeeCollector);

        assertEq(hooks3.hookFees(0), 0);
        assertEq(hooks3.hookFees(1), 0);
        assertEq(hooks3.hookFees(2), 0);
        assertEq(hookFeeCollectorBalance0After - hookFeeCollectorBalance0Before, hookFees0);
        assertEq(hookFeeCollectorBalance1After - hookFeeCollectorBalance1Before, hookFees1);
        assertEq(hookFeeCollectorBalance2After - hookFeeCollectorBalance2Before, hookFees2);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions as PeripheryActions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";

import {Fees} from "src/Fees.sol";

contract StableSwapHooksFeesTest is StableSwapHooksBaseTest {
    uint256 private constant LIQUIDITY_AMOUNT = 1e6;
    uint256 private constant SWAP_AMOUNT = 1000;

    function _addLiquidity3(uint256 _amount0, uint256 _amount1, uint256 _amount2) internal {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, _amount0);
        amounts[1] = _toTokenWei(currency1, _amount1);
        amounts[2] = _toTokenWei(currency2, _amount2);

        vm.prank(liquidityProvider);
        hooks3.addLiquidity(amounts, 0);
    }

    function _executeSwap3(Currency _inputCurrency, Currency _outputCurrency, uint256 _amountIn) internal {
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.unwrap(_inputCurrency) < Currency.unwrap(_outputCurrency)
                ? _inputCurrency
                : _outputCurrency,
            currency1: Currency.unwrap(_inputCurrency) < Currency.unwrap(_outputCurrency)
                ? _outputCurrency
                : _inputCurrency,
            fee: uint24(BASE_LP_FEE_PERCENTAGE),
            tickSpacing: hooks3.TICK_SPACING(),
            hooks: IHooks(address(hooks3))
        });

        bool zeroForOne = Currency.unwrap(_inputCurrency) < Currency.unwrap(_outputCurrency);

        bytes memory actions = abi.encodePacked(
            uint8(PeripheryActions.SWAP_EXACT_IN_SINGLE),
            uint8(PeripheryActions.SETTLE_ALL),
            uint8(PeripheryActions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountIn: uint128(_amountIn),
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(_inputCurrency, _amountIn);
        params[2] = abi.encode(_outputCurrency, 0);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.prank(swapper);
        universalRouter.execute(commands, inputs, block.timestamp + 100);
    }

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

    function test_setProtocolFeeCollector_ShouldAllowZeroAddress() public {
        vm.prank(defaultAdmin);
        vm.expectEmit(address(hooks));
        emit Fees.ProtocolFeeCollectorSet(defaultAdmin, address(0));
        hooks.setProtocolFeeCollector(address(0));

        assertEq(hooks.protocolFeeCollector(), address(0));
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

        uint256 protocolFees1 = hooks.protocolFees(1);
        assertGt(protocolFees1, 0);

        uint256 collectorBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(protocolFeeCollector);

        uint256[] memory expectedFees = new uint256[](2);
        expectedFees[0] = 0;
        expectedFees[1] = protocolFees1;

        // The sender in the event is the original caller of withdrawProtocolFees
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

        // The sender in the event is the original caller of withdrawProtocolFees
        vm.expectEmit(address(hooks));
        emit Fees.ProtocolFeesWithdrawn(address(this), protocolFeeCollector, expectedFees);

        hooks.withdrawProtocolFees();

        assertEq(hooks.protocolFees(0), 0);
        assertEq(hooks.protocolFees(1), 0);
    }

    function test_withdrawHookFees_ShouldTransferFeesAndEmitEvent() public {
        // Add liquidity and perform a swap to accumulate fees
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));

        uint256 hookFees1 = hooks.hookFees(1);
        assertGt(hookFees1, 0);

        address beneficiary = makeAddr("beneficiary");
        uint256 beneficiaryBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(beneficiary);

        uint256[] memory expectedFees = new uint256[](2);
        expectedFees[0] = 0;
        expectedFees[1] = hookFees1;

        // The sender in the event is the original caller of withdrawHookFees
        vm.expectEmit(address(hooks));
        emit Fees.HookFeesWithdrawn(defaultAdmin, beneficiary, expectedFees);

        vm.prank(defaultAdmin);
        hooks.withdrawHookFees(beneficiary);

        uint256 beneficiaryBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(beneficiary);

        assertEq(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);
        assertEq(beneficiaryBalance1After - beneficiaryBalance1Before, hookFees1);
    }

    function test_withdrawHookFees_ShouldHandleZeroFees() public {
        assertEq(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);

        address beneficiary = makeAddr("beneficiary");

        uint256[] memory expectedFees = new uint256[](2);

        // The sender in the event is the original caller of withdrawHookFees
        vm.expectEmit(address(hooks));
        emit Fees.HookFeesWithdrawn(defaultAdmin, beneficiary, expectedFees);

        vm.prank(defaultAdmin);
        hooks.withdrawHookFees(beneficiary);

        assertEq(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);
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

    function test_swaps_ShouldAccumulateFeesOnZeroForOne() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        assertEq(hooks.protocolFees(0), 0);
        assertEq(hooks.protocolFees(1), 0);
        assertEq(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);

        // Exact input swap zeroForOne accumulates fees on currency1
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

        // Exact input swap oneForZero accumulates fees on currency0
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

        // Exact output swap zeroForOne: user specifies output (currency1), fees charged on input (currency0)
        _executeExactOutputSwap(true, _toTokenWei(currency1, SWAP_AMOUNT));

        assertGt(hooks.protocolFees(0), 0);
        assertEq(hooks.protocolFees(1), 0);
        assertGt(hooks.hookFees(0), 0);
        assertEq(hooks.hookFees(1), 0);
    }

    function test_withdrawProtocolFees_ShouldBeCallableByAnyone() public {
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        _executeExactInputSwap(true, _toTokenWei(currency0, SWAP_AMOUNT));

        uint256 protocolFees1 = hooks.protocolFees(1);
        assertGt(protocolFees1, 0);

        uint256 collectorBalanceBefore = IERC20(Currency.unwrap(currency1)).balanceOf(protocolFeeCollector);

        // Call from unauthorized user - should succeed (permissionless)
        vm.prank(unauthorizedUser);
        hooks.withdrawProtocolFees();

        uint256 collectorBalanceAfter = IERC20(Currency.unwrap(currency1)).balanceOf(protocolFeeCollector);

        assertEq(hooks.protocolFees(1), 0);
        assertEq(collectorBalanceAfter - collectorBalanceBefore, protocolFees1);
    }

    function test_getFees_ShouldReturnZeroForZeroAmount() public view {
        (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = hooks.getFees(0);

        assertEq(lpFees, 0);
        assertEq(hookFees, 0);
        assertEq(protocolFees, 0);
    }

    function test_setProtocolFeePercentage_ShouldAllowZero() public {
        vm.prank(defaultAdmin);
        vm.expectEmit(address(hooks));
        emit Fees.ProtocolFeePercentageSet(defaultAdmin, 0);
        hooks.setProtocolFeePercentage(0);

        assertEq(hooks.protocolFeePercentage(), 0);
    }

    function test_setHookFeePercentage_ShouldAllowZero() public {
        vm.prank(defaultAdmin);
        vm.expectEmit(address(hooks));
        emit Fees.HookFeePercentageSet(defaultAdmin, 0);
        hooks.setHookFeePercentage(0);

        assertEq(hooks.hookFeePercentage(), 0);
    }

    function test_setLpFeePercentage_ShouldAllowZero() public {
        vm.prank(defaultAdmin);
        vm.expectEmit(address(hooks));
        emit Fees.LpFeePercentageSet(defaultAdmin, 0);
        hooks.setLpFeePercentage(0);

        assertEq(hooks.lpFeePercentage(), 0);
    }

    function test_hooks3_ShouldAccumulateFeesOnAllCurrencies() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        // All fees should start at zero
        assertEq(hooks3.protocolFees(0), 0);
        assertEq(hooks3.protocolFees(1), 0);
        assertEq(hooks3.protocolFees(2), 0);

        // Swap 0 -> 1: fees on currency1
        _executeSwap3(currency0, currency1, _toTokenWei(currency0, SWAP_AMOUNT));
        assertEq(hooks3.protocolFees(0), 0);
        assertGt(hooks3.protocolFees(1), 0);
        assertEq(hooks3.protocolFees(2), 0);

        uint256 fees1After01Swap = hooks3.protocolFees(1);

        // Swap 0 -> 2: fees on currency2
        _executeSwap3(currency0, currency2, _toTokenWei(currency0, SWAP_AMOUNT));
        assertEq(hooks3.protocolFees(0), 0);
        assertEq(hooks3.protocolFees(1), fees1After01Swap);
        assertGt(hooks3.protocolFees(2), 0);

        uint256 fees2After02Swap = hooks3.protocolFees(2);

        // Swap 1 -> 2: fees on currency2
        _executeSwap3(currency1, currency2, _toTokenWei(currency1, SWAP_AMOUNT));
        assertEq(hooks3.protocolFees(0), 0);
        assertEq(hooks3.protocolFees(1), fees1After01Swap);
        assertGt(hooks3.protocolFees(2), fees2After02Swap);
    }

    function test_hooks3_withdrawProtocolFees_ShouldTransferAllCurrencies() public {
        _addLiquidity3(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        // Execute swaps to accumulate fees on all currencies
        _executeSwap3(currency1, currency0, _toTokenWei(currency1, SWAP_AMOUNT)); // fees on 0
        _executeSwap3(currency0, currency1, _toTokenWei(currency0, SWAP_AMOUNT)); // fees on 1
        _executeSwap3(currency0, currency2, _toTokenWei(currency0, SWAP_AMOUNT)); // fees on 2

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

        // Execute swaps to accumulate fees on all currencies
        _executeSwap3(currency1, currency0, _toTokenWei(currency1, SWAP_AMOUNT)); // fees on 0
        _executeSwap3(currency0, currency1, _toTokenWei(currency0, SWAP_AMOUNT)); // fees on 1
        _executeSwap3(currency0, currency2, _toTokenWei(currency0, SWAP_AMOUNT)); // fees on 2

        uint256 hookFees0 = hooks3.hookFees(0);
        uint256 hookFees1 = hooks3.hookFees(1);
        uint256 hookFees2 = hooks3.hookFees(2);

        assertGt(hookFees0, 0);
        assertGt(hookFees1, 0);
        assertGt(hookFees2, 0);

        address beneficiary = makeAddr("beneficiary");
        uint256 beneficiaryBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(beneficiary);
        uint256 beneficiaryBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(beneficiary);
        uint256 beneficiaryBalance2Before = IERC20(Currency.unwrap(currency2)).balanceOf(beneficiary);

        vm.prank(defaultAdmin);
        hooks3.withdrawHookFees(beneficiary);

        uint256 beneficiaryBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(beneficiary);
        uint256 beneficiaryBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(beneficiary);
        uint256 beneficiaryBalance2After = IERC20(Currency.unwrap(currency2)).balanceOf(beneficiary);

        assertEq(hooks3.hookFees(0), 0);
        assertEq(hooks3.hookFees(1), 0);
        assertEq(hooks3.hookFees(2), 0);
        assertEq(beneficiaryBalance0After - beneficiaryBalance0Before, hookFees0);
        assertEq(beneficiaryBalance1After - beneficiaryBalance1Before, hookFees1);
        assertEq(beneficiaryBalance2After - beneficiaryBalance2Before, hookFees2);
    }
}

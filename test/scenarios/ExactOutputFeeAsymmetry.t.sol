// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Vm} from "forge-std/Vm.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

contract ExactOutputFeeAsymmetryTest is StableSwapHooksBaseTest {
    bytes32 internal constant STABLE_SWAP_TOPIC =
        keccak256("StableSwap(address,address,address,uint256,uint256,uint256,uint256,uint256)");

    function setUp() public override {
        super.setUp();

        _addLiquidity(1_000_000, 1_000_000);
    }

    function test_exactOutput_chargesFeeOnNetInput_underchargingTheGrossLpFee() public {
        vm.recordLogs();
        _executeExactOutputSwap(true, _toTokenWei(currency1, 1000));

        (uint256 amountIn, uint256 totalFees) = _readSwapFees();

        uint256 grossLpFee = Math.mulDiv(amountIn, hooks.lpFeePercentage(), hooks.FEE_PRECISION(), Math.Rounding.Ceil);

        assertLt(totalFees, grossLpFee, "exact output should undercharge the gross lp fee while bug is present");
    }

    function _readSwapFees() internal returns (uint256 amountIn, uint256 totalFees) {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == STABLE_SWAP_TOPIC && logs[i].emitter == address(hooks)) {
                (uint256 swapAmountIn,, uint256 lpFees, uint256 hookFees, uint256 protocolFees) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, uint256));
                return (swapAmountIn, lpFees + hookFees + protocolFees);
            }
        }

        revert("StableSwap event not found");
    }
}

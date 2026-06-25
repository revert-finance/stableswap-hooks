// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapMath} from "src/libraries/StableSwapMath.sol";
import {SwapQuote} from "src/periphery/StableSwapZapIn.sol";
import {StableSwapZapInTest} from "test/StableSwapZapIn.t.sol";

contract ZapInFeeOverSwapTest is StableSwapZapInTest {
    uint256 private constant RATE_PRECISION = 1e18;

    function test_quoteZapIn_doesNotOverSwapDeficitWithHookProtocolFees() public {
        _addLiquidity3(1_000_000, 1_000_000, 1_000_000);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 500_000);

        (,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks3), amounts, 1);

        assertEq(swaps.length, 1, "scenario requires a single balancing swap");
        assertEq(swaps[0].tokenInIndex, 0, "swap sells the excess token");
        assertEq(swaps[0].tokenOutIndex, 1, "swap buys the deficit token");

        uint256 targetRatio = _scaledTargetRatio3(amounts);

        _executeExactInputSwap3(currency0, currency1, swaps[0].amountIn);

        uint256 postRatioDeficit = _scaledDeficitRatioAfterSwap(swaps[0].expectedAmountOut);

        assertLe(
            postRatioDeficit,
            targetRatio,
            "deficit token must not overshoot target ratio: solve accounts for hook+protocol fees in the reserve decrease"
        );
        assertApproxEqRel(
            postRatioDeficit, targetRatio, 1e7, "balancing swap must land on target within integer-rounding dust"
        );
    }

    function test_quoteZapIn_noOverSwapWhenHookProtocolFeesZero() public {
        vm.startPrank(defaultAdmin);
        hooks3.setHookFeePercentage(0);
        hooks3.setProtocolFeePercentage(0);
        vm.stopPrank();

        _addLiquidity3(1_000_000, 1_000_000, 1_000_000);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 500_000);

        (,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks3), amounts, 1);

        assertEq(swaps.length, 1, "scenario requires a single balancing swap");

        uint256 targetRatio = _scaledTargetRatio3(amounts);

        _executeExactInputSwap3(currency0, currency1, swaps[0].amountIn);

        uint256 postRatioDeficit = _scaledDeficitRatioAfterSwap(swaps[0].expectedAmountOut);

        assertLe(
            postRatioDeficit,
            targetRatio,
            "without hook/protocol fees the reserve decrease equals the user output, so no overshoot"
        );
    }

    function test_quoteZapIn_extremeDepositDoesNotOverflowFeeAdjustedSolve() public {
        _addLiquidity(1000, 1000);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 1e12);

        (uint256 shares,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);

        assertGt(shares, 0, "deposit far above reserves still quotes shares");
        assertEq(swaps.length, 1, "deposit far above reserves still produces a balancing swap");
    }

    function _scaledTargetRatio3(uint256[] memory _amounts) private view returns (uint256) {
        uint256 totalInputs;
        uint256 totalReserves;

        for (uint256 i = 0; i < 3; ++i) {
            uint256 rate = hooks3.rates(i);
            totalInputs += StableSwapMath.scaleTo(_amounts[i], rate);
            totalReserves += StableSwapMath.scaleTo(hooks3.reserves(i), rate);
        }

        return totalInputs * RATE_PRECISION / totalReserves;
    }

    function _scaledDeficitRatioAfterSwap(uint256 _expectedAmountOut) private view returns (uint256) {
        uint256 rate1 = hooks3.rates(1);
        uint256 postReserveDeficit = StableSwapMath.scaleTo(hooks3.reserves(1), rate1);
        uint256 deficitDeposit = StableSwapMath.scaleTo(_expectedAmountOut, rate1);

        return deficitDeposit * RATE_PRECISION / postReserveDeficit;
    }
}

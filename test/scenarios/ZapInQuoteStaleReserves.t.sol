// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapZapIn, SwapQuote, Swap} from "src/periphery/StableSwapZapIn.sol";
import {StableSwapZapInTest} from "test/StableSwapZapIn.t.sol";

contract ZapInQuoteStaleReservesTest is StableSwapZapInTest {
    function test_quoteZapIn_underestimatesShares_singleSidedTwoToken() public {
        _addLiquidity(1_000, 1_000);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 200);

        (uint256 quotedShares,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);
        assertGt(swaps.length, 0, "scenario requires at least one balancing swap");

        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, _toSwaps(swaps), 0);

        uint256 actualShares = hooks.balanceOf(zapUser);

        assertGt(actualShares, quotedShares, "quote underestimates: actual mint exceeds pre-swap-reserve quote");
        assertGt((actualShares - quotedShares) * 10_000 / actualShares, 100, "gap well above rounding noise");
    }

    function test_quoteZapIn_underestimatesShares_singleSidedThreeToken() public {
        _addLiquidity3(1_000_000, 1_000_000, 1_000_000);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 300_000);

        (uint256 quotedShares,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks3), amounts, 6);

        vm.prank(zapUser);
        zapIn.zapIn(address(hooks3), amounts, _toSwaps(swaps), 0);

        uint256 actualShares = hooks3.balanceOf(zapUser);

        assertGt(actualShares, quotedShares, "three-token single-sided quote also underestimates");
        assertGt((actualShares - quotedShares) * 10_000 / actualShares, 500, "three-token gap exceeds 5%");
    }

    function test_quoteDerivedMinShares_doesNotProtectAgainstFrontRun() public {
        _addLiquidity(1_000, 1_000);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 200);

        (uint256 quotedShares,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);
        uint256 minShares = quotedShares * 99 / 100;

        uint256 snap = vm.snapshotState();
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, _toSwaps(swaps), 0);
        uint256 baselineShares = hooks.balanceOf(zapUser);
        vm.revertToState(snap);

        _executeExactInputSwap(true, _toTokenWei(currency0, 100));

        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, _toSwaps(swaps), minShares);
        uint256 frontRunShares = hooks.balanceOf(zapUser);

        assertGe(frontRunShares, minShares, "quote-derived minShares floor is cleared");
        assertLt(frontRunShares, baselineShares * 99 / 100, "victim receives worse than a true 1% slippage bound");
        assertLt(quotedShares, baselineShares, "quote understates the no-MEV baseline, creating the headroom");
    }

    function test_quoteZapIn_overestimatesShares_revertsSlippageOnHonestExecution() public {
        _addLiquidity3(20, 5_000, 1_000);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 10);
        amounts[1] = _toTokenWei(currency1, 2);
        amounts[2] = _toTokenWei(currency2, 500);

        (uint256 quotedShares,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks3), amounts, 2);
        uint256 minShares = quotedShares * 99 / 100;

        vm.prank(zapUser);
        vm.expectRevert(StableSwapZapIn.SlippageExceeded.selector);
        zapIn.zapIn(address(hooks3), amounts, _toSwaps(swaps), minShares);

        vm.prank(zapUser);
        zapIn.zapIn(address(hooks3), amounts, _toSwaps(swaps), 0);
        uint256 actualShares = hooks3.balanceOf(zapUser);

        assertLt(actualShares, minShares, "honest static execution mints below the over-stated quote");
    }

    function test_quoteZapIn_reportsResultingAmounts_notHookActualAmounts() public {
        _addLiquidity3(1_000_000, 1_000, 1_000);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 1_000);
        amounts[1] = _toTokenWei(currency1, 1_000);
        amounts[2] = _toTokenWei(currency2, 1_000);

        (uint256 quotedShares, uint256[] memory resultingAmounts,) = zapIn.quoteZapIn(address(hooks3), amounts, 0);
        (, uint256[] memory hookActualAmounts) = hooks3.quoteAddLiquidity(resultingAmounts);

        bool diverges;
        for (uint256 i = 0; i < resultingAmounts.length; ++i) {
            if (hookActualAmounts[i] < resultingAmounts[i]) {
                diverges = true;
            }
        }

        assertTrue(diverges, "hook consumes fewer tokens than zap quote reports as deposited");

        vm.prank(zapUser);
        zapIn.zapIn(address(hooks3), amounts, new Swap[](0), quotedShares);

        assertGe(hooks3.balanceOf(zapUser), quotedShares, "strict quoted minShares does not catch the amount skew");
    }
}

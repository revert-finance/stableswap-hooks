// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapZapIn, SwapQuote, Swap} from "src/periphery/StableSwapZapIn.sol";
import {StableSwapZapInTest} from "test/StableSwapZapIn.t.sol";

contract ZapInQuoteStaleReservesTest is StableSwapZapInTest {
    function test_zapIn_quoteMatchesExecution_singleSidedTwoToken() public {
        _addLiquidity(1_000, 1_000);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 200);

        (uint256 quotedShares,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);
        assertGt(swaps.length, 0, "scenario requires at least one balancing swap");

        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, _toSwaps(swaps), 0);

        uint256 actualShares = hooks.balanceOf(zapUser);

        assertApproxEqRel(quotedShares, actualShares, 1e14, "quote must match post-swap execution within rounding");
    }

    function test_zapIn_quoteMatchesExecution_singleSidedThreeToken() public {
        _addLiquidity3(1_000_000, 1_000_000, 1_000_000);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 300_000);

        (uint256 quotedShares,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks3), amounts, 6);

        vm.prank(zapUser);
        zapIn.zapIn(address(hooks3), amounts, _toSwaps(swaps), 0);

        uint256 actualShares = hooks3.balanceOf(zapUser);

        assertApproxEqRel(quotedShares, actualShares, 1e14, "three-token quote must match execution within rounding");
    }

    function test_zapIn_quoteDerivedMinSharesBlocksFrontRun() public {
        _addLiquidity(1_000, 1_000);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 200);

        (uint256 quotedShares,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);
        uint256 minShares = quotedShares * 99 / 100;

        _executeExactInputSwap(true, _toTokenWei(currency0, 100));

        vm.prank(zapUser);
        vm.expectRevert(StableSwapZapIn.SlippageExceeded.selector);
        zapIn.zapIn(address(hooks), amounts, _toSwaps(swaps), minShares);
    }

    function test_zapIn_accurateQuoteDoesNotSelfDoS() public {
        _addLiquidity3(20, 5_000, 1_000);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 10);
        amounts[1] = _toTokenWei(currency1, 2);
        amounts[2] = _toTokenWei(currency2, 500);

        (uint256 quotedShares,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks3), amounts, 2);
        uint256 minShares = quotedShares * 99 / 100;

        vm.prank(zapUser);
        zapIn.zapIn(address(hooks3), amounts, _toSwaps(swaps), minShares);

        assertGe(hooks3.balanceOf(zapUser), minShares, "accurate quote no longer self-reverts on honest execution");
    }
}

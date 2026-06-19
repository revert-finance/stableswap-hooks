// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SwapQuote} from "src/periphery/StableSwapZapIn.sol";
import {StableSwapZapInTest} from "test/StableSwapZapIn.t.sol";

contract ZapInOvershootTest is StableSwapZapInTest {
    function test_firstSwapDoesNotOvershootTargetRatio() public {
        _addLiquidity3(1_000_000, 1_000_000, 1_000_000);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 500_000);

        (,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks3), amounts, 1);

        assertGt(swaps.length, 0, "scenario requires a balancing swap");
        assertEq(swaps[0].tokenInIndex, 0, "first swap sells the excess token");
        assertEq(swaps[0].tokenOutIndex, 1, "first swap buys the deficit token");

        uint256 dec1 = IERC20Metadata(Currency.unwrap(currency1)).decimals();
        uint256 analyticBound = 1_000_000 * 500_000 * (10 ** dec1) / 3_500_000;

        assertLe(
            swaps[0].expectedAmountOut,
            analyticBound,
            "output must not exceed the (1 + targetRatio) bound; dividing by RATE_PRECISION alone overshoots ~33%"
        );
    }

    function test_convergesWithinIterationBudget() public {
        _addLiquidity3(1_000_000, 1_000_000, 1_000_000);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 500_000);

        (uint256 sharesAt2,,) = zapIn.quoteZapIn(address(hooks3), amounts, 2);
        (uint256 sharesAt10,,) = zapIn.quoteZapIn(address(hooks3), amounts, 10);

        uint256 lossBasisPoints = ((sharesAt10 - sharesAt2) * 10_000) / sharesAt10;

        assertLt(lossBasisPoints, 100, "overshoot oscillation must not cost more than 1% across the iteration budget");
        assertApproxEqRel(sharesAt2, sharesAt10, 1e16, "(n-1) iterations must converge for a 3-token single-sided zap");
    }
}

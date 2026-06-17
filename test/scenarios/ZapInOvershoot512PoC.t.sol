// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapZapIn, SwapQuote, Swap} from "src/periphery/StableSwapZapIn.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

contract ZapInOvershoot512PoC is StableSwapHooksBaseTest {
    using SafeERC20 for IERC20;

    StableSwapZapIn internal zapIn;

    function setUp() public override {
        super.setUp();

        zapIn = new StableSwapZapIn(address(factory), keccak256(type(StableSwapHooks).creationCode));

        _addLiquidity3(1_000_000, 1_000_000, 1_000_000);
    }

    function test_overshoot_quantifyShareLoss() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 500_000);

        (uint256 sharesAt2,,) = zapIn.quoteZapIn(address(hooks3), amounts, 2);
        (uint256 sharesConverged,,) = zapIn.quoteZapIn(address(hooks3), amounts, 10);

        uint256 lossBasisPoints = ((sharesConverged - sharesAt2) * 10_000) / sharesConverged;

        assertGt(sharesConverged, sharesAt2, "converged shares must exceed low-iteration shares while bug present");
        assertGt(lossBasisPoints, 0, "optimal math: maxIter=2 should equal maxIter=10 for a 3-token pool");
    }

    function test_overshoot_extraSwapsAndPingPong() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 300_000);

        (,, SwapQuote[] memory swaps) = zapIn.quoteZapIn(address(hooks3), amounts, 10);

        assertGt(swaps.length, 2, "optimal algorithm needs at most 2 swaps for a 3-token single-sided zap");

        bool pingPong = false;

        for (uint256 i = 0; i < swaps.length; ++i) {
            for (uint256 j = 0; j < i; ++j) {
                if (swaps[j].tokenOutIndex == swaps[i].tokenInIndex) {
                    pingPong = true;
                }
            }
        }

        assertTrue(pingPong, "overshoot flips a deficit token into excess, forcing it to be sold back");
    }

    function test_zapIn_yieldsFewerShares_thanProportional() public {
        address zapUser = makeAddr("zapUser");
        address refUser = makeAddr("refUser");

        deal(Currency.unwrap(currency0), zapUser, _toTokenWei(currency0, 300_000));
        deal(Currency.unwrap(currency0), refUser, _toTokenWei(currency0, 100_000));
        deal(Currency.unwrap(currency1), refUser, _toTokenWei(currency1, 100_000));
        deal(Currency.unwrap(currency2), refUser, _toTokenWei(currency2, 100_000));

        vm.startPrank(zapUser);
        IERC20(Currency.unwrap(currency0)).forceApprove(address(zapIn), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).forceApprove(address(zapIn), type(uint256).max);
        IERC20(Currency.unwrap(currency2)).forceApprove(address(zapIn), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(refUser);
        IERC20(Currency.unwrap(currency0)).forceApprove(address(hooks3), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).forceApprove(address(hooks3), type(uint256).max);
        IERC20(Currency.unwrap(currency2)).forceApprove(address(hooks3), type(uint256).max);
        vm.stopPrank();

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 300_000);

        (,, SwapQuote[] memory quotes) = zapIn.quoteZapIn(address(hooks3), amounts, 10);

        Swap[] memory swaps = new Swap[](quotes.length);
        for (uint256 i = 0; i < quotes.length; ++i) {
            swaps[i] = Swap({
                tokenInIndex: quotes[i].tokenInIndex,
                tokenOutIndex: quotes[i].tokenOutIndex,
                amountIn: quotes[i].amountIn
            });
        }

        uint256 snap = vm.snapshotState();

        vm.prank(zapUser);
        zapIn.zapIn(address(hooks3), amounts, swaps, 0);
        uint256 zapShares = IERC20(address(hooks3)).balanceOf(zapUser);

        vm.revertToState(snap);

        uint256[] memory refAmounts = new uint256[](3);
        uint256[] memory refMin = new uint256[](3);
        refAmounts[0] = _toTokenWei(currency0, 100_000);
        refAmounts[1] = _toTokenWei(currency1, 100_000);
        refAmounts[2] = _toTokenWei(currency2, 100_000);

        vm.prank(refUser);
        hooks3.addLiquidity(refAmounts, refMin, 0);
        uint256 refShares = IERC20(address(hooks3)).balanceOf(refUser);

        assertGt(zapShares, 0, "zap user must receive shares");
        assertLt(zapShares, refShares, "overshoot makes zapIn yield fewer shares than an equal-value proportional deposit");
    }
}

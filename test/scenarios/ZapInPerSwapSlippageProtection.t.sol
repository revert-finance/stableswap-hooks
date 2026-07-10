// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapZapIn, SwapQuote, Swap} from "src/periphery/StableSwapZapIn.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";

contract ZapInPerSwapSlippageProtection is StableSwapHooksBaseTest {
    using SafeERC20 for IERC20;

    StableSwapZapIn internal zap;
    address internal victim;
    address internal organicSwapper;

    function setUp() public override {
        super.setUp();

        zap = new StableSwapZapIn(address(factory), keccak256(type(StableSwapHooks).creationCode));
        victim = makeAddr("victim");
        organicSwapper = makeAddr("organicSwapper");

        deal(Currency.unwrap(currency0), victim, _toTokenWei(currency0, 3_000_000));
        deal(Currency.unwrap(currency1), victim, _toTokenWei(currency1, 3_000_000));
        deal(Currency.unwrap(currency0), organicSwapper, _toTokenWei(currency0, 3_000_000));
        deal(Currency.unwrap(currency1), organicSwapper, _toTokenWei(currency1, 3_000_000));

        vm.startPrank(victim);
        IERC20(Currency.unwrap(currency0)).forceApprove(address(zap), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).forceApprove(address(zap), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(organicSwapper);
        IERC20(Currency.unwrap(currency0)).forceApprove(address(permit2), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(currency0), address(universalRouter), type(uint160).max, type(uint48).max);
        permit2.approve(Currency.unwrap(currency1), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function test_perSwapMinAmountOutRevertsStaleZap() public {
        _addLiquidity(1_000_000, 1_000_000);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 2_000_000);

        (uint256 quotedShares,, SwapQuote[] memory quoteSwaps) = zap.quoteZapIn(address(hooks), amounts, 1);
        assertEq(quoteSwaps.length, 1, "single-sided zap should quote one internal swap");

        _executePoolMove(true, _toTokenWei(currency0, 700_000));

        vm.prank(victim);
        vm.expectRevert(StableSwapZapIn.SlippageExceeded.selector);
        zap.zapIn(address(hooks), amounts, _toSwaps(quoteSwaps), quotedShares);
    }

    function test_perSwapMinAmountOutAllowsFreshZap() public {
        _addLiquidity(1_000_000, 1_000_000);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 2_000_000);

        (uint256 quotedShares,, SwapQuote[] memory quoteSwaps) = zap.quoteZapIn(address(hooks), amounts, 1);

        vm.prank(victim);
        zap.zapIn(address(hooks), amounts, _toSwaps(quoteSwaps), quotedShares);

        assertGe(hooks.balanceOf(victim), quotedShares, "fresh quote zap succeeds with per-swap floor set");
    }

    function _executePoolMove(bool zeroForOne, uint256 amountIn) internal {
        PoolKey memory poolKey = _getPoolKey();
        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountIn: uint128(amountIn),
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(inputCurrency, amountIn);
        params[2] = abi.encode(outputCurrency, 0);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.prank(organicSwapper);
        universalRouter.execute(abi.encodePacked(uint8(Commands.V4_SWAP)), inputs, block.timestamp + 100);
    }

    function _toSwaps(SwapQuote[] memory quoteSwaps) internal pure returns (Swap[] memory swaps) {
        swaps = new Swap[](quoteSwaps.length);
        for (uint256 i = 0; i < quoteSwaps.length; ++i) {
            swaps[i] = Swap({
                tokenInIndex: quoteSwaps[i].tokenInIndex,
                tokenOutIndex: quoteSwaps[i].tokenOutIndex,
                amountIn: quoteSwaps[i].amountIn,
                minAmountOut: quoteSwaps[i].expectedAmountOut * 99 / 100
            });
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {Swap} from "src/periphery/StableSwapZapIn.sol";
import {StableSwapZapInTest} from "test/StableSwapZapIn.t.sol";

contract ZapInStrandedBalanceSweepTest is StableSwapZapInTest {
    /// @notice Verifies that assets stranded on the zap contract benefit the next caller.
    /// @dev A depositor transfers token0 directly to the zap. The next zapIn caller then receives
    /// that stranded balance, both as LP shares minted from it and as a leftover refund, because
    /// StableSwapZapIn adds liquidity and refunds using whole-contract balances rather than per-call deltas.
    function test_zapIn_refundsStrandedBalanceToNextCaller() public {
        _addLiquidity(1_000, 1_000);

        address depositor = makeAddr("depositor");
        uint256 strandedAmount = _toTokenWei(currency0, 100);
        uint256 beneficiaryInput = _toTokenWei(currency1, 1);

        deal(Currency.unwrap(currency0), depositor, strandedAmount);

        vm.prank(depositor);
        IERC20(Currency.unwrap(currency0)).transfer(address(zapIn), strandedAmount);

        assertEq(
            IERC20(Currency.unwrap(currency0)).balanceOf(address(zapIn)),
            strandedAmount,
            "depositor tokens must be stranded on the zap before the attack"
        );

        uint256 beneficiaryToken0Before = IERC20(Currency.unwrap(currency0)).balanceOf(zapUser);
        uint256 beneficiaryLpBefore = hooks.balanceOf(zapUser);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = beneficiaryInput;

        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, new Swap[](0), 0);

        uint256 beneficiaryToken0After = IERC20(Currency.unwrap(currency0)).balanceOf(zapUser);
        uint256 beneficiaryLpAfter = hooks.balanceOf(zapUser);

        assertEq(
            beneficiaryToken0After - beneficiaryToken0Before,
            strandedAmount - _toTokenWei(currency0, 1),
            "beneficiary should receive the depositor's excess token0 via leftover refund"
        );
        assertEq(
            beneficiaryLpAfter - beneficiaryLpBefore,
            _toTokenWei(currency0, 1),
            "beneficiary should also receive LP shares backed by the depositor's token0"
        );
        assertEq(
            IERC20(Currency.unwrap(currency0)).balanceOf(address(zapIn)),
            0,
            "zap should not retain the depositor's token0"
        );
    }
}

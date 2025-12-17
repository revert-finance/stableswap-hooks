// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapMath} from "src/libraries/StableSwapMath.sol";

contract TokenMock {
    uint8 public decimals;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }
}

contract StableSwapMathTest is Test {
    function _makeReserves(uint256 reserves0, uint256 reserves1) internal pure returns (uint256[] memory) {
        uint256[] memory reserves = new uint256[](2);
        reserves[0] = reserves0;
        reserves[1] = reserves1;
        return reserves;
    }

    function test_getInvariant_ShouldReturnZeroForEmptyPool() public pure {
        uint256[] memory reserves = _makeReserves(0, 0);
        uint256 invariant = StableSwapMath.getInvariant(reserves, 100);
        assertEq(invariant, 0);
    }

    function test_getInvariant_ShouldEqualSumOfReservesForBalancedPool() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        assertEq(invariant, reserves0 + reserves1);
    }

    function test_getInvariant_ShouldBeLessThanSumForImbalancedPool() public pure {
        // For imbalanced pools, D < sum due to the constant-product component of the StableSwap curve
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 2000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);
        uint256 sum = reserves0 + reserves1;

        assertTrue(invariant < sum);
    }

    function test_getInvariant_ShouldBeSymmetric() public pure {
        uint256 reserves0 = 1234e18;
        uint256 reserves1 = 5678e18;
        uint256 amplification = 100;

        uint256[] memory reservesFwd = _makeReserves(reserves0, reserves1);
        uint256[] memory reservesRev = _makeReserves(reserves1, reserves0);

        uint256 invariant1 = StableSwapMath.getInvariant(reservesFwd, amplification);
        uint256 invariant2 = StableSwapMath.getInvariant(reservesRev, amplification);

        assertEq(invariant1, invariant2);
    }

    function test_getInvariant_ShouldIncreaseWithReserves() public pure {
        uint256 amplification = 100;

        uint256[] memory reservesSmall = _makeReserves(100e18, 100e18);
        uint256[] memory reservesLarge = _makeReserves(1000e18, 1000e18);

        uint256 invariantSmall = StableSwapMath.getInvariant(reservesSmall, amplification);
        uint256 invariantLarge = StableSwapMath.getInvariant(reservesLarge, amplification);

        assertTrue(invariantLarge > invariantSmall);
    }

    function test_getInvariant_ShouldBeCloserToSumWithHigherA() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 2000e18;
        uint256 sum = reserves0 + reserves1;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);

        uint256 invariantLowA = StableSwapMath.getInvariant(reserves, 50);
        uint256 invariantHighA = StableSwapMath.getInvariant(reserves, 1000);

        // Higher A pushes the curve toward constant-sum (x + y = D), so D approaches the sum of reserves.
        // Lower A pushes toward constant-product, where D < sum for imbalanced pools.
        uint256 diffLowA = sum - invariantLowA;
        uint256 diffHighA = sum - invariantHighA;

        assertTrue(diffHighA < diffLowA);
    }

    function test_getInvariant_ShouldHandleVeryLargeReserves() public pure {
        // Test numerical stability with large values (100 billion tokens with 18 decimals)
        uint256 reserves0 = 100_000_000_000e18;
        uint256 reserves1 = 100_000_000_000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // For balanced pool, invariant should equal sum
        assertEq(invariant, reserves0 + reserves1);
    }

    function test_getTargetReserves_ShouldReturnCurrentReserveWhenNoSwap() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);
        uint256 targetReserve = StableSwapMath.getTargetReserves(0, 1, reserves0, reserves, amplification, invariant);

        assertEq(targetReserve, reserves1);
    }

    function test_getTargetReserves_ShouldPreserveInvariant() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        uint256 newReserves0 = reserves0 + 50e18;
        uint256 newReserves1 = StableSwapMath.getTargetReserves(0, 1, newReserves0, reserves, amplification, invariant);

        uint256[] memory newReserves = _makeReserves(newReserves0, newReserves1);
        uint256 newInvariant = StableSwapMath.getInvariant(newReserves, amplification);

        // Newton-Raphson iteration may introduce up to 1 wei rounding error
        assertApproxEqAbs(newInvariant, invariant, 1);
    }

    function test_getTargetReserves_ShouldDecreaseOutputWhenInputIncreases() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        uint256 newReserves0 = reserves0 + 100e18;
        uint256 newTargetReserve =
            StableSwapMath.getTargetReserves(0, 1, newReserves0, reserves, amplification, invariant);

        assertTrue(newTargetReserve < reserves1);
    }

    function test_getTargetReserves_ShouldBeSymmetric() public pure {
        // Swapping A->B then B->A should roughly return to original (minus rounding)
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;
        uint256 swapAmount = 50e18;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // Swap 0 -> 1
        uint256 newReserves0 = reserves0 + swapAmount;
        uint256 newReserves1 = StableSwapMath.getTargetReserves(0, 1, newReserves0, reserves, amplification, invariant);
        uint256 outputFromFirstSwap = reserves1 - newReserves1;

        // Update reserves array for second swap
        uint256[] memory midReserves = _makeReserves(newReserves0, newReserves1);

        // Swap 1 -> 0 with the output from first swap
        uint256 finalReserves1 = newReserves1 + outputFromFirstSwap;
        uint256 finalReserves0 =
            StableSwapMath.getTargetReserves(1, 0, finalReserves1, midReserves, amplification, invariant);

        // Should be close to original reserves0 (within rounding tolerance)
        assertApproxEqAbs(finalReserves0, reserves0, 2);
    }

    function test_getTargetReserves_ShouldNeverExceedCurrentReserves() public pure {
        // Output reserve should never be negative (target should never exceed current)
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // Even with a large swap, target reserve should be >= 0
        uint256 largeSwapIn = 900e18;
        uint256 newReserves0 = reserves0 + largeSwapIn;
        uint256 targetReserve =
            StableSwapMath.getTargetReserves(0, 1, newReserves0, reserves, amplification, invariant);

        assertTrue(targetReserve <= reserves1);
        assertTrue(targetReserve > 0);
    }

    function test_getTargetReserves_ShouldHandleLargeSwapNearingDepletion() public pure {
        // Test behavior when swap nearly depletes one side
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // Swap that would deplete ~95% of reserves1
        uint256 veryLargeSwapIn = 5000e18;
        uint256 newReserves0 = reserves0 + veryLargeSwapIn;
        uint256 targetReserve =
            StableSwapMath.getTargetReserves(0, 1, newReserves0, reserves, amplification, invariant);

        // Target reserve should be positive but very small
        assertTrue(targetReserve > 0);
        assertTrue(targetReserve < reserves1 / 10); // Less than 10% remaining
    }

    function test_getTargetReserves_ShouldHaveLowSlippageForSmallSwaps() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        // A=20000 matches production Curve pools (e.g., 3pool uses A_precise=2000000, which is A=20000)
        uint256 amplification = 20000;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // Small swap: 1% of pool
        uint256 swapIn = 10e18;
        uint256 newReserves0 = reserves0 + swapIn;
        uint256 newTargetReserve =
            StableSwapMath.getTargetReserves(0, 1, newReserves0, reserves, amplification, invariant);
        uint256 swapOut = reserves1 - newTargetReserve;

        // Slippage in basis points: (amountIn - amountOut) / amountIn * 10000
        // For comparison, constant-product AMM would give ~99 bps slippage for a 1% swap.
        // With A=20000, StableSwap achieves sub-1-bps slippage.
        uint256 slippageBps = ((swapIn - swapOut) * 10000) / swapIn;
        assertLt(slippageBps, 1);
    }

    function test_getTargetReserves_ShouldHaveLowerSlippageWithHigherA() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 swapIn = 100e18;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);

        // Low A
        uint256 invariantLowA = StableSwapMath.getInvariant(reserves, 50);
        uint256 targetReserveLowA =
            StableSwapMath.getTargetReserves(0, 1, reserves0 + swapIn, reserves, 50, invariantLowA);
        uint256 outLowA = reserves1 - targetReserveLowA;

        // High A
        uint256 invariantHighA = StableSwapMath.getInvariant(reserves, 1000);
        uint256 targetReserveHighA =
            StableSwapMath.getTargetReserves(0, 1, reserves0 + swapIn, reserves, 1000, invariantHighA);
        uint256 outHighA = reserves1 - targetReserveHighA;

        // Higher A pushes the curve toward constant-sum, giving more output (less slippage).
        // Lower A pushes toward constant-product, giving less output (more slippage).
        assertTrue(outHighA > outLowA);
    }

    function test_scaleTo_ShouldRoundTripWithDescale() public pure {
        // Token with 6 decimals (e.g., USDC) => rate = 10^(36-6) = 1e30
        // scaleTo: amount * rate / 1e18 = 123e6 * 1e30 / 1e18 = 123e18
        // descale: scaled * 1e18 / rate = 123e18 * 1e18 / 1e30 = 123e6
        uint256 rate = 1e30;
        uint256 tokenAmount = 123e6; // 123 tokens with 6 decimals

        uint256 scaledTo = StableSwapMath.scaleTo(tokenAmount, rate);
        uint256 descaled = StableSwapMath.descale(scaledTo, rate);

        assertEq(scaledTo, 123e18);
        assertEq(descaled, tokenAmount);
    }

    function test_scaleTo_ShouldReturnZeroForZeroAmount() public pure {
        uint256 rate = 1e30;

        assertEq(StableSwapMath.scaleTo(0, rate), 0);
    }

    function test_scaleTo_ShouldRoundTripWithDescaleForArbitraryDecimals() public pure {
        // Token with 7 decimals => stored rate 1e29 (effective factor 1e11)
        uint256 rate = 1e29;
        uint256 amount = 123_456_789;

        uint256 scaled = StableSwapMath.scaleTo(amount, rate);
        uint256 back = StableSwapMath.descale(scaled, rate);

        assertEq(back, amount);
    }

    function test_scaleTo_ShouldBeIdentityFor18DecimalTokens() public pure {
        // For 18-decimal tokens, rate = 1e18, so scaleTo should be identity
        uint256 rate = 1e18; // 10^(36 - 18)
        uint256 amount = 123e18;

        uint256 scaled = StableSwapMath.scaleTo(amount, rate);

        assertEq(scaled, amount);
    }

    function test_scaleTo_ShouldHandleVerySmallAmounts() public pure {
        // Test potential rounding to zero for very small amounts
        uint256 rate = 1e30; // 6-decimal token
        uint256 verySmallAmount = 1; // 1 wei of a 6-decimal token

        uint256 scaled = StableSwapMath.scaleTo(verySmallAmount, rate);

        // 1 * 1e30 / 1e18 = 1e12
        assertEq(scaled, 1e12);
    }

    function test_descale_ShouldReturnZeroForZeroAmount() public pure {
        uint256 rate = 1e30;

        assertEq(StableSwapMath.descale(0, rate), 0);
    }

    function test_descale_ShouldBeIdentityFor18DecimalTokens() public pure {
        // For 18-decimal tokens, rate = 1e18, so descale should be identity
        uint256 rate = 1e18;
        uint256 amount = 456e18;

        uint256 descaled = StableSwapMath.descale(amount, rate);

        assertEq(descaled, amount);
    }

    function test_descale_ShouldRoundDownForSmallAmounts() public pure {
        // Test rounding behavior for amounts that don't divide evenly
        uint256 rate = 1e30; // 6-decimal token
        uint256 scaledAmount = 1e12 + 1e11; // 1.1e12 in scaled form

        uint256 descaled = StableSwapMath.descale(scaledAmount, rate);

        // (1.1e12 * 1e18) / 1e30 = 1.1, rounds down to 1
        assertEq(descaled, 1);
    }

    function test_getRate_ShouldReturnScalingFactorBasedOnDecimals() public {
        // Rate formula: 10^(36 - decimals)
        // This allows scaleTo/descale to normalize any token to 18 decimals for internal math
        TokenMock token = new TokenMock(6);
        Currency currency = Currency.wrap(address(token));
        uint256 rate = StableSwapMath.getRate(currency);
        assertEq(rate, 1e30); // 10^(36 - 6) for 6-decimal tokens (USDC, USDT)

        token = new TokenMock(18);
        currency = Currency.wrap(address(token));
        rate = StableSwapMath.getRate(currency);
        assertEq(rate, 1e18); // 10^(36 - 18) for 18-decimal tokens (DAI)
    }

    function test_getRate_ShouldHandleVariousDecimals() public {
        // Test a range of decimal values
        uint8[5] memory decimalsToTest = [uint8(0), uint8(8), uint8(12), uint8(18), uint8(24)];
        uint256[5] memory expectedRates = [uint256(1e36), uint256(1e28), uint256(1e24), uint256(1e18), uint256(1e12)];

        for (uint256 i = 0; i < decimalsToTest.length; i++) {
            TokenMock token = new TokenMock(decimalsToTest[i]);
            Currency currency = Currency.wrap(address(token));
            uint256 rate = StableSwapMath.getRate(currency);
            assertEq(rate, expectedRates[i]);
        }
    }
}

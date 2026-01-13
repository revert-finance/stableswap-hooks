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
    function _makeReserves(uint256 reserves0, uint256 reserves1) private pure returns (uint256[] memory) {
        uint256[] memory reserves = new uint256[](2);
        reserves[0] = reserves0;
        reserves[1] = reserves1;
        return reserves;
    }

    function _makeReserves3(uint256 r0, uint256 r1, uint256 r2) private pure returns (uint256[] memory) {
        uint256[] memory reserves = new uint256[](3);
        reserves[0] = r0;
        reserves[1] = r1;
        reserves[2] = r2;
        return reserves;
    }

    function _makeReserves4(uint256 r0, uint256 r1, uint256 r2, uint256 r3) private pure returns (uint256[] memory) {
        uint256[] memory reserves = new uint256[](4);
        reserves[0] = r0;
        reserves[1] = r1;
        reserves[2] = r2;
        reserves[3] = r3;
        return reserves;
    }

    function _makeValues(uint256 v0, uint256 v1) private pure returns (uint256[] memory) {
        uint256[] memory values = new uint256[](2);
        values[0] = v0;
        values[1] = v1;
        return values;
    }

    function _makeValues3(uint256 v0, uint256 v1, uint256 v2) private pure returns (uint256[] memory) {
        uint256[] memory values = new uint256[](3);
        values[0] = v0;
        values[1] = v1;
        values[2] = v2;
        return values;
    }

    function _makeValues4(uint256 v0, uint256 v1, uint256 v2, uint256 v3) private pure returns (uint256[] memory) {
        uint256[] memory values = new uint256[](4);
        values[0] = v0;
        values[1] = v1;
        values[2] = v2;
        values[3] = v3;
        return values;
    }

    function _makeValues1(uint256 v0) private pure returns (uint256[] memory) {
        uint256[] memory values = new uint256[](1);
        values[0] = v0;
        return values;
    }

    function _makeValues5(uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory values = new uint256[](5);
        values[0] = v0;
        values[1] = v1;
        values[2] = v2;
        values[3] = v3;
        values[4] = v4;
        return values;
    }

    // ==========================================================================
    // getInvariant
    // ==========================================================================

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

    function test_getInvariant_ShouldHandleVerySmallReserves() public pure {
        // Test with dust amounts (1 wei each)
        uint256 reserves0 = 1;
        uint256 reserves1 = 1;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // For balanced pool, invariant should equal sum even with tiny amounts
        assertEq(invariant, reserves0 + reserves1);
    }

    function test_getInvariant_ShouldHandleLowAmp() public pure {
        // A=50 is low but should work (very low A with imbalanced pools can overflow)
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1500e18; // Less imbalanced to avoid overflow
        uint256 amplification = 50;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // With low A, invariant should still be calculated but further from sum
        uint256 sum = reserves0 + reserves1;
        assertTrue(invariant > 0);
        assertTrue(invariant < sum);
    }

    function test_getInvariant_ShouldWorkWith3Currencies() public pure {
        uint256 r0 = 1000e18;
        uint256 r1 = 1000e18;
        uint256 r2 = 1000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves3(r0, r1, r2);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // For balanced 3-currency pool, invariant should equal sum
        assertEq(invariant, r0 + r1 + r2);
    }

    function test_getInvariant_ShouldBeSymmetricWith3Currencies() public pure {
        uint256 r0 = 1000e18;
        uint256 r1 = 2000e18;
        uint256 r2 = 3000e18;
        uint256 amplification = 100;

        uint256[] memory reserves1 = _makeReserves3(r0, r1, r2);
        uint256[] memory reserves2 = _makeReserves3(r2, r0, r1);
        uint256[] memory reserves3 = _makeReserves3(r1, r2, r0);

        uint256 inv1 = StableSwapMath.getInvariant(reserves1, amplification);
        uint256 inv2 = StableSwapMath.getInvariant(reserves2, amplification);
        uint256 inv3 = StableSwapMath.getInvariant(reserves3, amplification);

        assertEq(inv1, inv2);
        assertEq(inv2, inv3);
    }

    // ==========================================================================
    // getInvariant - Fuzz Tests
    // ==========================================================================

    function testFuzz_getInvariant_ShouldBeSymmetric(uint64 _r0, uint64 _r1) public pure {
        // Minimum reserves and limit imbalance ratio to 100:1 (extreme imbalance causes convergence issues)
        vm.assume(_r0 >= 1e15 && _r1 >= 1e15);
        uint256 r0 = uint256(_r0);
        uint256 r1 = uint256(_r1);
        vm.assume(r0 * 100 >= r1 && r1 * 100 >= r0);
        uint256 amplification = 100;

        uint256[] memory reservesFwd = _makeReserves(r0, r1);
        uint256[] memory reservesRev = _makeReserves(r1, r0);

        uint256 invariant1 = StableSwapMath.getInvariant(reservesFwd, amplification);
        uint256 invariant2 = StableSwapMath.getInvariant(reservesRev, amplification);

        // Newton-Raphson may have 1 wei variance depending on iteration order
        assertApproxEqAbs(invariant1, invariant2, 1);
    }

    function testFuzz_getInvariant_ShouldAlwaysConverge(uint64 _r0, uint64 _r1, uint32 _amp) public pure {
        // Minimum reserves, minimum amp, and limit imbalance ratio
        vm.assume(_r0 >= 1e15 && _r1 >= 1e15 && _amp >= 50);
        uint256 r0 = uint256(_r0);
        uint256 r1 = uint256(_r1);
        vm.assume(r0 * 100 >= r1 && r1 * 100 >= r0);
        uint256 amp = uint256(_amp);

        uint256[] memory reserves = _makeReserves(r0, r1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amp);

        // Invariant should always be positive for non-zero reserves
        assertTrue(invariant > 0);
        // Invariant should never exceed sum of reserves
        assertTrue(invariant <= r0 + r1);
    }

    // ==========================================================================
    // getTargetReserves
    // ==========================================================================

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
        uint256 targetReserve = StableSwapMath.getTargetReserves(0, 1, newReserves0, reserves, amplification, invariant);

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
        uint256 targetReserve = StableSwapMath.getTargetReserves(0, 1, newReserves0, reserves, amplification, invariant);

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

    function test_getTargetReserves_ShouldHandleLowAmp() public pure {
        // A=50 is low but should still work (very low A can overflow)
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 50;

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        uint256 swapIn = 100e18;
        uint256 newReserves0 = reserves0 + swapIn;
        uint256 targetReserve = StableSwapMath.getTargetReserves(0, 1, newReserves0, reserves, amplification, invariant);

        // Should still produce valid output
        assertTrue(targetReserve > 0);
        assertTrue(targetReserve < reserves1);
    }

    function test_getTargetReserves_ShouldWorkWith3Currencies() public pure {
        uint256 r0 = 1000e18;
        uint256 r1 = 1000e18;
        uint256 r2 = 1000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves3(r0, r1, r2);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // Swap from currency 0 to currency 2
        uint256 swapIn = 100e18;
        uint256 newR0 = r0 + swapIn;
        uint256 targetR2 = StableSwapMath.getTargetReserves(0, 2, newR0, reserves, amplification, invariant);

        // Output reserve should decrease
        assertTrue(targetR2 < r2);
        assertTrue(targetR2 > 0);
    }

    // ==========================================================================
    // getTargetReserves - Fuzz Tests
    // ==========================================================================

    function testFuzz_getTargetReserves_ShouldPreserveInvariant(uint128 _swapIn) public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        // Bound swap to reasonable percentage of pool (0.01% to 50%)
        uint256 swapIn = bound(uint256(_swapIn), reserves0 / 10000, reserves0 / 2);

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        uint256 newReserves0 = reserves0 + swapIn;
        uint256 newReserves1 = StableSwapMath.getTargetReserves(0, 1, newReserves0, reserves, amplification, invariant);

        uint256[] memory newReserves = _makeReserves(newReserves0, newReserves1);
        uint256 newInvariant = StableSwapMath.getInvariant(newReserves, amplification);

        // Invariant should be preserved within 2 wei tolerance (Newton-Raphson rounding)
        assertApproxEqAbs(newInvariant, invariant, 2);
    }

    function testFuzz_getTargetReserves_OutputShouldNeverExceedReserve(uint128 _swapIn) public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        // Even with very large swaps, output reserve should stay positive
        uint256 swapIn = bound(uint256(_swapIn), 1, reserves0 * 100);

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        uint256 newReserves0 = reserves0 + swapIn;
        uint256 targetReserve = StableSwapMath.getTargetReserves(0, 1, newReserves0, reserves, amplification, invariant);

        assertTrue(targetReserve > 0);
        assertTrue(targetReserve <= reserves1);
    }

    // ==========================================================================
    // scaleTo / descale
    // ==========================================================================

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

    // ==========================================================================
    // scaleTo / descale - Fuzz Tests
    // ==========================================================================

    function testFuzz_scaleTo_ShouldRoundTrip(uint128 _amount, uint8 _decimals) public pure {
        // Bound decimals to realistic range (0-18 for upscaling, avoids precision loss)
        uint8 decimals = uint8(bound(uint256(_decimals), 0, 18));
        uint256 rate = 10 ** (36 - decimals);

        // Bound amount to avoid overflow when scaling
        uint256 maxAmount = type(uint256).max / rate;
        uint256 amount = bound(uint256(_amount), 0, maxAmount);

        uint256 scaled = StableSwapMath.scaleTo(amount, rate);
        uint256 back = StableSwapMath.descale(scaled, rate);

        // Round-trip should preserve original value
        assertEq(back, amount);
    }

    function testFuzz_scaleTo_ShouldPreserveRelativeOrder(uint128 _a, uint128 _b) public pure {
        uint256 rate = 1e30; // 6-decimal token

        uint256 a = uint256(_a);
        uint256 b = uint256(_b);

        uint256 scaledA = StableSwapMath.scaleTo(a, rate);
        uint256 scaledB = StableSwapMath.scaleTo(b, rate);

        // Scaling should preserve relative ordering
        if (a > b) {
            assertTrue(scaledA > scaledB);
        } else if (a < b) {
            assertTrue(scaledA < scaledB);
        } else {
            assertEq(scaledA, scaledB);
        }
    }

    function testFuzz_descale_ShouldRoundDown(uint128 _scaled) public pure {
        uint256 rate = 1e30; // 6-decimal token
        uint256 scaled = uint256(_scaled);

        uint256 descaled = StableSwapMath.descale(scaled, rate);
        uint256 rescaled = StableSwapMath.scaleTo(descaled, rate);

        // Rescaled should be <= original scaled (due to rounding down)
        assertTrue(rescaled <= scaled);
    }

    // ==========================================================================
    // getRate
    // ==========================================================================

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

    function test_getRate_ShouldReturn1For36Decimals() public {
        // Edge case: 36 decimals => rate = 10^(36 - 36) = 1
        TokenMock token = new TokenMock(36);
        Currency currency = Currency.wrap(address(token));
        uint256 rate = StableSwapMath.getRate(currency);
        assertEq(rate, 1);
    }

    // ==========================================================================
    // geometricMean
    // ==========================================================================

    function test_geometricMean_ShouldCalculateCorrectlyForTwoValues() public pure {
        // sqrt(4 * 9) = sqrt(36) = 6
        uint256[] memory values = new uint256[](2);
        values[0] = 4;
        values[1] = 9;
        uint256 result = StableSwapMath.geometricMean(values);
        assertEq(result, 6);
    }

    function test_geometricMean_ShouldCalculateCorrectlyForTwoEqualValues() public pure {
        // sqrt(100 * 100) = 100
        uint256[] memory values = new uint256[](2);
        values[0] = 100e18;
        values[1] = 100e18;
        uint256 result = StableSwapMath.geometricMean(values);
        assertEq(result, 100e18);
    }

    function test_geometricMean_ShouldCalculateCorrectlyForThreeValues() public pure {
        // cbrt(8) * cbrt(27) * cbrt(64) = 2 * 3 * 4 = 24
        // (8 * 27 * 64)^(1/3) = (13824)^(1/3) = 24
        uint256[] memory values = _makeValues3(8, 27, 64);
        uint256 result = StableSwapMath.geometricMean(values);
        assertEq(result, 24);
    }

    function test_geometricMean_ShouldCalculateCorrectlyForThreeEqualValues() public pure {
        // For 3 equal values, geometricMean uses cbrt(a) * cbrt(b) * cbrt(c)
        // cbrt(1000e18) ≈ 10e6 (since (10e6)^3 = 1e21, not 1e18)
        // Actually cbrt(1000e18) = cbrt(1e21) = 1e7
        // So result = 1e7 * 1e7 * 1e7 = 1e21
        uint256[] memory values = _makeValues3(1000e18, 1000e18, 1000e18);
        uint256 result = StableSwapMath.geometricMean(values);
        // cbrt(1000e18) = 1e7 (since 1e21 = 1e7^3), so result = 1e7 * 1e7 * 1e7 = 1e21
        assertEq(result, 1e21);
    }

    function test_geometricMean_ShouldCalculateCorrectlyForFourValues() public pure {
        // (16 * 81 * 256 * 625)^(1/4) = (209715200)^(1/4) = 120.27... ≈ 120
        // Actually: 2^4 * 3^4 * 4^4 * 5^4 = (2*3*4*5)^4 = 120^4
        // So (16 * 81 * 256 * 625)^(1/4) = 120
        uint256[] memory values = _makeValues4(16, 81, 256, 625);
        uint256 result = StableSwapMath.geometricMean(values);
        assertEq(result, 120);
    }

    function test_geometricMean_ShouldCalculateCorrectlyForFourEqualValues() public pure {
        // (100e18)^4 ^ (1/4) = 100e18
        uint256[] memory values = _makeValues4(100e18, 100e18, 100e18, 100e18);
        uint256 result = StableSwapMath.geometricMean(values);
        assertEq(result, 100e18);
    }

    function test_geometricMean_ShouldHandleLargeValues() public pure {
        // Test with large values to ensure no overflow
        uint256[] memory values = _makeValues(1e36, 1e36);
        uint256 result = StableSwapMath.geometricMean(values);
        assertEq(result, 1e36);
    }

    function test_geometricMean_ShouldHandleAsymmetricValues() public pure {
        // sqrt(1e18 * 1e36) = sqrt(1e54) = 1e27
        uint256[] memory values = _makeValues(1e18, 1e36);
        uint256 result = StableSwapMath.geometricMean(values);
        assertEq(result, 1e27);
    }

    function test_geometricMean_ShouldRevertForSingleValue() public {
        uint256[] memory values = _makeValues1(100);
        vm.expectRevert(StableSwapMath.InvalidDegree.selector);
        this.callGeometricMean(values);
    }

    function test_geometricMean_ShouldRevertForFiveValues() public {
        uint256[] memory values = _makeValues5(1, 2, 3, 4, 5);
        vm.expectRevert(StableSwapMath.InvalidDegree.selector);
        this.callGeometricMean(values);
    }

    function test_geometricMean_ShouldRevertForEmptyArray() public {
        uint256[] memory values = new uint256[](0);
        vm.expectRevert(StableSwapMath.InvalidDegree.selector);
        this.callGeometricMean(values);
    }

    function callGeometricMean(uint256[] memory values) external pure returns (uint256) {
        return StableSwapMath.geometricMean(values);
    }

    // ==========================================================================
    // geometricMean - Fuzz Tests
    // ==========================================================================

    function testFuzz_geometricMean_TwoValues_ShouldBeBetweenMinAndMax(uint128 _a, uint128 _b) public pure {
        vm.assume(_a > 0 && _b > 0);
        uint256 a = uint256(_a);
        uint256 b = uint256(_b);

        uint256[] memory values = _makeValues(a, b);
        uint256 result = StableSwapMath.geometricMean(values);

        uint256 minVal = a < b ? a : b;
        uint256 maxVal = a > b ? a : b;

        // Geometric mean is always between min and max (or equal if a == b)
        assertTrue(result >= minVal);
        assertTrue(result <= maxVal);
    }

    function testFuzz_geometricMean_ThreeValues_ShouldBePositive(uint64 _a, uint64 _b, uint64 _c) public pure {
        vm.assume(_a > 0 && _b > 0 && _c > 0);

        uint256[] memory values = _makeValues3(uint256(_a), uint256(_b), uint256(_c));
        uint256 result = StableSwapMath.geometricMean(values);

        assertTrue(result > 0);
    }

    function testFuzz_geometricMean_FourValues_ShouldBePositive(uint64 _a, uint64 _b, uint64 _c, uint64 _d)
        public
        pure
    {
        vm.assume(_a > 0 && _b > 0 && _c > 0 && _d > 0);

        uint256[] memory values = _makeValues4(uint256(_a), uint256(_b), uint256(_c), uint256(_d));
        uint256 result = StableSwapMath.geometricMean(values);

        assertTrue(result > 0);
    }

    // ==========================================================================
    // cbrt
    // ==========================================================================

    function test_cbrt_ShouldReturnCorrectValueForPerfectCubes() public pure {
        assertEq(StableSwapMath.cbrt(0), 0);
        assertEq(StableSwapMath.cbrt(1), 1);
        assertEq(StableSwapMath.cbrt(8), 2);
        assertEq(StableSwapMath.cbrt(27), 3);
        assertEq(StableSwapMath.cbrt(64), 4);
        assertEq(StableSwapMath.cbrt(125), 5);
        assertEq(StableSwapMath.cbrt(1000), 10);
        assertEq(StableSwapMath.cbrt(1000000), 100);
        assertEq(StableSwapMath.cbrt(1e18), 1e6);
        assertEq(StableSwapMath.cbrt(1e27), 1e9);
    }

    function test_cbrt_ShouldRoundDownForNonPerfectCubes() public pure {
        // cbrt(9) = 2.08..., should round down to 2
        assertEq(StableSwapMath.cbrt(9), 2);
        // cbrt(26) = 2.96..., should round down to 2
        assertEq(StableSwapMath.cbrt(26), 2);
        // cbrt(28) = 3.03..., should round down to 3
        assertEq(StableSwapMath.cbrt(28), 3);
        // cbrt(100) = 4.64..., should round down to 4
        assertEq(StableSwapMath.cbrt(100), 4);
    }

    function test_cbrt_ShouldHandleLargeValues() public pure {
        // cbrt(type(uint256).max) should not overflow
        uint256 result = StableSwapMath.cbrt(type(uint256).max);
        // type(uint256).max ≈ 1.15e77, cbrt ≈ 4.87e25
        assertTrue(result > 0);
        // Verify: result^3 <= input < (result+1)^3
        assertTrue(result * result * result <= type(uint256).max);
    }

    function test_cbrt_ShouldHandleSmallValues() public pure {
        assertEq(StableSwapMath.cbrt(0), 0);
        assertEq(StableSwapMath.cbrt(1), 1);
        assertEq(StableSwapMath.cbrt(2), 1);
        assertEq(StableSwapMath.cbrt(7), 1);
        assertEq(StableSwapMath.cbrt(8), 2);
    }

    // ==========================================================================
    // cbrt - Fuzz Tests
    // ==========================================================================

    function testFuzz_cbrt_ShouldSatisfyCubeRootProperty(uint256 _x) public pure {
        uint256 z = StableSwapMath.cbrt(_x);

        // z^3 <= x
        assertTrue(z * z * z <= _x);

        // (z+1)^3 > x (unless z+1 would overflow, in which case z is correct)
        if (z < type(uint256).max) {
            uint256 zPlus1 = z + 1;
            // Check for overflow in (z+1)^3
            if (zPlus1 <= 6981463658331) {
                // Max z where z^3 doesn't overflow
                assertTrue(zPlus1 * zPlus1 * zPlus1 > _x);
            }
        }
    }

    // ==========================================================================
    // getInvariant - 4 Currencies
    // ==========================================================================

    function test_getInvariant_ShouldWorkWith4Currencies() public pure {
        uint256 r0 = 1000e18;
        uint256 r1 = 1000e18;
        uint256 r2 = 1000e18;
        uint256 r3 = 1000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves4(r0, r1, r2, r3);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // For balanced 4-currency pool, invariant should equal sum
        assertEq(invariant, r0 + r1 + r2 + r3);
    }

    function test_getInvariant_ShouldBeSymmetricWith4Currencies() public pure {
        uint256 r0 = 1000e18;
        uint256 r1 = 2000e18;
        uint256 r2 = 3000e18;
        uint256 r3 = 4000e18;
        uint256 amplification = 100;

        uint256[] memory reserves1 = _makeReserves4(r0, r1, r2, r3);
        uint256[] memory reserves2 = _makeReserves4(r3, r0, r1, r2);
        uint256[] memory reserves3 = _makeReserves4(r2, r3, r0, r1);

        uint256 inv1 = StableSwapMath.getInvariant(reserves1, amplification);
        uint256 inv2 = StableSwapMath.getInvariant(reserves2, amplification);
        uint256 inv3 = StableSwapMath.getInvariant(reserves3, amplification);

        // Newton-Raphson may have 1 wei variance depending on iteration order
        assertApproxEqAbs(inv1, inv2, 1);
        assertApproxEqAbs(inv2, inv3, 1);
    }

    function test_getInvariant_ShouldBeLessThanSumForImbalanced4CurrencyPool() public pure {
        uint256 r0 = 1000e18;
        uint256 r1 = 2000e18;
        uint256 r2 = 3000e18;
        uint256 r3 = 4000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves4(r0, r1, r2, r3);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);
        uint256 sum = r0 + r1 + r2 + r3;

        assertTrue(invariant < sum);
    }

    // ==========================================================================
    // getTargetReserves - 4 Currencies
    // ==========================================================================

    function test_getTargetReserves_ShouldWorkWith4Currencies() public pure {
        uint256 r0 = 1000e18;
        uint256 r1 = 1000e18;
        uint256 r2 = 1000e18;
        uint256 r3 = 1000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves4(r0, r1, r2, r3);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // Swap from currency 0 to currency 3
        uint256 swapIn = 100e18;
        uint256 newR0 = r0 + swapIn;
        uint256 targetR3 = StableSwapMath.getTargetReserves(0, 3, newR0, reserves, amplification, invariant);

        // Output reserve should decrease
        assertTrue(targetR3 < r3);
        assertTrue(targetR3 > 0);
    }

    function test_getTargetReserves_ShouldPreserveInvariantWith4Currencies() public pure {
        uint256 r0 = 1000e18;
        uint256 r1 = 1000e18;
        uint256 r2 = 1000e18;
        uint256 r3 = 1000e18;
        uint256 amplification = 100;

        uint256[] memory reserves = _makeReserves4(r0, r1, r2, r3);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // Swap from currency 1 to currency 2
        uint256 swapIn = 50e18;
        uint256 newR1 = r1 + swapIn;
        uint256 newR2 = StableSwapMath.getTargetReserves(1, 2, newR1, reserves, amplification, invariant);

        uint256[] memory newReserves = _makeReserves4(r0, newR1, newR2, r3);
        uint256 newInvariant = StableSwapMath.getInvariant(newReserves, amplification);

        // Invariant should be preserved within rounding tolerance
        assertApproxEqAbs(newInvariant, invariant, 2);
    }

    // ==========================================================================
    // getInvariant - High Amplification
    // ==========================================================================

    function test_getInvariant_ShouldHandleVeryHighAmplification() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 2000e18;
        uint256 amplification = 100000; // Very high A

        uint256[] memory reserves = _makeReserves(reserves0, reserves1);
        uint256 invariant = StableSwapMath.getInvariant(reserves, amplification);

        // With very high A, invariant approaches sum
        uint256 sum = reserves0 + reserves1;
        uint256 diff = sum - invariant;

        // Should be very close to sum (within 0.01%)
        assertTrue(diff * 10000 < sum);
    }
}

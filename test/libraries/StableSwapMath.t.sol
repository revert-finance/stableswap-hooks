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
    function test_getInvariant_ShouldReturnZeroForEmptyPool() public pure {
        uint256 invariant = StableSwapMath.getInvariant(0, 0, 100);
        assertEq(invariant, 0);
    }

    function test_getInvariant_ShouldCalculateCorrectlyForBalancedPool() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256 invariant = StableSwapMath.getInvariant(reserves0, reserves1, amplification);

        // For balanced pool, D should equal x0 + x1
        assertEq(invariant, reserves0 + reserves1);
    }

    function test_getInvariant_ShouldBeSymmetric() public pure {
        uint256 reserves0 = 1234e18;
        uint256 reserves1 = 5678e18;
        uint256 amplification = 100;

        uint256 invariant1 = StableSwapMath.getInvariant(reserves0, reserves1, amplification);
        uint256 invariant2 = StableSwapMath.getInvariant(reserves1, reserves0, amplification);

        assertEq(invariant1, invariant2);
    }

    function test_getInvariant_ShouldIncreaseWithReserves() public pure {
        uint256 amplification = 100;

        uint256 invariantSmall = StableSwapMath.getInvariant(100e18, 100e18, amplification);
        uint256 invariantLarge = StableSwapMath.getInvariant(1000e18, 1000e18, amplification);

        assertTrue(invariantLarge > invariantSmall);
    }

    function test_getInvariant_ShouldBeCloserToSumWithHigherA() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 2000e18;
        uint256 sum = reserves0 + reserves1;

        uint256 invariantLowA = StableSwapMath.getInvariant(reserves0, reserves1, 50);
        uint256 invariantHighA = StableSwapMath.getInvariant(reserves0, reserves1, 1000);

        // Higher A should give D closer to sum
        uint256 diffLowA = sum - invariantLowA;
        uint256 diffHighA = sum - invariantHighA;

        assertTrue(diffHighA < diffLowA);
    }

    function test_getOtherReserves_ShouldCalculateCorrectlyForBalancedPool() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256 invariant = StableSwapMath.getInvariant(reserves0, reserves1, amplification);
        uint256 otherReserve = StableSwapMath.getOtherReserves(reserves0, amplification, invariant);

        // For balanced pool, y should equal x1
        assertEq(otherReserve, reserves1);
    }

    function test_getOtherReserves_ShouldPreserveInvariant() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256 invariant = StableSwapMath.getInvariant(reserves0, reserves1, amplification);

        // Simulate swap: add 50e18 to x0
        uint256 newReserves0 = reserves0 + 50e18;
        uint256 newReserves1 = StableSwapMath.getOtherReserves(newReserves0, amplification, invariant);

        // Recalculate D with new reserves
        uint256 newInvariant = StableSwapMath.getInvariant(newReserves0, newReserves1, amplification);

        // D should be preserved (within 1 wei rounding)
        assertApproxEqAbs(newInvariant, invariant, 1);
    }

    function test_getOtherReserves_ShouldDecreaseOutputReserve() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256 invariant = StableSwapMath.getInvariant(reserves0, reserves1, amplification);

        // Add to x0, y should decrease
        uint256 newReserves0 = reserves0 + 100e18;
        uint256 newOtherReserve = StableSwapMath.getOtherReserves(newReserves0, amplification, invariant);

        assertTrue(newOtherReserve < reserves1);
    }

    function test_getOtherReserves_ShouldHaveLowSlippageForSmallSwaps() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256 invariant = StableSwapMath.getInvariant(reserves0, reserves1, amplification);

        // Small swap: 1% of pool
        uint256 swapIn = 10e18;
        uint256 newReserves0 = reserves0 + swapIn;
        uint256 newOtherReserve = StableSwapMath.getOtherReserves(newReserves0, amplification, invariant);
        uint256 swapOut = reserves1 - newOtherReserve;

        // Slippage should be < 1% for small swap on balanced pool
        uint256 slippageBps = ((swapIn - swapOut) * 10000) / swapIn;
        assertTrue(slippageBps < 100);
    }

    function test_getOtherReserves_ShouldHaveLowerSlippageWithHigherA() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 swapIn = 100e18;

        // Low A
        uint256 invariantLowA = StableSwapMath.getInvariant(reserves0, reserves1, 50);
        uint256 otherReserveLowA = StableSwapMath.getOtherReserves(reserves0 + swapIn, 50, invariantLowA);
        uint256 outLowA = reserves1 - otherReserveLowA;

        // High A
        uint256 invariantHighA = StableSwapMath.getInvariant(reserves0, reserves1, 1000);
        uint256 otherReserveHighA = StableSwapMath.getOtherReserves(reserves0 + swapIn, 1000, invariantHighA);
        uint256 outHighA = reserves1 - otherReserveHighA;

        // Higher A should give more output (less slippage)
        assertTrue(outHighA > outLowA);
    }

    function test_scaleTo_ShouldRoundTripWithDescale() public pure {
        // Token with 6 decimals => rate stored as 1e30, effective factor 1e12 after / 1e18
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

    function test_descale_ShouldReturnZeroForZeroAmount() public pure {
        uint256 rate = 1e30;

        assertEq(StableSwapMath.descale(0, rate), 0);
    }

    function test_descale_ShouldInvertScaleToForArbitraryAmounts() public pure {
        // Token with 7 decimals => stored rate 1e29 (effective factor 1e11)
        uint256 rate = 1e29;
        uint256 amount = 123_456_789;

        uint256 scaled = StableSwapMath.scaleTo(amount, rate);
        uint256 back = StableSwapMath.descale(scaled, rate);

        assertEq(back, amount);
    }

    function test_getRate_ShouldReturnExpectedDecimalsConversion() public {
        TokenMock token = new TokenMock(6);
        Currency currency = Currency.wrap(address(token));
        uint256 rate = StableSwapMath.getRate(currency);
        assertEq(rate, 1e30); // 10**(36 - 6)

        token = new TokenMock(18);
        currency = Currency.wrap(address(token));
        rate = StableSwapMath.getRate(currency);
        assertEq(rate, 1e18); // 10**(36 - 18)
    }
}

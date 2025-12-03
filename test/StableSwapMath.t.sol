// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StableSwapMath} from "../src/libraries/StableSwapMath.sol";

contract StableSwapMathTest is Test {
    function test_getInvariant_returnsZeroForEmptyPool() public pure {
        uint256 invariant = StableSwapMath.getInvariant(0, 0, 100);
        assertEq(invariant, 0);
    }

    function test_getInvariant_balancedPool() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256 invariant = StableSwapMath.getInvariant(reserves0, reserves1, amplification);

        // For balanced pool, D should equal x0 + x1
        assertEq(invariant, reserves0 + reserves1);
    }

    function test_getInvariant_symmetry() public pure {
        uint256 reserves0 = 1234e18;
        uint256 reserves1 = 5678e18;
        uint256 amplification = 100;

        uint256 invariant1 = StableSwapMath.getInvariant(reserves0, reserves1, amplification);
        uint256 invariant2 = StableSwapMath.getInvariant(reserves1, reserves0, amplification);

        assertEq(invariant1, invariant2);
    }

    function test_getInvariant_increasesWithReserves() public pure {
        uint256 amplification = 100;

        uint256 invariantSmall = StableSwapMath.getInvariant(100e18, 100e18, amplification);
        uint256 invariantLarge = StableSwapMath.getInvariant(1000e18, 1000e18, amplification);

        assertTrue(invariantLarge > invariantSmall);
    }

    function test_getInvariant_higherA_closerToSum() public pure {
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

    function test_getOtherReserve_balancedPool() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256 invariant = StableSwapMath.getInvariant(reserves0, reserves1, amplification);
        uint256 otherReserve = StableSwapMath.getOtherReserve(reserves0, amplification, invariant);

        // For balanced pool, y should equal x1
        assertEq(otherReserve, reserves1);
    }

    function test_getOtherReserve_preservesInvariant() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256 invariant = StableSwapMath.getInvariant(reserves0, reserves1, amplification);

        // Simulate swap: add 50e18 to x0
        uint256 newReserves0 = reserves0 + 50e18;
        uint256 newReserves1 = StableSwapMath.getOtherReserve(newReserves0, amplification, invariant);

        // Recalculate D with new reserves
        uint256 newInvariant = StableSwapMath.getInvariant(newReserves0, newReserves1, amplification);

        // D should be preserved (within 1 wei rounding)
        assertApproxEqAbs(newInvariant, invariant, 1);
    }

    function test_getOtherReserve_outputDecreasesReserve() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256 invariant = StableSwapMath.getInvariant(reserves0, reserves1, amplification);

        // Add to x0, y should decrease
        uint256 newReserves0 = reserves0 + 100e18;
        uint256 newOtherReserve = StableSwapMath.getOtherReserve(newReserves0, amplification, invariant);

        assertTrue(newOtherReserve < reserves1);
    }

    function test_getOtherReserve_lowSlippage() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 amplification = 100;

        uint256 invariant = StableSwapMath.getInvariant(reserves0, reserves1, amplification);

        // Small swap: 1% of pool
        uint256 swapIn = 10e18;
        uint256 newReserves0 = reserves0 + swapIn;
        uint256 newOtherReserve = StableSwapMath.getOtherReserve(newReserves0, amplification, invariant);
        uint256 swapOut = reserves1 - newOtherReserve;

        // Slippage should be < 1% for small swap on balanced pool
        uint256 slippageBps = ((swapIn - swapOut) * 10000) / swapIn;
        assertTrue(slippageBps < 100);
    }

    function test_getOtherReserve_higherA_lowerSlippage() public pure {
        uint256 reserves0 = 1000e18;
        uint256 reserves1 = 1000e18;
        uint256 swapIn = 100e18;

        // Low A
        uint256 invariantLowA = StableSwapMath.getInvariant(reserves0, reserves1, 50);
        uint256 otherReserveLowA = StableSwapMath.getOtherReserve(reserves0 + swapIn, 50, invariantLowA);
        uint256 outLowA = reserves1 - otherReserveLowA;

        // High A
        uint256 invariantHighA = StableSwapMath.getInvariant(reserves0, reserves1, 1000);
        uint256 otherReserveHighA = StableSwapMath.getOtherReserve(reserves0 + swapIn, 1000, invariantHighA);
        uint256 outHighA = reserves1 - otherReserveHighA;

        // Higher A should give more output (less slippage)
        assertTrue(outHighA > outLowA);
    }
}

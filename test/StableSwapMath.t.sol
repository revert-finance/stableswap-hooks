// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StableSwapMath} from "../src/libraries/StableSwapMath.sol";

contract StableSwapMathTest is Test {
    function test_getD_returnsZeroForEmptyPool() public pure {
        uint256 D = StableSwapMath.getD(0, 0, 100);
        assertEq(D, 0);
    }

    function test_getD_balancedPool() public pure {
        uint256 x0 = 1000e18;
        uint256 x1 = 1000e18;
        uint256 A = 100;

        uint256 D = StableSwapMath.getD(x0, x1, A);

        // For balanced pool, D should equal x0 + x1
        assertEq(D, x0 + x1);
    }

    function test_getD_symmetry() public pure {
        uint256 x0 = 1234e18;
        uint256 x1 = 5678e18;
        uint256 A = 100;

        uint256 D1 = StableSwapMath.getD(x0, x1, A);
        uint256 D2 = StableSwapMath.getD(x1, x0, A);

        assertEq(D1, D2);
    }

    function test_getD_increasesWithReserves() public pure {
        uint256 A = 100;

        uint256 dSmall = StableSwapMath.getD(100e18, 100e18, A);
        uint256 dLarge = StableSwapMath.getD(1000e18, 1000e18, A);

        assertTrue(dLarge > dSmall);
    }

    function test_getD_higherA_closerToSum() public pure {
        uint256 x0 = 1000e18;
        uint256 x1 = 2000e18;
        uint256 sum = x0 + x1;

        uint256 dLowA = StableSwapMath.getD(x0, x1, 50);
        uint256 dHighA = StableSwapMath.getD(x0, x1, 1000);

        // Higher A should give D closer to sum
        uint256 diffLowA = sum - dLowA;
        uint256 diffHighA = sum - dHighA;

        assertTrue(diffHighA < diffLowA);
    }

    function test_getY_balancedPool() public pure {
        uint256 x0 = 1000e18;
        uint256 x1 = 1000e18;
        uint256 A = 100;

        uint256 D = StableSwapMath.getD(x0, x1, A);
        uint256 y = StableSwapMath.getY(x0, A, D);

        // For balanced pool, y should equal x1
        assertEq(y, x1);
    }

    function test_getY_preservesInvariant() public pure {
        uint256 x0 = 1000e18;
        uint256 x1 = 1000e18;
        uint256 A = 100;

        uint256 D = StableSwapMath.getD(x0, x1, A);

        // Simulate swap: add 50e18 to x0
        uint256 newX0 = x0 + 50e18;
        uint256 newX1 = StableSwapMath.getY(newX0, A, D);

        // Recalculate D with new reserves
        uint256 newD = StableSwapMath.getD(newX0, newX1, A);

        // D should be preserved (within 1 wei rounding)
        assertApproxEqAbs(newD, D, 1);
    }

    function test_getY_outputDecreasesReserve() public pure {
        uint256 x0 = 1000e18;
        uint256 x1 = 1000e18;
        uint256 A = 100;

        uint256 D = StableSwapMath.getD(x0, x1, A);

        // Add to x0, y should decrease
        uint256 newX0 = x0 + 100e18;
        uint256 newY = StableSwapMath.getY(newX0, A, D);

        assertTrue(newY < x1);
    }

    function test_getY_lowSlippage() public pure {
        uint256 x0 = 1000e18;
        uint256 x1 = 1000e18;
        uint256 A = 100;

        uint256 D = StableSwapMath.getD(x0, x1, A);

        // Small swap: 1% of pool
        uint256 swapIn = 10e18;
        uint256 newX0 = x0 + swapIn;
        uint256 newY = StableSwapMath.getY(newX0, A, D);
        uint256 swapOut = x1 - newY;

        // Slippage should be < 1% for small swap on balanced pool
        uint256 slippageBps = ((swapIn - swapOut) * 10000) / swapIn;
        assertTrue(slippageBps < 100);
    }

    function test_getY_higherA_lowerSlippage() public pure {
        uint256 x0 = 1000e18;
        uint256 x1 = 1000e18;
        uint256 swapIn = 100e18;

        // Low A
        uint256 dLowA = StableSwapMath.getD(x0, x1, 50);
        uint256 yLowA = StableSwapMath.getY(x0 + swapIn, 50, dLowA);
        uint256 outLowA = x1 - yLowA;

        // High A
        uint256 dHighA = StableSwapMath.getD(x0, x1, 1000);
        uint256 yHighA = StableSwapMath.getY(x0 + swapIn, 1000, dHighA);
        uint256 outHighA = x1 - yHighA;

        // Higher A should give more output (less slippage)
        assertTrue(outHighA > outLowA);
    }
}

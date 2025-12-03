// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
library StableSwapMath {
    /// @dev Precision divisor for amplification coefficient calculations.
    uint256 internal constant AMPLIFICATION_PRECISION = 100;

    /// @dev Number of currencies in the pool (n in the invariant formula).
    uint256 internal constant CURRENCY_COUNT = 2;

    error ConvergenceNotReached();

    /// @notice Compute the StableSwap invariant D for two reserves.
    /// @dev Iteratively solves A·n^n·Σx_i + D = A·D·n^n + D^(n+1)/(n^n·Πx_i), starting with D = Σx_i.
    /// @param reserves0 Scaled reserve of currency 0.
    /// @param reserves1 Scaled reserve of currency 1.
    /// @param amplification Amplification coefficient A.
    /// @return invariant The converged invariant D.
    function getInvariant(uint256 reserves0, uint256 reserves1, uint256 amplification)
        internal
        pure
        returns (uint256 invariant)
    {
        uint256 totalReserves = reserves0 + reserves1;

        if (totalReserves == 0) {
            return 0;
        }

        invariant = totalReserves;
        uint256 ampTimesCoins = amplification * CURRENCY_COUNT;

        // Newton-Raphson over D. For two currencies the product term is D^(n+1) / (n^n * x0 * x1) with n = 2.
        for (uint256 i = 0; i < 255; ++i) {
            uint256 productTerm = invariant;
            productTerm = (productTerm * invariant) / reserves0;
            productTerm = (productTerm * invariant) / reserves1;
            productTerm = productTerm / (CURRENCY_COUNT * CURRENCY_COUNT);

            uint256 previousInvariant = invariant;

            uint256 numerator =
                ((ampTimesCoins * totalReserves) / AMPLIFICATION_PRECISION + productTerm * CURRENCY_COUNT) * invariant;
            uint256 denominator = ((ampTimesCoins - AMPLIFICATION_PRECISION) * invariant) / AMPLIFICATION_PRECISION
                + (CURRENCY_COUNT + 1) * productTerm;
            invariant = numerator / denominator;

            if (invariant > previousInvariant) {
                if (invariant - previousInvariant <= 1) return invariant;
            } else {
                if (previousInvariant - invariant <= 1) return invariant;
            }
        }

        revert ConvergenceNotReached();
    }

    /// @notice Compute the missing reserve given the other reserve and invariant.
    /// @dev Rearranges the invariant into a quadratic and applies Newton-Raphson on the unknown reserve.
    /// @param knownReserves The known reserve after a swap (scaled).
    /// @param amplification Amplification coefficient A.
    /// @param invariant The invariant D that must be preserved.
    /// @return otherReserve The calculated missing reserve.
    function getOtherReserve(uint256 knownReserves, uint256 amplification, uint256 invariant)
        internal
        pure
        returns (uint256 otherReserve)
    {
        uint256 ampTimesCoins = amplification * CURRENCY_COUNT;

        // constantTerm = D^3 / (A*n^n*n*x)
        uint256 constantTerm = (invariant * invariant) / (knownReserves * CURRENCY_COUNT);
        constantTerm = (constantTerm * invariant * AMPLIFICATION_PRECISION) / (ampTimesCoins * CURRENCY_COUNT);

        // linearCoefficient = x + D / (A * n^n)
        uint256 linearCoefficient = knownReserves + (invariant * AMPLIFICATION_PRECISION) / ampTimesCoins;

        otherReserve = invariant;

        for (uint256 i = 0; i < 255; ++i) {
            uint256 previousOtherReserve = otherReserve;

            otherReserve =
                (otherReserve * otherReserve + constantTerm) / (2 * otherReserve + linearCoefficient - invariant);

            if (otherReserve > previousOtherReserve) {
                if (otherReserve - previousOtherReserve <= 1) return otherReserve;
            } else {
                if (previousOtherReserve - otherReserve <= 1) return otherReserve;
            }
        }

        revert ConvergenceNotReached();
    }
}

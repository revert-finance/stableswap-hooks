// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

library StableSwapMath {
    /// @dev Precision divisor for amplification coefficient calculations.
    uint256 internal constant AMPLIFICATION_PRECISION = 100;

    /// @dev Number of currencies in the pool (n in the invariant formula).
    uint256 internal constant CURRENCY_COUNT = 2;

    /// @dev Fixed-point precision (1e18) used when scaling token rates and amounts.
    uint256 internal constant RATE_PRECISION = 1e18;

    error ConvergenceNotReached();

    /// @notice Compute the StableSwap invariant D for two reserves.
    /// @dev Iteratively solves A·n^n·Σx_i + D = A·D·n^n + D^(n+1)/(n^n·Πx_i), starting with D = Σx_i.
    /// Reserves must be pre-scaled to 1e18 precision;
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

    /// @notice Compute the missing reserves given the other reserve and invariant.
    /// @dev Rearranges the invariant into a quadratic and applies Newton-Raphson on the unknown reserve.
    /// @param knownReserves The known reserve after a swap (scaled to 1e18 decimals).
    /// @param amplification Amplification coefficient A.
    /// @param invariant The invariant D that must be preserved.
    /// @return otherReserve The calculated missing reserve (scaled).
    function getOtherReserves(uint256 knownReserves, uint256 amplification, uint256 invariant)
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

    /// @dev Scales a token amount into 1e18 precision using the given rate.
    /// @param amount Token-denominated amount.
    /// @param rate Scaling factor for the token.
    /// @return Scaled amount in 1e18 precision.
    function scaleTo(uint256 amount, uint256 rate) internal pure returns (uint256) {
        return rate * amount / RATE_PRECISION;
    }

    /// @dev Converts a 1e18-precision amount back to token units using the given rate.
    /// @param amount 1e18-scaled amount.
    /// @param rate Scaling factor for the token.
    /// @return Token-denominated amount.
    function descale(uint256 amount, uint256 rate) internal pure returns (uint256) {
        return amount * RATE_PRECISION / rate;
    }

    /// @dev Returns the rate for a given currency.
    /// @param currency The currency to get the rate for.
    /// @return The rate for the currency.
    function getRate(Currency currency) internal view returns (uint256) {
        return 10 ** (36 - IERC20Metadata(Currency.unwrap(currency)).decimals());
    }
}

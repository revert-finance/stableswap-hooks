// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/// @notice Library containing StableSwap mathematical functions for invariant and reserve calculations
library StableSwapMath {
    /// @dev Precision divisor for amplification coefficient calculations.
    uint256 internal constant AMPLIFICATION_PRECISION = 100;

    /// @dev Number of currencies in the pool (n in the invariant formula).
    uint256 internal constant CURRENCY_COUNT = 2;

    /// @dev Fixed-point precision (1e18) used when scaling token rates and amounts.
    uint256 internal constant RATE_PRECISION = 1e18;

    /// @notice Error thrown when Newton-Raphson iteration fails to converge within 255 iterations
    error ConvergenceNotReached();

    /// @notice Compute the StableSwap invariant D for two reserves.
    /// @dev Iteratively solves A·n^n·Σx_i + D = A·D·n^n + D^(n+1)/(n^n·Πx_i), starting with D = Σx_i.
    /// Reserves must be pre-scaled to 1e18 precision;
    /// @param _reserves0 Scaled reserve of currency 0.
    /// @param _reserves1 Scaled reserve of currency 1.
    /// @param _amplification Amplification coefficient A.
    /// @return invariant The converged invariant D.
    function getInvariant(uint256 _reserves0, uint256 _reserves1, uint256 _amplification)
        internal
        pure
        returns (uint256 invariant)
    {
        uint256 totalReserves = _reserves0 + _reserves1;

        if (totalReserves == 0) {
            return 0;
        }

        invariant = totalReserves;
        uint256 ampTimesCoins = _amplification * CURRENCY_COUNT;

        // Newton-Raphson over D. For two currencies the product term is D^(n+1) / (n^n * x0 * x1) with n = 2.
        for (uint256 i = 0; i < 255; ++i) {
            uint256 productTerm = invariant;
            productTerm = (productTerm * invariant) / _reserves0;
            productTerm = (productTerm * invariant) / _reserves1;
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

    /// @notice Compute the missing reserves given the other reserves and invariant.
    /// @dev Rearranges the invariant into a quadratic and applies Newton-Raphson on the unknown reserves.
    /// @param _knownReserves The known reserves after a swap (scaled to 1e18 decimals).
    /// @param _amplification Amplification coefficient A.
    /// @param _invariant The invariant D that must be preserved.
    /// @return otherReserves The calculated missing reserves (scaled).
    function getOtherReserves(uint256 _knownReserves, uint256 _amplification, uint256 _invariant)
        internal
        pure
        returns (uint256 otherReserves)
    {
        uint256 ampTimesCoins = _amplification * CURRENCY_COUNT;

        // constantTerm = D^3 / (A*n^n*n*x)
        uint256 constantTerm = (_invariant * _invariant) / (_knownReserves * CURRENCY_COUNT);
        constantTerm = (constantTerm * _invariant * AMPLIFICATION_PRECISION) / (ampTimesCoins * CURRENCY_COUNT);

        // linearCoefficient = x + D / (A * n^n)
        uint256 linearCoefficient = _knownReserves + (_invariant * AMPLIFICATION_PRECISION) / ampTimesCoins;

        otherReserves = _invariant;

        for (uint256 i = 0; i < 255; ++i) {
            uint256 previousOtherReserves = otherReserves;

            otherReserves =
                (otherReserves * otherReserves + constantTerm) / (2 * otherReserves + linearCoefficient - _invariant);

            if (otherReserves > previousOtherReserves) {
                if (otherReserves - previousOtherReserves <= 1) return otherReserves;
            } else {
                if (previousOtherReserves - otherReserves <= 1) return otherReserves;
            }
        }

        revert ConvergenceNotReached();
    }

    /// @dev Scales a token amount into 1e18 precision using the given rate.
    /// @param _amount Token-denominated amount.
    /// @param _rate Scaling factor for the token.
    /// @return Scaled amount in 1e18 precision.
    function scaleTo(uint256 _amount, uint256 _rate) internal pure returns (uint256) {
        return _rate * _amount / RATE_PRECISION;
    }

    /// @dev Converts a 1e18-precision amount back to token units using the given rate.
    /// @param _amount 1e18-scaled amount.
    /// @param _rate Scaling factor for the token.
    /// @return Token-denominated amount.
    function descale(uint256 _amount, uint256 _rate) internal pure returns (uint256) {
        return _amount * RATE_PRECISION / _rate;
    }

    /// @dev Returns the rate for a given currency.
    /// @param _currency The currency to get the rate for.
    /// @return The rate for the currency.
    function getRate(Currency _currency) internal view returns (uint256) {
        return 10 ** (36 - IERC20Metadata(Currency.unwrap(_currency)).decimals());
    }
}

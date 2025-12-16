// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/// @notice Library containing StableSwap mathematical functions for invariant and reserve calculations
library StableSwapMath {
    /// @dev Precision divisor for amplification coefficient calculations.
    uint256 internal constant AMP_PRECISION = 100;

    /// @dev Fixed-point precision (1e18) used when scaling token rates and amounts.
    uint256 internal constant RATE_PRECISION = 1e18;

    /// @notice Error thrown when Newton-Raphson iteration fails to converge within 255 iterations
    error ConvergenceNotReached();

    /// @notice Compute the StableSwap invariant D for N reserves.
    /// @param _scaledReserves Array of scaled reserves for all currencies.
    /// @param _amplification Amplification coefficient A.
    function getInvariant(uint256[] memory _scaledReserves, uint256 _amplification)
        internal
        pure
        returns (uint256 invariant)
    {
        // TODO: Keep in immutable value?
        uint256 nCurrencies = _scaledReserves.length;

        uint256 totalReserves = 0;

        for (uint256 i = 0; i < nCurrencies; ++i) {
            totalReserves += _scaledReserves[i];
        }

        if (totalReserves == 0) {
            return 0;
        }

        invariant = totalReserves;

        uint256 ampTimesCoins = _amplification * nCurrencies;

        for (uint256 i = 0; i < 255; ++i) {
            uint256 invariantProduct = invariant;

            for (uint256 j = 0; j < nCurrencies; ++j) {
                invariantProduct = (invariantProduct * invariant) / _scaledReserves[j];
            }

            invariantProduct = invariantProduct / (nCurrencies ** nCurrencies);

            uint256 previousInvariant = invariant;

            // forgefmt: disable-next-item
            invariant = (
                (ampTimesCoins * totalReserves / AMP_PRECISION + invariantProduct * nCurrencies) * invariant
            ) / (
                (ampTimesCoins - AMP_PRECISION) * invariant / AMP_PRECISION + (nCurrencies + 1) * invariantProduct
            );

            if (invariant > previousInvariant) {
                if (invariant - previousInvariant <= 1) {
                    return invariant;
                }
            } else {
                if (previousInvariant - invariant <= 1) {
                    return invariant;
                }
            }
        }

        revert ConvergenceNotReached();
    }

    /// @notice Compute reserves[j] given reserves[i] = x and all other reserves.
    /// @dev Rearranges the invariant into a quadratic and applies Newton-Raphson.
    /// Solves: y^2 + y * (sum' - (A*n^n - 1) * D / (A * n^n)) = D^(n+1) / (n^(2n) * prod' * A)
    /// Which simplifies to: y^2 + linearCoefficient * y = constantTerm
    /// Solution: y = (y^2 + constantTerm) / (2*y + linearCoefficient)
    /// @param _inputIndex Index of the input coin (the one being swapped in).
    /// @param _outputIndex Index of the output coin (the one being calculated).
    /// @param _inputReserves New value of reserves[inputIndex] after swap.
    /// @param _reserves Current reserves array (scaled to 1e18 decimals).
    /// @param _amplification Amplification coefficient A.
    /// @param _invariant The invariant D that must be preserved.
    /// @return otherReserves The calculated reserves[outputIndex].
    function getOtherReserves(
        uint256 _inputIndex,
        uint256 _outputIndex,
        uint256 _inputReserves,
        uint256[] memory _reserves,
        uint256 _amplification,
        uint256 _invariant
    ) internal pure returns (uint256 otherReserves) {
        uint256 nCurrencies = _reserves.length;
        uint256 ampTimesCoins = _amplification * nCurrencies;

        // knownReservesSum = sum of all reserves except output
        // constantTerm = D^(n+1) / (n^n * prod(reserves except output) * A * n)
        uint256 knownReservesSum = 0;
        uint256 constantTerm = _invariant;

        for (uint256 k = 0; k < nCurrencies; ++k) {
            uint256 currentReserves;
            if (k == _inputIndex) {
                currentReserves = _inputReserves;
            } else if (k != _outputIndex) {
                currentReserves = _reserves[k];
            } else {
                continue;
            }
            knownReservesSum += currentReserves;
            constantTerm = constantTerm * _invariant / (currentReserves * nCurrencies);
        }

        constantTerm = constantTerm * _invariant * AMP_PRECISION / (ampTimesCoins * nCurrencies);
        // linearCoefficient = knownReservesSum + D / (A * n^n) - D
        uint256 linearCoefficient = knownReservesSum + _invariant * AMP_PRECISION / ampTimesCoins;

        otherReserves = _invariant;

        for (uint256 k = 0; k < 255; ++k) {
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

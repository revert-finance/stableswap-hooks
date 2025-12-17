// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/// @notice Library containing StableSwap mathematical functions for invariant and reserve calculations
library StableSwapMath {
    /// @dev Fixed-point precision (1e18) used when scaling token rates and amounts.
    uint256 internal constant RATE_PRECISION = 1e18;

    /// @dev Precision divisor for amplification coefficient calculations.
    uint256 internal constant AMP_PRECISION = 100;

    /// @notice Error thrown when Newton-Raphson iteration fails to converge within 255 iterations
    error ConvergenceNotReached();

    /// @notice Compute the stable swap invariant for the provided currency reserves.
    /// @dev Solves the StableSwap invariant equation using Newton-Raphson iteration:
    ///      A·n^n·Σx_i + D = A·D·n^n + D^(n+1) / (n^n·Πx_i)
    ///      where A is the amplification, n is the number of currencies, x_i are the reserves, and D is the invariant.
    ///      Converges when the difference between iterations is <= 1.
    /// @param _scaledReserves The array of scaled reserves.
    /// @param _amplification The amplification coefficient.
    /// @return invariant The converged invariant.
    function getInvariant(uint256[] memory _scaledReserves, uint256 _amplification)
        internal
        pure
        returns (uint256 invariant)
    {
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

    /// @notice Compute the target reserves for a swap given the new source reserves.
    /// @dev Solves for y in the quadratic derived from the StableSwap invariant using Newton-Raphson:
    ///      y^2 + y·(Σx' + D/(A·n^n) - D) = D^(n+1) / (n^n·Πx'·A·n)
    ///      where x' are the known reserves (excluding target), simplified to: y = (y^2 + c) / (2y + b - D)
    ///      Converges when the difference between iterations is <= 1.
    /// @param _source Index of the source currency (the one being swapped in).
    /// @param _target Index of the target currency (the one being swapped out).
    /// @param _sourceReserves New reserves for the source currency after the swap.
    /// @param _scaledReserves Current scaled reserves for all currencies.
    /// @param _amplification The amplification coefficient.
    /// @param _invariant The invariant that must be preserved.
    /// @return targetReserves The scaled reserves for the target currency.
    function getTargetReserves(
        uint256 _source,
        uint256 _target,
        uint256 _sourceReserves,
        uint256[] memory _scaledReserves,
        uint256 _amplification,
        uint256 _invariant
    ) internal pure returns (uint256 targetReserves) {
        uint256 nCurrencies = _scaledReserves.length;

        uint256 ampTimesCoins = _amplification * nCurrencies;

        uint256 knownReservesSum = 0;

        uint256 invariantProduct = _invariant;

        for (uint256 i = 0; i < nCurrencies; ++i) {
            uint256 reserves;

            if (i == _source) {
                reserves = _sourceReserves;
            } else if (i != _target) {
                reserves = _scaledReserves[i];
            } else {
                continue;
            }

            knownReservesSum += reserves;

            invariantProduct = invariantProduct * _invariant / (reserves * nCurrencies);
        }

        invariantProduct = invariantProduct * _invariant * AMP_PRECISION / (ampTimesCoins * nCurrencies);

        uint256 sumPlusInvariantRatio = knownReservesSum + _invariant * AMP_PRECISION / ampTimesCoins;

        targetReserves = _invariant;

        for (uint256 i = 0; i < 255; ++i) {
            uint256 previousTargetReserves = targetReserves;

            // forgefmt: disable-next-item
            targetReserves = (
                targetReserves * targetReserves + invariantProduct
            ) / (
                2 * targetReserves + sumPlusInvariantRatio - _invariant
            );

            if (targetReserves > previousTargetReserves) {
                if (targetReserves - previousTargetReserves <= 1) {
                    return targetReserves;
                }
            } else {
                if (previousTargetReserves - targetReserves <= 1) {
                    return targetReserves;
                }
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

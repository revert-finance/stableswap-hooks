// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Library containing StableSwap mathematical functions for invariant and reserve calculations
library StableSwapMath {
    /// @dev Fixed-point precision (1e18) used when scaling token rates and amounts.
    uint256 internal constant RATE_PRECISION = 1e18;

    /// @dev Precision divisor for amplification coefficient calculations.
    uint256 internal constant AMP_PRECISION = 100;

    /// @notice Error thrown when Newton-Raphson iteration fails to converge within 255 iterations
    error ConvergenceNotReached();

    /// @notice Error thrown when nthRoot is called with an unsupported degree (must be 2, 3, or 4)
    error InvalidDegree();

    /// @notice Compute the stable swap invariant for the provided currency reserves.
    /// @dev Solves the StableSwap invariant equation using Newton-Raphson iteration:
    ///      A·n^n·Σx_i + D = A·D·n^n + D^(n+1) / (n^n·Πx_i)
    ///      where A is the amplification, n is the number of currencies, x_i are the reserves, and D is the invariant.
    ///      Converges when the difference between iterations is <= 1.
    /// @param _scaledReserves The array of scaled reserves.
    /// @param _amplification The amplification coefficient.
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
    function scaleTo(uint256 _amount, uint256 _rate) internal pure returns (uint256) {
        return _rate * _amount / RATE_PRECISION;
    }

    /// @dev Converts a 1e18-precision amount back to token units using the given rate.
    /// @param _amount 1e18-scaled amount.
    /// @param _rate Scaling factor for the token.
    function descale(uint256 _amount, uint256 _rate) internal pure returns (uint256) {
        return _amount * RATE_PRECISION / _rate;
    }

    /// @dev Computes the scaling rate to normalize a currency's decimals to 1e18 precision.
    /// @dev For native ETH (address zero), returns 1e18 (18 decimals, no scaling needed).
    /// @dev For ERC20 tokens, returns 10^(36 - decimals) to scale token amounts to 1e18.
    /// @param _currency The currency to get the scaling rate for.
    function getRate(Currency _currency) internal view returns (uint256) {
        if (_currency.isAddressZero()) {
            return 1e18;
        }

        return 10 ** (36 - IERC20Metadata(Currency.unwrap(_currency)).decimals());
    }

    /// @notice Calculate the geometric mean of an array of values without overflow.
    /// @dev Uses different strategies based on array length to avoid overflow:
    ///      - 2 values: sqrt(a * b) using mulDiv for safe multiplication
    ///      - 3 values: cbrt(a) * cbrt(b) * cbrt(c) to avoid computing full product
    ///      - 4 values: sqrt(sqrt(a*b) * sqrt(c*d)) using pairwise approach
    /// @param _values Array of values (must be length 2, 3, or 4).
    function geometricMean(uint256[] memory _values) internal pure returns (uint256) {
        uint256 n = _values.length;

        if (n == 2) {
            // sqrt(a * b) - use mulDiv to handle large values safely
            return Math.sqrt(Math.mulDiv(_values[0], _values[1], 1));
        }

        if (n == 3) {
            // cbrt(a) * cbrt(b) * cbrt(c) = (a * b * c)^(1/3)
            // This avoids computing the full product which could overflow
            return cbrt(_values[0]) * cbrt(_values[1]) * cbrt(_values[2]);
        }

        if (n == 4) {
            // sqrt(sqrt(a*b) * sqrt(c*d)) = (a*b*c*d)^(1/4)
            // Pairwise approach reduces overflow risk significantly
            uint256 sqrt01 = Math.sqrt(Math.mulDiv(_values[0], _values[1], 1));
            uint256 sqrt23 = Math.sqrt(Math.mulDiv(_values[2], _values[3], 1));
            return Math.sqrt(Math.mulDiv(sqrt01, sqrt23, 1));
        }

        revert InvalidDegree();
    }

    /// @notice Returns the cube root of `x`, rounded down.
    /// @dev Obtained from Solady: https://github.com/Vectorized/solady/blob/v0.1.26/src/utils/FixedPointMathLib.sol
    /// @dev Formally verified by xuwinnie: https://github.com/vectorized/solady/blob/main/audits/xuwinnie-solady-cbrt-proof.pdf
    /// @param x The value to compute the cube root of.
    function cbrt(uint256 x) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            let r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffff, shr(r, x))))
            r := or(r, shl(3, lt(0xff, shr(r, x))))
            // Makeshift lookup table to nudge the approximate log2 result.
            z := div(shl(div(r, 3), shl(lt(0xf, shr(r, x)), 0xf)), xor(7, mod(r, 3)))
            // Newton-Raphson's.
            z := div(add(add(div(x, mul(z, z)), z), z), 3)
            z := div(add(add(div(x, mul(z, z)), z), z), 3)
            z := div(add(add(div(x, mul(z, z)), z), z), 3)
            z := div(add(add(div(x, mul(z, z)), z), z), 3)
            z := div(add(add(div(x, mul(z, z)), z), z), 3)
            z := div(add(add(div(x, mul(z, z)), z), z), 3)
            z := div(add(add(div(x, mul(z, z)), z), z), 3)
            // Round down.
            z := sub(z, lt(div(x, mul(z, z)), z))
        }
    }
}

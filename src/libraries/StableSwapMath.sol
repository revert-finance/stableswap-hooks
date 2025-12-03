// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title StableSwapMath
/// @notice Library for StableSwap AMM calculations (2-coin pools)
/// @dev Based on Curve's StableSwap invariant (Egorov, 2019)
///
/// The StableSwap invariant combines constant-sum and constant-product formulas:
///
///   A·n^n · Σx_i + D = A·D·n^n + D^(n+1) / (n^n · Πx_i)
///
/// Where:
///   - x_i = reserve balance of coin i
///   - n   = number of coins (N_COINS)
///   - D   = invariant, represents total value when all coins are balanced
///   - A   = amplification coefficient (higher = lower slippage near balance)
///
/// When A → 0:  behaves like constant-product (Uniswap: Πx_i = k)
/// When A → ∞:  behaves like constant-sum (x + y = k, zero slippage)
///
/// The amplification coefficient A acts as "leverage" - a typical value of A=100
/// provides ~100x less slippage than constant-product near the balance point.
///
/// Solutions for D and y are found iteratively using Newton-Raphson method.
library StableSwapMath {
    /// @dev Precision for amplification coefficient (A should be stored as A * A_PRECISION)
    uint256 internal constant A_PRECISION = 100;

    /// @dev Number of coins in the pool (n in the invariant formula)
    uint256 internal constant N_COINS = 2;

    error ConvergenceNotReached();

    /// @notice Calculate the StableSwap invariant D
    /// @dev Solves the StableSwap invariant equation for D given reserves.
    ///
    /// From the whitepaper, the invariant is:
    ///   A·n^n · Σx_i + D = A·D·n^n + D^(n+1) / (n^n · Πx_i)
    ///
    /// Rearranging for Newton-Raphson iteration:
    ///   D_new = (A·n^n · S + D_P · n) · D / ((A·n^n - 1) · D + (n + 1) · D_P)
    ///
    /// Where:
    ///   S   = Σx_i (sum of reserves)
    ///   D_P = D^(n+1) / (n^n · Πx_i) (product term from invariant)
    ///
    /// D represents the total liquidity when the pool is perfectly balanced.
    /// When reserves are equal, D = n · x (where x is each reserve).
    ///
    /// @param x0 Precision-adjusted reserves of token 0
    /// @param x1 Precision-adjusted reserves of token 1
    /// @param A Amplification coefficient
    /// @return D The invariant
    function getD(uint256 x0, uint256 x1, uint256 A) internal pure returns (uint256) {
        // S = Σx_i (sum of all reserves)
        uint256 S = x0 + x1;

        // Empty pool has zero invariant
        if (S == 0) {
            return 0;
        }

        // Initial guess: D = S (assumes balanced pool)
        uint256 D = S;

        // Ann = A·n^n (amplification scaled by number of coins)
        uint256 ann = A * N_COINS;

        // Newton-Raphson iteration to find D
        for (uint256 i = 0; i < 255; ++i) {
            // D_P = D^(n+1) / (n^n · Πx_i)
            // This is the "product" part of the invariant that pulls toward constant-product behavior
            uint256 dP = D;
            dP = (dP * D) / x0;
            dP = (dP * D) / x1;
            dP = dP / (N_COINS * N_COINS);

            uint256 dPrev = D;

            // Newton-Raphson step:
            // D = (Ann · S / precision + dP · n) · D / ((Ann - precision) · D / precision + (n+1) · dP)
            uint256 numerator = ((ann * S) / A_PRECISION + dP * N_COINS) * D;
            uint256 denominator = ((ann - A_PRECISION) * D) / A_PRECISION + (N_COINS + 1) * dP;
            D = numerator / denominator;

            // Convergence check: stop when D changes by ≤ 1 wei
            if (D > dPrev) {
                if (D - dPrev <= 1) return D;
            } else {
                if (dPrev - D <= 1) return D;
            }
        }

        revert ConvergenceNotReached();
    }

    /// @notice Calculate the unspecified reserve given the specified reserve and invariant
    /// @dev Solves for y (unknown reserve) when x (known reserve) and D are fixed.
    ///
    /// From the invariant, for n=2 coins with known x and unknown y:
    ///   A·n^n·(x + y) + D = A·D·n^n + D^3 / (n^n · x · y)
    ///
    /// Rearranging into quadratic form for Newton-Raphson:
    ///   y^2 + (x + D/A·n^n - D)·y = D^3 / (A · n^2n · x)
    ///
    /// Which gives iteration:
    ///   y_new = (y^2 + c) / (2y + b - D)
    ///
    /// Where:
    ///   c = D^3 / (A · n^2n · x)  (constant term)
    ///   b = x + D / (A · n^n)     (linear coefficient)
    ///
    /// This is used during swaps: given input amount changes x, find new y.
    /// The difference (old_y - new_y) is the output amount.
    ///
    /// @param x The known reserve amount after swap (precision-adjusted)
    /// @param A Amplification coefficient
    /// @param D The invariant (must remain constant during swap)
    /// @return y The calculated reserve for the other token
    function getY(uint256 x, uint256 A, uint256 D) internal pure returns (uint256 y) {
        // Ann = A·n^n
        uint256 ann = A * N_COINS;

        // c = D^3 / (Ann · n^n · x)
        // Computed as: (D^2 / (x · n)) · (D · precision / (Ann · n))
        uint256 c = (D * D) / (x * N_COINS);
        c = (c * D * A_PRECISION) / (ann * N_COINS);

        // b = x + D · precision / ann
        uint256 b = x + (D * A_PRECISION) / ann;

        // Initial guess: y = D (assumes near-balanced state)
        y = D;

        // Newton-Raphson iteration to find y
        for (uint256 i = 0; i < 255; ++i) {
            uint256 yPrev = y;

            // Newton step: y = (y² + c) / (2y + b - D)
            y = (y * y + c) / (2 * y + b - D);

            // Convergence check: stop when y changes by ≤ 1 wei
            if (y > yPrev) {
                if (y - yPrev <= 1) return y;
            } else {
                if (yPrev - y <= 1) return y;
            }
        }

        revert ConvergenceNotReached();
    }
}

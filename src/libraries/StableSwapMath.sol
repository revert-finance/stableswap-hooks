// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title StableSwapMath
/// @notice Library for StableSwap AMM calculations (2-coin pools)
/// @dev Based on Curve's StableSwap invariant with amplification coefficient
library StableSwapMath {
    uint256 internal constant A_PRECISION = 100;
    uint256 internal constant N_COINS = 2;
    uint256 internal constant RATE_PRECISION = 1e18;
    uint256 internal constant FEE_DENOMINATOR = 1e6;

    error ConvergenceNotReached();

    /// @notice Calculate the StableSwap invariant D
    /// @param xp0 Precision-adjusted balance of token 0
    /// @param xp1 Precision-adjusted balance of token 1
    /// @param amp Amplification coefficient
    /// @return D The invariant
    function getD(uint256 xp0, uint256 xp1, uint256 amp) internal pure returns (uint256) {
        uint256 S = xp0 + xp1;
        if (S == 0) return 0;

        uint256 D = S;
        uint256 Ann = amp * N_COINS;

        for (uint256 i = 0; i < 255; ++i) {
            uint256 D_P = D;

            D_P = (D_P * D) / xp0;
            D_P = (D_P * D) / xp1;

            D_P = D_P / (N_COINS * N_COINS);

            uint256 D_prev = D;

            // (Ann * S / A_PRECISION + D_P * N_COINS) * D / ((Ann - A_PRECISION) * D / A_PRECISION + (N_COINS + 1) * D_P)
            D = (((Ann * S) / A_PRECISION + D_P * N_COINS) * D)
                / (((Ann - A_PRECISION) * D) / A_PRECISION + (N_COINS + 1) * D_P);

            if (D > D_prev) {
                if (D - D_prev <= 1) {
                    return D;
                }
            } else {
                if (D_prev - D <= 1) {
                    return D;
                }
            }
        }

        revert ConvergenceNotReached();
    }

    /// @notice Calculate y given x for the StableSwap invariant
    /// @param x The known balance (precision-adjusted)
    /// @param amp Amplification coefficient
    /// @param D The invariant
    /// @return y The calculated balance for the other token
    function getY(uint256 x, uint256 amp, uint256 D) internal pure returns (uint256) {
        uint256 Ann = amp * N_COINS;

        // c = D^(n+1) / (n^n * prod(x_i) * Ann)
        uint256 c = (D * D) / (x * N_COINS);
        c = (c * D * A_PRECISION) / (Ann * N_COINS);

        // b = S_ + D / Ann
        uint256 b = x + (D * A_PRECISION) / Ann;

        uint256 y = D;

        for (uint256 i = 0; i < 255; ++i) {
            uint256 y_prev = y;
            y = (y * y + c) / (2 * y + b - D);

            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                }
            } else {
                if (y_prev - y <= 1) {
                    return y;
                }
            }
        }

        revert ConvergenceNotReached();
    }

    /// @notice Calculate output amount for exact input swap
    /// @param xpIn Precision-adjusted reserve of input token
    /// @param xpOut Precision-adjusted reserve of output token
    /// @param amountIn Amount of input token (in real units)
    /// @param rateIn Rate multiplier for input token
    /// @param rateOut Rate multiplier for output token
    /// @param amp Amplification coefficient
    /// @param D Invariant D
    /// @param fee Fee in parts per FEE_DENOMINATOR
    /// @return amountOut Amount of output token (positive = user receives)
    function swapExactInput(
        uint256 xpIn,
        uint256 xpOut,
        uint256 amountIn,
        uint256 rateIn,
        uint256 rateOut,
        uint256 amp,
        uint256 D,
        uint256 fee
    ) internal pure returns (uint256 amountOut) {
        // Convert input amount to precision units and add to reserves
        uint256 xIn = xpIn + (amountIn * rateIn) / RATE_PRECISION;

        uint256 xOut = getY(xIn, amp, D);

        // Subtract 1 to round in favor of the pool
        uint256 dyGross = xpOut - xOut - 1;

        // Apply fee to the output amount
        uint256 dyFee = (dyGross * fee) / FEE_DENOMINATOR;
        uint256 dyNet = dyGross - dyFee;

        // Convert from precision units to real token units
        amountOut = (dyNet * RATE_PRECISION) / rateOut;
    }

    /// @notice Calculate input amount for exact output swap
    /// @param xpIn Precision-adjusted reserve of input token
    /// @param xpOut Precision-adjusted reserve of output token
    /// @param amountOut Desired amount of output token (in real units)
    /// @param rateIn Rate multiplier for input token
    /// @param rateOut Rate multiplier for output token
    /// @param amp Amplification coefficient
    /// @param D Invariant D
    /// @param fee Fee in parts per FEE_DENOMINATOR
    /// @return amountIn Amount of input token required (user pays)
    function swapExactOutput(
        uint256 xpIn,
        uint256 xpOut,
        uint256 amountOut,
        uint256 rateIn,
        uint256 rateOut,
        uint256 amp,
        uint256 D,
        uint256 fee
    ) internal pure returns (uint256 amountIn) {
        // Convert desired output to precision units
        uint256 dyNet = (amountOut * rateOut) / RATE_PRECISION;

        // Calculate gross output needed (before fee)
        uint256 dyGross = (dyNet * FEE_DENOMINATOR) / (FEE_DENOMINATOR - fee);

        // Calculate new output reserve after removing gross output
        uint256 xOut = xpOut - dyGross;

        // Calculate required input reserve
        uint256 xIn = getY(xOut, amp, D);

        // Calculate required input amount (in precision units)
        uint256 dxRequired = xIn - xpIn;

        // Convert from precision units to real token units
        amountIn = (dxRequired * RATE_PRECISION) / rateIn;
    }
}

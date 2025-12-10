// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

import {Fees} from "src/Fees.sol";
import {StableSwapMath} from "src/libraries/StableSwapMath.sol";

/// @notice Abstract contract implementing StableSwap (Curve-style) swap logic as a Uniswap v4 hook
abstract contract Swap is Fees {
    /// @notice Hook called before a swap is executed
    /// @dev Validates the pool and calculates the swap using the StableSwap invariant
    /// @param _poolKey The pool key identifying the pool
    /// @param _params The swap parameters containing direction, amount, and sqrt price limit
    /// @return bytes4 The function selector to indicate successful hook execution
    /// @return BeforeSwapDelta The delta amounts for specified and unspecified tokens
    /// @return uint24 The LP fee override (0 = use pool's default fee)
    function _beforeSwap(address, PoolKey calldata _poolKey, SwapParams calldata _params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _validatePoolId(_poolKey);

        BeforeSwapDelta delta = toBeforeSwapDelta(-SafeCast.toInt128(_params.amountSpecified), _swap(_params));

        return (this.beforeSwap.selector, delta, 0);
    }

    /// @notice Executes a swap using the StableSwap invariant
    /// @param _params The swap parameters from Uniswap v4
    /// @return The unspecified delta amount
    function _swap(SwapParams calldata _params) private returns (int128) {
        // Scale reserves to 1e18 precision for consistent math across different token decimals
        uint256 scaledReserves0 = StableSwapMath.scaleTo(reserves0, rate0);
        uint256 scaledReserves1 = StableSwapMath.scaleTo(reserves1, rate1);

        // Get current amplification coefficient and compute the StableSwap invariant D
        uint256 amp = _currentAmp();
        uint256 invariant = StableSwapMath.getInvariant(scaledReserves0, scaledReserves1, amp);

        // Determine swap type: exact input (negative) vs exact output (positive)
        bool isExactInput = _params.amountSpecified < 0;

        uint256 unspecifiedAmount;

        // zeroForOne: swapping currency0 -> currency1
        if (_params.zeroForOne) {
            if (isExactInput) {
                // Exact input: user specifies input amount, we calculate output
                uint256 amountSpecified = uint256(-_params.amountSpecified);

                // Calculate new reserves after adding input, then derive output from invariant
                uint256 newScaledReserves0 = scaledReserves0 + StableSwapMath.scaleTo(amountSpecified, rate0);
                uint256 newScaledReserves1 = StableSwapMath.getOtherReserves(newScaledReserves0, amp, invariant);
                uint256 output = StableSwapMath.descale(scaledReserves1 - newScaledReserves1, rate1);

                // Calculate and track fees (fees taken from output in currency1)
                (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = _getFees(output);
                _addFees(false, protocolFees, hookFees);
                uint256 outputMinusFees = output - lpFees - hookFees - protocolFees;

                // Update pool manager accounting: burn output claims, mint input claims
                poolManager.burn(address(this), currency1.toId(), outputMinusFees);
                poolManager.mint(address(this), currency0.toId(), amountSpecified);

                // Update local reserves (LP fees stay in reserves)
                reserves0 += amountSpecified;
                reserves1 -= output - lpFees;

                unspecifiedAmount = outputMinusFees;
            } else {
                // Exact output: user specifies output amount, we calculate required input
                uint256 amountSpecified = uint256(_params.amountSpecified);

                // Calculate new reserves after removing output, then derive input from invariant
                uint256 newScaledReserves1 = scaledReserves1 - StableSwapMath.scaleTo(amountSpecified, rate1);
                uint256 newScaledReserves0 = StableSwapMath.getOtherReserves(newScaledReserves1, amp, invariant);
                uint256 input = StableSwapMath.descale(newScaledReserves0 - scaledReserves0, rate0);

                // Calculate and track fees (fees added to input in currency0)
                (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = _getFees(input);
                _addFees(true, protocolFees, hookFees);
                uint256 inputPlusFees = input + lpFees + hookFees + protocolFees;

                // Update pool manager accounting: burn output claims, mint input claims
                poolManager.burn(address(this), currency1.toId(), amountSpecified);
                poolManager.mint(address(this), currency0.toId(), inputPlusFees);

                // Update local reserves (LP fees stay in reserves)
                reserves0 += input + lpFees;
                reserves1 -= amountSpecified;

                unspecifiedAmount = inputPlusFees;
            }
        } else {
            // oneForZero: swapping currency1 -> currency0
            if (isExactInput) {
                // Exact input: user specifies input amount, we calculate output
                uint256 amountSpecified = uint256(-_params.amountSpecified);

                // Calculate new reserves after adding input, then derive output from invariant
                uint256 newScaledReserves1 = scaledReserves1 + StableSwapMath.scaleTo(amountSpecified, rate1);
                uint256 newScaledReserves0 = StableSwapMath.getOtherReserves(newScaledReserves1, amp, invariant);
                uint256 output = StableSwapMath.descale(scaledReserves0 - newScaledReserves0, rate0);

                // Calculate and track fees (fees taken from output in currency0)
                (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = _getFees(output);
                _addFees(true, protocolFees, hookFees);
                uint256 outputMinusFees = output - lpFees - hookFees - protocolFees;

                // Update pool manager accounting: burn output claims, mint input claims
                poolManager.burn(address(this), currency0.toId(), outputMinusFees);
                poolManager.mint(address(this), currency1.toId(), amountSpecified);

                // Update local reserves (LP fees stay in reserves)
                reserves1 += amountSpecified;
                reserves0 -= output - lpFees;

                unspecifiedAmount = outputMinusFees;
            } else {
                // Exact output: user specifies output amount, we calculate required input
                uint256 amountSpecified = uint256(_params.amountSpecified);

                // Calculate new reserves after removing output, then derive input from invariant
                uint256 newScaledReserves0 = scaledReserves0 - StableSwapMath.scaleTo(amountSpecified, rate0);
                uint256 newScaledReserves1 = StableSwapMath.getOtherReserves(newScaledReserves0, amp, invariant);
                uint256 input = StableSwapMath.descale(newScaledReserves1 - scaledReserves1, rate1);

                // Calculate and track fees (fees added to input in currency1)
                (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = _getFees(input);
                _addFees(false, protocolFees, hookFees);
                uint256 inputPlusFees = input + lpFees + hookFees + protocolFees;

                // Update pool manager accounting: burn output claims, mint input claims
                poolManager.burn(address(this), currency0.toId(), amountSpecified);
                poolManager.mint(address(this), currency1.toId(), inputPlusFees);

                // Update local reserves (LP fees stay in reserves)
                reserves1 += input + lpFees;
                reserves0 -= amountSpecified;

                unspecifiedAmount = inputPlusFees;
            }
        }

        int128 unspecifiedDelta = SafeCast.toInt128(SafeCast.toInt256(unspecifiedAmount));

        // Return delta with correct sign: negative for exact input (hook pays), positive for exact output (hook receives)
        return isExactInput ? -unspecifiedDelta : unspecifiedDelta;
    }
}

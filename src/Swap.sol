// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {Amp} from "src/Amp.sol";
import {Fees} from "src/Fees.sol";
import {StableSwapMath} from "src/libraries/StableSwapMath.sol";

/// @notice Abstract contract implementing StableSwap (Curve-style) swap logic as a Uniswap v4 hook
abstract contract Swap is Amp, Fees {
    /// @notice Thrown when the swap is attempted on a pool that doesn't match this hook's poolId
    error InvalidPoolId();

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
        if (PoolId.unwrap(poolId) != PoolId.unwrap(_poolKey.toId())) {
            revert InvalidPoolId();
        }

        BeforeSwapDelta delta = toBeforeSwapDelta(-SafeCast.toInt128(_params.amountSpecified), _swap(_params));

        return (this.beforeSwap.selector, delta, 0);
    }

    /// @notice Executes a swap using the StableSwap invariant
    /// @param _params The swap parameters from Uniswap v4
    /// @return The unspecified delta amount
    function _swap(SwapParams calldata _params) private returns (int128) {
        uint256 scaledReserves0 = StableSwapMath.scaleTo(reserves0, rate0);
        uint256 scaledReserves1 = StableSwapMath.scaleTo(reserves1, rate1);
        uint256 amp = _currentAmp();
        uint256 invariant = StableSwapMath.getInvariant(scaledReserves0, scaledReserves1, amp);
        bool isExactInput = _params.amountSpecified < 0;

        uint256 unspecifiedAmount;

        if (_params.zeroForOne) {
            if (isExactInput) {
                uint256 amountSpecified = uint256(-_params.amountSpecified);
                uint256 newScaledReserves0 = scaledReserves0 + StableSwapMath.scaleTo(amountSpecified, rate0);
                uint256 newScaledReserves1 = StableSwapMath.getOtherReserves(newScaledReserves0, amp, invariant);
                uint256 output = StableSwapMath.descale(scaledReserves1 - newScaledReserves1, rate1);
                (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = _getFees(output);
                _addFees(false, protocolFees, hookFees);
                uint256 outputMinusFees = output - lpFees - hookFees - protocolFees;
                poolManager.burn(address(this), currency1.toId(), outputMinusFees);
                poolManager.mint(address(this), currency0.toId(), amountSpecified);
                reserves0 += amountSpecified;
                reserves1 -= output - lpFees;

                unspecifiedAmount = outputMinusFees;
            } else {
                uint256 amountSpecified = uint256(_params.amountSpecified);
                uint256 newScaledReserves1 = scaledReserves1 - StableSwapMath.scaleTo(amountSpecified, rate1);
                uint256 newScaledReserves0 = StableSwapMath.getOtherReserves(newScaledReserves1, amp, invariant);
                uint256 input = StableSwapMath.descale(newScaledReserves0 - scaledReserves0, rate0);
                (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = _getFees(input);
                _addFees(true, protocolFees, hookFees);
                uint256 inputPlusFees = input + lpFees + hookFees + protocolFees;
                poolManager.burn(address(this), currency1.toId(), amountSpecified);
                poolManager.mint(address(this), currency0.toId(), inputPlusFees);
                reserves0 += input + lpFees;
                reserves1 -= amountSpecified;

                unspecifiedAmount = inputPlusFees;
            }
        } else {
            if (isExactInput) {
                uint256 amountSpecified = uint256(-_params.amountSpecified);
                uint256 newScaledReserves1 = scaledReserves1 + StableSwapMath.scaleTo(amountSpecified, rate1);
                uint256 newScaledReserves0 = StableSwapMath.getOtherReserves(newScaledReserves1, amp, invariant);
                uint256 output = StableSwapMath.descale(scaledReserves0 - newScaledReserves0, rate0);
                (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = _getFees(output);
                _addFees(true, protocolFees, hookFees);
                uint256 outputMinusFees = output - lpFees - hookFees - protocolFees;
                poolManager.burn(address(this), currency0.toId(), outputMinusFees);
                poolManager.mint(address(this), currency1.toId(), amountSpecified);
                reserves1 += amountSpecified;
                reserves0 -= output - lpFees;

                unspecifiedAmount = outputMinusFees;
            } else {
                uint256 amountSpecified = uint256(_params.amountSpecified);
                uint256 newScaledReserves0 = scaledReserves0 - StableSwapMath.scaleTo(amountSpecified, rate0);
                uint256 newScaledReserves1 = StableSwapMath.getOtherReserves(newScaledReserves0, amp, invariant);
                uint256 input = StableSwapMath.descale(newScaledReserves1 - scaledReserves1, rate1);
                (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = _getFees(input);
                _addFees(false, protocolFees, hookFees);
                uint256 inputPlusFees = input + lpFees + hookFees + protocolFees;
                poolManager.burn(address(this), currency0.toId(), amountSpecified);
                poolManager.mint(address(this), currency1.toId(), inputPlusFees);
                reserves1 += input + lpFees;
                reserves0 -= amountSpecified;

                unspecifiedAmount = inputPlusFees;
            }
        }

        int128 unspecifiedDelta = SafeCast.toInt128(SafeCast.toInt256(unspecifiedAmount));

        return isExactInput ? -unspecifiedDelta : unspecifiedDelta;
    }
}

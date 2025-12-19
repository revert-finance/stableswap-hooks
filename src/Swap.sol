// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

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

        BeforeSwapDelta delta = toBeforeSwapDelta(-SafeCast.toInt128(_params.amountSpecified), _swap(_poolKey, _params));

        return (this.beforeSwap.selector, delta, 0);
    }

    /// @notice Executes a swap using the StableSwap invariant
    /// @dev Handles both exact input (amountSpecified < 0) and exact output (amountSpecified > 0) swaps.
    ///      Fees are deducted from output for exact input, or added to input for exact output.
    /// @param _poolKey The pool key identifying the currencies being swapped
    /// @param _params The swap parameters from Uniswap v4
    /// @return The unspecified delta amount (negative for exact input, positive for exact output)
    function _swap(PoolKey calldata _poolKey, SwapParams calldata _params) private returns (int128) {
        uint256 index0 = getCurrencyIndex(_poolKey.currency0);
        uint256 index1 = getCurrencyIndex(_poolKey.currency1);

        uint256[] memory scaledReserves = new uint256[](currenciesLength);

        for (uint256 i = 0; i < currenciesLength; ++i) {
            scaledReserves[i] = StableSwapMath.scaleTo(reserves[i], _getRate(i));
        }

        uint256 amp = _currentAmp();

        uint256 invariant = StableSwapMath.getInvariant(scaledReserves, amp);

        uint256 increasedIndex;
        uint256 decreasedIndex;

        if (_params.zeroForOne) {
            increasedIndex = index0;
            decreasedIndex = index1;
        } else {
            increasedIndex = index1;
            decreasedIndex = index0;
        }

        uint256 unspecifiedAmount;

        if (_params.amountSpecified < 0) {
            uint256 amountSpecified = uint256(-_params.amountSpecified);

            uint256 increasedReserves =
                scaledReserves[increasedIndex] + StableSwapMath.scaleTo(amountSpecified, _getRate(increasedIndex));

            uint256 decreasedReserves = StableSwapMath.getTargetReserves(
                increasedIndex, decreasedIndex, increasedReserves, scaledReserves, amp, invariant
            );

            uint256 decreased =
                StableSwapMath.descale(scaledReserves[decreasedIndex] - decreasedReserves, _getRate(decreasedIndex));

            (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = _getFees(decreased);

            _addFees(decreasedIndex, protocolFees, hookFees);

            uint256 decreasedMinusFees = decreased - lpFees - hookFees - protocolFees;

            poolManager.burn(address(this), currencies[decreasedIndex].toId(), decreasedMinusFees);
            poolManager.mint(address(this), currencies[increasedIndex].toId(), amountSpecified);

            reserves[increasedIndex] += amountSpecified;
            reserves[decreasedIndex] -= decreased - lpFees;

            unspecifiedAmount = decreasedMinusFees;
        } else {
            uint256 amountSpecified = uint256(_params.amountSpecified);

            uint256 decreasedReserves =
                scaledReserves[decreasedIndex] - StableSwapMath.scaleTo(amountSpecified, _getRate(decreasedIndex));

            uint256 increasedReserves = StableSwapMath.getTargetReserves(
                decreasedIndex, increasedIndex, decreasedReserves, scaledReserves, amp, invariant
            );

            uint256 increased =
                StableSwapMath.descale(increasedReserves - scaledReserves[increasedIndex], _getRate(increasedIndex));

            (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = _getFees(increased);

            _addFees(increasedIndex, protocolFees, hookFees);

            uint256 increasedPlusFees = increased + lpFees + hookFees + protocolFees;

            poolManager.burn(address(this), currencies[decreasedIndex].toId(), amountSpecified);
            poolManager.mint(address(this), currencies[increasedIndex].toId(), increasedPlusFees);

            reserves[increasedIndex] += increased + lpFees;
            reserves[decreasedIndex] -= amountSpecified;

            unspecifiedAmount = increasedPlusFees;
        }

        int128 unspecifiedDelta = SafeCast.toInt128(SafeCast.toInt256(unspecifiedAmount));

        return _params.amountSpecified < 0 ? -unspecifiedDelta : unspecifiedDelta;
    }
}

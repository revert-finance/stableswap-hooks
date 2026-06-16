// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Fees} from "src/Fees.sol";
import {StableSwapMath} from "src/libraries/StableSwapMath.sol";

/// @notice Implements StableSwap (Curve-style) swap logic as a Uniswap v4 hook
/// @dev Supports both exact input and exact output swaps using the StableSwap invariant
abstract contract Swap is Fees {
    /// @dev Swap execution context containing pool state
    struct SwapContext {
        uint256 tokenInIndex;
        uint256 tokenOutIndex;
        uint256[] scaledReserves;
        uint256 amp;
        uint256 invariant;
    }

    /// @dev Result of a swap containing amounts and fee breakdown
    struct SwapResult {
        uint256 amountIn;
        uint256 amountOut;
        uint256 lpFees;
        uint256 hookFees;
        uint256 protocolFees;
    }

    /// @notice Error thrown when an exact-output swap would require zero input
    error ZeroInput();

    /// @notice Emitted when a swap is executed
    event StableSwap(
        address indexed _sender,
        Currency indexed _currencyIn,
        Currency indexed _currencyOut,
        uint256 _amountIn,
        uint256 _amountOut,
        uint256 _lpFees,
        uint256 _hookFees,
        uint256 _protocolFees
    );

    /// @dev Hook called before a swap, executes the StableSwap logic
    function _beforeSwap(address _sender, PoolKey calldata _poolKey, SwapParams calldata _params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _validatePoolId(_poolKey);

        BeforeSwapDelta delta =
            toBeforeSwapDelta(-SafeCast.toInt128(_params.amountSpecified), _swap(_sender, _poolKey, _params));

        return (this.beforeSwap.selector, delta, 0);
    }

    /// @dev Executes a swap and emits the StableSwap event
    function _swap(address _sender, PoolKey calldata _poolKey, SwapParams calldata _params) private returns (int128) {
        SwapContext memory ctx = _createSwapContext(_poolKey, _params.zeroForOne);

        bool isExactInput = _params.amountSpecified < 0;

        uint256 specifiedAmount = isExactInput ? uint256(-_params.amountSpecified) : uint256(_params.amountSpecified);

        SwapResult memory result =
            isExactInput ? _swapExactInput(specifiedAmount, ctx) : _swapExactOutput(specifiedAmount, ctx);

        _checkInvariant();

        emit StableSwap(
            _sender,
            currencies[ctx.tokenInIndex],
            currencies[ctx.tokenOutIndex],
            result.amountIn,
            result.amountOut,
            result.lpFees,
            result.hookFees,
            result.protocolFees
        );

        uint256 unspecifiedAmount = isExactInput ? result.amountOut : result.amountIn;
        int128 unspecifiedDelta = SafeCast.toInt128(SafeCast.toInt256(unspecifiedAmount));

        return isExactInput ? -unspecifiedDelta : unspecifiedDelta;
    }

    /// @dev Builds the swap context with scaled reserves, amp, and invariant
    function _createSwapContext(PoolKey calldata _poolKey, bool _zeroForOne)
        private
        view
        returns (SwapContext memory ctx)
    {
        uint256 index0 = getCurrencyIndex(_poolKey.currency0);
        uint256 index1 = getCurrencyIndex(_poolKey.currency1);

        (ctx.tokenInIndex, ctx.tokenOutIndex) = _zeroForOne ? (index0, index1) : (index1, index0);

        ctx.scaledReserves = new uint256[](currenciesLength);
        for (uint256 i = 0; i < currenciesLength; ++i) {
            ctx.scaledReserves[i] = StableSwapMath.scaleTo(reserves[i], _getRate(i));
        }

        ctx.amp = getCurrentAmp();
        ctx.invariant = StableSwapMath.getInvariant(ctx.scaledReserves, ctx.amp);
    }

    /// @dev Calculates output amount for exact input swap, fees deducted from output
    function _swapExactInput(uint256 _amountIn, SwapContext memory _ctx) private returns (SwapResult memory result) {
        uint256 newTokenInReserves =
            _ctx.scaledReserves[_ctx.tokenInIndex] + StableSwapMath.scaleTo(_amountIn, _getRate(_ctx.tokenInIndex));

        uint256 newTokenOutReserves = StableSwapMath.getTargetReserves(
            _ctx.tokenInIndex, _ctx.tokenOutIndex, newTokenInReserves, _ctx.scaledReserves, _ctx.amp, _ctx.invariant
        );

        uint256 rawAmountOut = StableSwapMath.descale(
            _ctx.scaledReserves[_ctx.tokenOutIndex] - newTokenOutReserves, _getRate(_ctx.tokenOutIndex)
        );

        (result.lpFees, result.hookFees, result.protocolFees) = _getFees(rawAmountOut);
        uint256 totalFees = result.lpFees + result.hookFees + result.protocolFees;

        result.amountIn = _amountIn;
        result.amountOut = rawAmountOut - totalFees;

        _settleTrade(_ctx, result, true);
    }

    /// @dev Calculates input amount for exact output swap, fees grossed up into the input
    function _swapExactOutput(uint256 _amountOut, SwapContext memory _ctx) private returns (SwapResult memory result) {
        uint256 newTokenOutReserves = _ctx.scaledReserves[_ctx.tokenOutIndex]
            - StableSwapMath.scaleToUp(_amountOut, _getRate(_ctx.tokenOutIndex));

        uint256 newTokenInReserves = StableSwapMath.getTargetReserves(
            _ctx.tokenOutIndex, _ctx.tokenInIndex, newTokenOutReserves, _ctx.scaledReserves, _ctx.amp, _ctx.invariant
        );

        uint256 rawAmountIn = StableSwapMath.descaleUp(
            newTokenInReserves - _ctx.scaledReserves[_ctx.tokenInIndex], _getRate(_ctx.tokenInIndex)
        );

        uint256 grossAmountIn =
            Math.mulDiv(rawAmountIn, FEE_PRECISION, FEE_PRECISION - lpFeePercentage, Math.Rounding.Ceil);

        (result.lpFees, result.hookFees, result.protocolFees) = _getFees(grossAmountIn);

        result.amountIn = grossAmountIn;
        result.amountOut = _amountOut;

        if (result.amountIn == 0) {
            revert ZeroInput();
        }

        _settleTrade(_ctx, result, false);
    }

    /// @dev Settles the trade by updating pool manager claims and reserves
    function _settleTrade(SwapContext memory _ctx, SwapResult memory _result, bool _isExactInput) private {
        if (_isExactInput) {
            _addFees(_ctx.tokenOutIndex, _result.protocolFees, _result.hookFees);

            poolManager.burn(address(this), currencies[_ctx.tokenOutIndex].toId(), _result.amountOut);
            poolManager.mint(address(this), currencies[_ctx.tokenInIndex].toId(), _result.amountIn);

            reserves[_ctx.tokenInIndex] += _result.amountIn;
            reserves[_ctx.tokenOutIndex] -= _result.amountOut + _result.hookFees + _result.protocolFees;
        } else {
            _addFees(_ctx.tokenInIndex, _result.protocolFees, _result.hookFees);

            poolManager.burn(address(this), currencies[_ctx.tokenOutIndex].toId(), _result.amountOut);
            poolManager.mint(address(this), currencies[_ctx.tokenInIndex].toId(), _result.amountIn);

            reserves[_ctx.tokenInIndex] += _result.amountIn - _result.hookFees - _result.protocolFees;
            reserves[_ctx.tokenOutIndex] -= _result.amountOut;
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStableSwapHooks} from "src/interfaces/IStableSwapHooks.sol";
import {IStableSwapHooksFactory} from "src/interfaces/IStableSwapHooksFactory.sol";
import {StableSwapMath} from "src/libraries/StableSwapMath.sol";

/// @notice Swap for zapIn execution (minimal struct for gas efficiency)
/// @param tokenInIndex Index of the input token in the pool's currencies array
/// @param tokenOutIndex Index of the output token in the pool's currencies array
/// @param amountIn Amount of input token to swap
struct Swap {
    uint256 tokenInIndex;
    uint256 tokenOutIndex;
    uint256 amountIn;
}

/// @notice Quote result from quoteZapIn (includes expected output for off-chain use)
/// @param tokenInIndex Index of the input token in the pool's currencies array
/// @param tokenOutIndex Index of the output token in the pool's currencies array
/// @param amountIn Amount of input token to swap
/// @param expectedAmountOut Expected amount of output token (for quote/display purposes)
struct SwapQuote {
    uint256 tokenInIndex;
    uint256 tokenOutIndex;
    uint256 amountIn;
    uint256 expectedAmountOut;
}

/// @dev Context for swap calculations (all values in scaled 1e18 precision)
/// @param scaledInputs User input amounts scaled by rate
/// @param scaledReserves Pool reserves scaled by rate
/// @param rates Dynamic rates for each currency (includes oracle rates)
/// @param lpFee Gross LP fee percentage (in FEE_PRECISION units)
/// @param hookFee Hook fee share of gross LP fees (in FEE_PRECISION units)
/// @param protocolFee Protocol fee share of gross LP fees (in FEE_PRECISION units)
/// @param amp Current amplification coefficient
struct SwapCalcContext {
    uint256[] scaledInputs;
    uint256[] scaledReserves;
    uint256[] rates;
    uint256 lpFee;
    uint256 hookFee;
    uint256 protocolFee;
    uint256 amp;
}

/// @title StableSwapZapIn
/// @notice Periphery contract for adding liquidity with arbitrary token amounts
/// @dev User must approve this contract to spend their tokens. This contract calculates
/// optimal swaps to balance deposits and executes them atomically via PoolManager.
/// @dev Security: zapIn is reentrancy-guarded before user tokens are pulled; PoolManager's lock protects swap callbacks.
/// The contract does not hold user funds between transactions.
contract StableSwapZapIn is IUnlockCallback, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Precision for rate calculations
    uint256 private constant RATE_PRECISION = 1e18;

    /// @dev Precision for fee calculations (matches pool's FEE_PRECISION)
    uint256 private constant FEE_PRECISION = 1e6;

    /// @dev Sentinel value for pools that do not include native ETH
    uint256 private constant NO_NATIVE_INDEX = type(uint256).max;

    /// @dev Maximum imbalance delta tolerated before scheduling another balancing swap (0.001% in RATE_PRECISION units)
    uint256 private constant IMBALANCE_THRESHOLD = 1e13;

    /// @notice The Uniswap v4 PoolManager contract
    IPoolManager public immutable poolManager;

    /// @notice Trusted factory used to validate hook provenance
    IStableSwapHooksFactory public immutable factory;

    /// @notice StableSwapHooks creation-code hash expected from the trusted factory
    bytes32 public immutable hooksCreationCodeHash;

    /// @notice Emitted when liquidity is added via zap
    /// @param sender User who performed the zap
    /// @param hooks StableSwap hook the liquidity was added to
    /// @param inputAmounts Raw input amounts provided to `zapIn`
    /// @param usedAmounts Amount of each originally supplied currency that was consumed.
    /// Tokens produced by swaps and later refunded are not represented here when the original input for that
    /// currency was zero.
    /// @param shares LP shares received from the zap
    event ZapIn(
        address indexed sender, address indexed hooks, uint256[] inputAmounts, uint256[] usedAmounts, uint256 shares
    );

    /// @notice Error thrown when arrays have mismatched lengths
    error ArrayLengthMismatch();

    /// @notice Error thrown when no tokens are provided
    error NoTokensProvided();

    /// @notice Error thrown when slippage tolerance is exceeded
    error SlippageExceeded();

    /// @notice Error thrown when caller is not the PoolManager
    error NotPoolManager();

    /// @notice Error thrown when swap index is invalid
    error InvalidSwapIndex();

    /// @notice Error thrown when hooks address is zero
    error ZeroAddress();

    /// @notice Error thrown when ETH is sent but does not exactly match the native currency input amount
    error InvalidNativeValue();

    /// @notice Error thrown when an unexpected address sends ETH to this contract
    error InvalidEthSender();

    /// @notice Error thrown when rate oracle call fails
    error RateOracleCallFailed();

    /// @notice Error thrown when a hook was not deployed by the trusted factory
    error HookNotFromFactory();

    /// @notice Error thrown when the factory deploys unsupported StableSwapHooks bytecode
    error UnsupportedFactoryCreationCode(bytes32 expectedHash, bytes32 actualHash);

    /// @param _factory The StableSwapHooksFactory that deployed supported hooks
    /// @param _hooksCreationCodeHash Expected StableSwapHooks creation-code hash for this deployment build
    constructor(address _factory, bytes32 _hooksCreationCodeHash) {
        if (_factory == address(0)) revert ZeroAddress();

        factory = IStableSwapHooksFactory(_factory);

        bytes32 actualCreationCodeHash = factory.creationCodeHash();
        if (actualCreationCodeHash != _hooksCreationCodeHash) {
            revert UnsupportedFactoryCreationCode(_hooksCreationCodeHash, actualCreationCodeHash);
        }
        hooksCreationCodeHash = _hooksCreationCodeHash;

        poolManager = factory.poolManager();

        if (address(poolManager) == address(0)) revert ZeroAddress();
    }

    receive() external payable {
        if (msg.sender != address(poolManager) && !factory.isDeployedByFactory(msg.sender)) revert InvalidEthSender();
    }

    /// @notice Quote the result of a zap-in operation with configurable iteration count
    /// @dev Memory usage grows linearly with `_maxIterations`, so callers should keep it reasonably small.
    /// @param _hooks The StableSwapHooks contract address
    /// @param _amounts Array of input amounts for each currency
    /// @param _maxIterations Maximum iterations for balancing (0 = no swaps)
    /// @return shares Expected LP shares to receive
    /// @return resultingAmounts Amounts after swaps (what will be deposited as liquidity)
    /// @return swaps Array of swaps to execute to balance the deposit
    function quoteZapIn(address _hooks, uint256[] calldata _amounts, uint256 _maxIterations)
        public
        view
        returns (uint256 shares, uint256[] memory resultingAmounts, SwapQuote[] memory swaps)
    {
        IStableSwapHooks hooks = IStableSwapHooks(_hooks);
        _validateHook(_hooks);

        uint256 len = hooks.currenciesLength();

        if (_amounts.length != len) {
            revert ArrayLengthMismatch();
        }

        resultingAmounts = new uint256[](len);

        // For initial deposit, no swaps needed - use all amounts directly
        if (hooks.totalSupply() == 0) {
            (shares,) = hooks.quoteAddLiquidity(_amounts);
            for (uint256 i = 0; i < len; ++i) {
                resultingAmounts[i] = _amounts[i];
            }
            return (shares, resultingAmounts, new SwapQuote[](0));
        }

        // Calculate optimal swaps accounting for price impact
        swaps = _calculateOptimalSwaps(hooks, _amounts, _maxIterations);

        // Calculate resulting amounts after swaps
        for (uint256 i = 0; i < len; ++i) {
            resultingAmounts[i] = _amounts[i];
        }
        for (uint256 i = 0; i < swaps.length; ++i) {
            resultingAmounts[swaps[i].tokenInIndex] -= swaps[i].amountIn;
            resultingAmounts[swaps[i].tokenOutIndex] += swaps[i].expectedAmountOut;
        }

        (shares,) = hooks.quoteAddLiquidity(resultingAmounts);
    }

    /// @notice Add liquidity with pre-calculated swaps
    /// @dev Reentrancy protection is provided by PoolManager's lock mechanism
    /// @dev If the pool contains native ETH (`address(0)`), callers must fund that entry in `_amounts`
    /// with exactly matching `msg.value`. WETH is treated like any other ERC20 and is never auto-wrapped.
    /// @param _hooks The StableSwapHooks contract address
    /// @param _amounts Array of input amounts for each currency
    /// @param _swaps Pre-calculated swaps from quoteZapIn (use tokenInIndex, tokenOutIndex, amountIn fields)
    /// @param _minShares Minimum LP shares to receive (slippage protection)
    function zapIn(address _hooks, uint256[] calldata _amounts, Swap[] calldata _swaps, uint256 _minShares)
        external
        payable
        nonReentrant
    {
        if (_hooks == address(0)) revert ZeroAddress();
        _validateHook(_hooks);

        IStableSwapHooks hooks = IStableSwapHooks(_hooks);
        uint256 len = hooks.currenciesLength();

        if (_amounts.length != len) {
            revert ArrayLengthMismatch();
        }

        // Validate swap indices
        for (uint256 i = 0; i < _swaps.length; ++i) {
            if (_swaps[i].tokenInIndex >= len || _swaps[i].tokenOutIndex >= len) {
                revert InvalidSwapIndex();
            }
            if (_swaps[i].tokenInIndex == _swaps[i].tokenOutIndex) {
                revert InvalidSwapIndex();
            }
        }

        // Cache currencies to avoid repeated external calls
        Currency[] memory currencies = new Currency[](len);
        for (uint256 i = 0; i < len; ++i) {
            currencies[i] = hooks.currencies(i);
        }
        uint256 nativeIndex = _getNativeIndex(currencies);

        // Transfer tokens from user
        _transferTokensFromUser(currencies, _amounts, nativeIndex, msg.value);

        // Execute all swaps via PoolManager.unlock
        if (_swaps.length > 0) {
            poolManager.unlock(abi.encode(hooks, currencies, _swaps));
        }

        // Add liquidity and get shares
        uint256 sharesReceived = _addLiquidityAndGetShares(hooks, currencies);

        if (sharesReceived < _minShares) {
            revert SlippageExceeded();
        }

        // Transfer LP tokens and refund leftovers
        IERC20(address(hooks)).safeTransfer(msg.sender, sharesReceived);
        uint256[] memory usedAmounts = _refundLeftovers(currencies, _amounts);

        emit ZapIn(msg.sender, address(hooks), _amounts, usedAmounts, sharesReceived);
    }

    /// @dev Ensures ZapIn only interacts with hooks deployed by the configured factory.
    function _validateHook(address _hooks) internal view {
        if (!factory.isDeployedByFactory(_hooks)) {
            revert HookNotFromFactory();
        }
    }

    /// @notice Callback from PoolManager.unlock - executes swaps and settles
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();

        (IStableSwapHooks hooks, Currency[] memory currencies, Swap[] memory swaps) =
            abi.decode(data, (IStableSwapHooks, Currency[], Swap[]));
        uint256 len = currencies.length;

        // Cache pool config
        uint24 fee = uint24(hooks.lpFeePercentage());
        int24 tickSpacing = hooks.TICK_SPACING();
        IHooks hooksInterface = IHooks(address(hooks));

        // Track net deltas per currency (negative = we owe pool, positive = pool owes us)
        int256[] memory deltas = new int256[](len);

        // Execute all swaps and accumulate deltas
        for (uint256 i = 0; i < swaps.length; ++i) {
            Swap memory swap = swaps[i];

            Currency currencyIn = currencies[swap.tokenInIndex];
            Currency currencyOut = currencies[swap.tokenOutIndex];
            bool zeroForOne = Currency.unwrap(currencyIn) < Currency.unwrap(currencyOut);

            BalanceDelta swapDelta = poolManager.swap(
                PoolKey({
                    currency0: zeroForOne ? currencyIn : currencyOut,
                    currency1: zeroForOne ? currencyOut : currencyIn,
                    fee: fee,
                    tickSpacing: tickSpacing,
                    hooks: hooksInterface
                }),
                SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: -int256(swap.amountIn),
                    sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
                }),
                ""
            );

            // Accumulate deltas (amount0/amount1 correspond to currency0/currency1)
            if (zeroForOne) {
                deltas[swap.tokenInIndex] += swapDelta.amount0();
                deltas[swap.tokenOutIndex] += swapDelta.amount1();
            } else {
                deltas[swap.tokenInIndex] += swapDelta.amount1();
                deltas[swap.tokenOutIndex] += swapDelta.amount0();
            }
        }

        // Settle all currencies with non-zero deltas
        for (uint256 i = 0; i < len; ++i) {
            int256 delta = deltas[i];
            if (delta < 0) {
                // We owe the pool - settle with native ETH or ERC20 tokens.
                Currency currency = currencies[i];
                uint256 amount = uint256(-delta);
                if (currency.isAddressZero()) {
                    poolManager.settle{value: amount}();
                } else {
                    poolManager.sync(currency);
                    IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), amount);
                    poolManager.settle();
                }
            } else if (delta > 0) {
                // Pool owes us - take the tokens
                poolManager.take(currencies[i], address(this), uint256(delta));
            }
        }

        return "";
    }

    /// @dev Transfer tokens from user to this contract
    /// @param _currencies Array of currencies to transfer
    /// @param _amounts Array of amounts to transfer for each currency
    /// @param _nativeIndex Index of native ETH in the pool, or sentinel if absent
    /// @param _nativeValue ETH supplied alongside the zap for the native ETH currency
    function _transferTokensFromUser(
        Currency[] memory _currencies,
        uint256[] calldata _amounts,
        uint256 _nativeIndex,
        uint256 _nativeValue
    ) internal {
        uint256 len = _currencies.length;
        bool hasTokens = false;

        for (uint256 i = 0; i < len; ++i) {
            uint256 amount = _amounts[i];
            if (amount > 0) {
                hasTokens = true;

                if (!_currencies[i].isAddressZero()) {
                    IERC20(Currency.unwrap(_currencies[i])).safeTransferFrom(msg.sender, address(this), amount);
                }
            }
        }

        uint256 nativeAmount = _nativeIndex == NO_NATIVE_INDEX ? 0 : _amounts[_nativeIndex];
        if (_nativeValue != nativeAmount) revert InvalidNativeValue();
        if (!hasTokens) {
            revert NoTokensProvided();
        }
    }

    /// @dev Find the native ETH currency in the pool, if present.
    function _getNativeIndex(Currency[] memory _currencies) internal pure returns (uint256) {
        uint256 len = _currencies.length;

        for (uint256 i = 0; i < len; ++i) {
            if (_currencies[i].isAddressZero()) {
                return i;
            }
        }

        return NO_NATIVE_INDEX;
    }

    /// @dev Add liquidity using current contract balances and return shares received
    /// @param _hooks The StableSwapHooks contract to add liquidity to
    /// @param _currencies Array of currencies in the pool
    /// @return shares Amount of LP shares received
    function _addLiquidityAndGetShares(IStableSwapHooks _hooks, Currency[] memory _currencies)
        internal
        returns (uint256 shares)
    {
        uint256 len = _currencies.length;
        uint256[] memory balances = new uint256[](len);
        IERC20[] memory tokens = new IERC20[](len);

        // Get balances and approve in single loop
        for (uint256 i = 0; i < len; ++i) {
            Currency currency = _currencies[i];
            if (currency.isAddressZero()) {
                balances[i] = address(this).balance;
                continue;
            }

            IERC20 token = IERC20(Currency.unwrap(currency));
            uint256 balance = token.balanceOf(address(this));
            balances[i] = balance;
            tokens[i] = token;
            if (balance > 0) {
                token.forceApprove(address(_hooks), balance);
            }
        }

        uint256[] memory minAmounts = new uint256[](len);
        uint256 sharesBefore = IERC20(address(_hooks)).balanceOf(address(this));
        uint256 nativeIndex = _getNativeIndex(_currencies);
        uint256 nativeValue = nativeIndex == NO_NATIVE_INDEX ? 0 : balances[nativeIndex];

        _hooks.addLiquidity{value: nativeValue}(balances, minAmounts, 0);

        // Clear temporary approvals so user-supplied hooks do not retain spending power.
        for (uint256 i = 0; i < len; ++i) {
            if (!_currencies[i].isAddressZero() && balances[i] > 0) {
                tokens[i].forceApprove(address(_hooks), 0);
            }
        }

        return IERC20(address(_hooks)).balanceOf(address(this)) - sharesBefore;
    }

    /// @dev Refund leftover tokens to msg.sender and calculate used amounts
    /// @param _currencies Array of currencies to refund
    /// @param _amounts Original input amounts (used to calculate how much was used)
    /// @return usedAmounts Amount of each originally supplied currency that was consumed.
    /// Swap-produced tokens refunded back to the user are not represented here when the original input for that
    /// currency was zero.
    function _refundLeftovers(Currency[] memory _currencies, uint256[] calldata _amounts)
        internal
        returns (uint256[] memory usedAmounts)
    {
        uint256 len = _currencies.length;
        usedAmounts = new uint256[](len);

        for (uint256 i = 0; i < len; ++i) {
            Currency currency = _currencies[i];
            uint256 leftover;
            if (currency.isAddressZero()) {
                leftover = address(this).balance;
            } else {
                leftover = IERC20(Currency.unwrap(currency)).balanceOf(address(this));
            }

            // leftover can exceed _amounts[i] when swaps produce output tokens not originally provided
            usedAmounts[i] = leftover >= _amounts[i] ? 0 : _amounts[i] - leftover;
            if (leftover > 0) {
                if (currency.isAddressZero()) {
                    Address.sendValue(payable(msg.sender), leftover);
                } else {
                    IERC20(Currency.unwrap(currency)).safeTransfer(msg.sender, leftover);
                }
            }
        }
    }

    /// @dev Calculate optimal swaps using iterative balancing
    /// Works for any number of tokens (2, 3, 4, etc.)
    /// @param _hooks The hooks contract
    /// @param _amounts Input amounts
    /// @param _maxIterations Maximum iterations (0 = no swaps)
    /// @return swaps Array of swaps to execute
    function _calculateOptimalSwaps(IStableSwapHooks _hooks, uint256[] calldata _amounts, uint256 _maxIterations)
        internal
        view
        returns (SwapQuote[] memory swaps)
    {
        uint256 len = _hooks.currenciesLength();

        // Build context with scaled inputs and reserves
        SwapCalcContext memory ctx;
        ctx.scaledInputs = new uint256[](len);
        ctx.scaledReserves = new uint256[](len);
        ctx.rates = new uint256[](len);
        ctx.lpFee = _hooks.lpFeePercentage();
        ctx.hookFee = _hooks.hookFeePercentage();
        ctx.protocolFee = _hooks.protocolFeePercentage();
        ctx.amp = _hooks.getCurrentAmp();

        for (uint256 i = 0; i < len; ++i) {
            ctx.rates[i] = _getDynamicRate(_hooks, i);
            uint256 reserve = _hooks.reserves(i);
            ctx.scaledInputs[i] = StableSwapMath.scaleTo(_amounts[i], ctx.rates[i]);
            ctx.scaledReserves[i] = StableSwapMath.scaleTo(reserve, ctx.rates[i]);
        }

        // If no iterations requested, return empty swaps
        if (_maxIterations == 0) {
            return new SwapQuote[](0);
        }

        // Temporary array to collect swaps
        SwapQuote[] memory tempSwaps = new SwapQuote[](_maxIterations);
        uint256 swapCount = 0;

        // Iteratively balance pairs until no significant imbalance remains
        // For 2-token pools this is a single iteration, for 3+ it may take multiple
        for (uint256 round = 0; round < _maxIterations; ++round) {
            // Find highest excess and highest deficit based on ratio to reserves
            (uint256 excessIdx, uint256 deficitIdx, bool hasImbalance) =
                _findMostImbalancedPair(ctx.scaledInputs, ctx.scaledReserves);

            if (!hasImbalance) break;

            // Calculate and apply swap for this pair
            (uint256 swapAmount, uint256 expectedOutput) = _applyPairSwap(ctx, excessIdx, deficitIdx);
            if (swapAmount > 0) {
                tempSwaps[swapCount] = SwapQuote({
                    tokenInIndex: excessIdx,
                    tokenOutIndex: deficitIdx,
                    amountIn: swapAmount,
                    expectedAmountOut: expectedOutput
                });
                swapCount++;
            }
        }

        // Copy to correctly sized array
        swaps = new SwapQuote[](swapCount);
        for (uint256 i = 0; i < swapCount; ++i) {
            swaps[i] = tempSwaps[i];
        }
    }

    /// @dev Calculate and apply swap to balance either the deficit or excess token
    /// @param ctx Swap calculation context (modified in place to track state changes)
    /// @param excessIdx Index of the token with excess ratio
    /// @param deficitIdx Index of the token with deficit ratio
    /// @return swapAmount The amount to swap (in token units, not scaled)
    /// @return expectedOutput The expected output amount (in token units, not scaled)
    function _applyPairSwap(SwapCalcContext memory ctx, uint256 excessIdx, uint256 deficitIdx)
        internal
        pure
        returns (uint256 swapAmount, uint256 expectedOutput)
    {
        uint256 scaledSwapAmount = _calculateSwapAmount(ctx, excessIdx, deficitIdx);
        if (scaledSwapAmount == 0) return (0, 0);

        // Calculate actual output from this swap amount
        uint256 invariant = StableSwapMath.getInvariant(ctx.scaledReserves, ctx.amp);
        uint256 newReserveDeficit = StableSwapMath.getTargetReserves(
            excessIdx,
            deficitIdx,
            ctx.scaledReserves[excessIdx] + scaledSwapAmount,
            ctx.scaledReserves,
            ctx.amp,
            invariant
        );
        uint256 scaledOutputAfterFees;
        uint256 scaledReserveDecrease;
        (expectedOutput, scaledOutputAfterFees, scaledReserveDecrease) =
            _quoteSwapOutput(ctx, deficitIdx, ctx.scaledReserves[deficitIdx] - newReserveDeficit);

        // Update simulated state for next iteration
        ctx.scaledInputs[excessIdx] -= scaledSwapAmount;
        ctx.scaledInputs[deficitIdx] += scaledOutputAfterFees;
        ctx.scaledReserves[excessIdx] += scaledSwapAmount;
        ctx.scaledReserves[deficitIdx] -= scaledReserveDecrease;

        // Return descaled amounts
        swapAmount = StableSwapMath.descale(scaledSwapAmount, ctx.rates[excessIdx]);
    }

    /// @dev Quotes exact-input swap output and reserve movement in the same units used by the live hook.
    function _quoteSwapOutput(SwapCalcContext memory ctx, uint256 deficitIdx, uint256 rawOutputScaled)
        internal
        pure
        returns (uint256 outputAfterFees, uint256 scaledOutputAfterFees, uint256 scaledReserveDecrease)
    {
        uint256 rate = ctx.rates[deficitIdx];
        uint256 rawOutput = StableSwapMath.descale(rawOutputScaled, rate);
        (uint256 lpFees, uint256 hookFees, uint256 protocolFees) = _getSwapFees(rawOutput, ctx);

        outputAfterFees = rawOutput - lpFees - hookFees - protocolFees;
        scaledOutputAfterFees = StableSwapMath.scaleTo(outputAfterFees, rate);
        scaledReserveDecrease = StableSwapMath.scaleTo(rawOutput - lpFees, rate);
    }

    /// @dev Mirrors Fees._getFees: charge the gross LP fee, then split hook/protocol fees out of it.
    function _getSwapFees(uint256 _amount, SwapCalcContext memory ctx)
        internal
        pure
        returns (uint256 lpFees, uint256 hookFees, uint256 protocolFees)
    {
        lpFees = Math.mulDiv(_amount, ctx.lpFee, FEE_PRECISION, Math.Rounding.Ceil);
        hookFees = Math.mulDiv(lpFees, ctx.hookFee, FEE_PRECISION);
        protocolFees = Math.mulDiv(lpFees, ctx.protocolFee, FEE_PRECISION);
        lpFees -= hookFees + protocolFees;
    }

    /// @dev Calculate swap amount needed to balance deficit or excess token
    /// @param ctx Swap calculation context
    /// @param excessIdx Index of the token with excess ratio
    /// @param deficitIdx Index of the token with deficit ratio
    /// @return Scaled swap amount needed
    function _calculateSwapAmount(SwapCalcContext memory ctx, uint256 excessIdx, uint256 deficitIdx)
        internal
        pure
        returns (uint256)
    {
        // Calculate target ratio (total inputs / total reserves)
        uint256 targetRatio = _getTargetRatio(ctx);

        // Bail out when the deficit token already meets or exceeds the target ratio
        if (targetRatio * ctx.scaledReserves[deficitIdx] <= ctx.scaledInputs[deficitIdx] * RATE_PRECISION) {
            return 0;
        }

        // Calculate max swap from excess to reach target ratio
        uint256 maxFromExcess =
            (ctx.scaledInputs[excessIdx] * RATE_PRECISION - targetRatio * ctx.scaledReserves[excessIdx])
                / (RATE_PRECISION + targetRatio);

        // Output shrinks the deficit reserve while it grows the input
        // Divide by (RATE_PRECISION + targetRatio) to land on the target ratio after the swap.
        uint256 outputNeeded =
            (targetRatio * ctx.scaledReserves[deficitIdx] - ctx.scaledInputs[deficitIdx] * RATE_PRECISION)
                / (RATE_PRECISION + targetRatio);
        if (ctx.lpFee >= FEE_PRECISION) return 0;

        uint256 rawOutputNeeded = Math.mulDiv(outputNeeded, FEE_PRECISION, FEE_PRECISION - ctx.lpFee);
        uint256 deficitReserve = ctx.scaledReserves[deficitIdx];
        if (deficitReserve <= 1) return 0;

        // When the ideal target would drain the deficit reserve, use the maximum ratio-balancing input instead.
        // The actual output for that input is computed later from the invariant, so this avoids quote-only underflows.
        if (rawOutputNeeded >= deficitReserve - 1) {
            return maxFromExcess > ctx.scaledInputs[excessIdx] ? ctx.scaledInputs[excessIdx] : maxFromExcess;
        }

        // Calculate input needed for this output
        uint256 inputNeeded = _getInputForOutput(ctx, excessIdx, deficitIdx, rawOutputNeeded);

        // Return minimum of: what deficit needs, what excess can give, or available input
        uint256 result = inputNeeded < maxFromExcess ? inputNeeded : maxFromExcess;
        return result > ctx.scaledInputs[excessIdx] ? ctx.scaledInputs[excessIdx] : result;
    }

    /// @dev Calculate target ratio (total inputs / total reserves)
    /// @param ctx Swap calculation context
    /// @return Target ratio in RATE_PRECISION units
    function _getTargetRatio(SwapCalcContext memory ctx) internal pure returns (uint256) {
        uint256 totalInputs;
        uint256 totalReserves;
        uint256 len = ctx.scaledInputs.length;
        for (uint256 i = 0; i < len; ++i) {
            totalInputs += ctx.scaledInputs[i];
            totalReserves += ctx.scaledReserves[i];
        }
        return totalInputs * RATE_PRECISION / totalReserves;
    }

    /// @dev Calculate input needed to produce a given output using StableSwap math
    /// @param ctx Swap calculation context
    /// @param excessIdx Index of the input token
    /// @param deficitIdx Index of the output token
    /// @param rawOutput Desired output amount (scaled, before fees)
    /// @return Scaled input amount needed
    function _getInputForOutput(SwapCalcContext memory ctx, uint256 excessIdx, uint256 deficitIdx, uint256 rawOutput)
        internal
        pure
        returns (uint256)
    {
        uint256 invariant = StableSwapMath.getInvariant(ctx.scaledReserves, ctx.amp);
        uint256 newDeficitReserve = ctx.scaledReserves[deficitIdx] - rawOutput;
        uint256 newExcessReserve = StableSwapMath.getTargetReserves(
            deficitIdx, excessIdx, newDeficitReserve, ctx.scaledReserves, ctx.amp, invariant
        );
        return newExcessReserve - ctx.scaledReserves[excessIdx];
    }

    /// @dev Find the token pair with highest imbalance (highest excess ratio vs lowest deficit ratio)
    /// @param scaledInputs Scaled input amounts
    /// @param scaledReserves Scaled reserve amounts
    /// @return excessIdx Index of token with highest input/reserve ratio
    /// @return deficitIdx Index of token with lowest input/reserve ratio
    /// @return hasImbalance True if imbalance exceeds threshold (0.001%)
    function _findMostImbalancedPair(uint256[] memory scaledInputs, uint256[] memory scaledReserves)
        internal
        pure
        returns (uint256 excessIdx, uint256 deficitIdx, bool hasImbalance)
    {
        uint256 len = scaledInputs.length;
        uint256 maxRatio = 0;
        uint256 minRatio = type(uint256).max;

        for (uint256 i = 0; i < len; ++i) {
            // Initial deposits return early before this function, so zero reserves can only appear on unsupported
            // partially initialized state and should not influence pair selection.
            if (scaledReserves[i] == 0) continue;
            uint256 ratio = scaledInputs[i] * RATE_PRECISION / scaledReserves[i];
            if (ratio > maxRatio) {
                maxRatio = ratio;
                excessIdx = i;
            }
            if (ratio < minRatio) {
                minRatio = ratio;
                deficitIdx = i;
            }
        }

        hasImbalance = maxRatio > minRatio && maxRatio - minRatio > IMBALANCE_THRESHOLD;
    }

    /// @dev Gets the dynamic rate for a currency, fetching from oracle if configured
    /// @notice Mirrors the _getRate logic in Base.sol to ensure consistent rate calculations
    /// @param _hooks The StableSwapHooks contract
    /// @param _index Currency index
    /// @return rate Dynamic rate (base rate * oracle rate if configured)
    function _getDynamicRate(IStableSwapHooks _hooks, uint256 _index) internal view returns (uint256 rate) {
        rate = _hooks.rates(_index);

        (address oracle, bytes4 selector) = _hooks.rateOracles(_index);

        if (oracle != address(0)) {
            bytes memory returnData = Address.functionStaticCall(oracle, abi.encodeWithSelector(selector));

            if (returnData.length != 32) {
                revert RateOracleCallFailed();
            }

            uint256 fetchedRate = abi.decode(returnData, (uint256));
            rate = rate * fetchedRate / RATE_PRECISION;
        }
    }
}

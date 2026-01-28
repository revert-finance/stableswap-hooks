// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapZapIn, Swap} from "src/periphery/StableSwapZapIn.sol";
import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";
import {MockERC20} from "test/scenarios/mocks/MockERC20.sol";

contract StableSwapZapInTest is StableSwapHooksBaseTest {
    using SafeERC20 for IERC20;

    StableSwapZapIn internal zapIn;
    StableSwapHooks internal hooks4;
    Currency internal currency3;

    address internal zapUser;

    function setUp() public override {
        super.setUp();

        zapIn = new StableSwapZapIn(address(poolManager));
        zapUser = makeAddr("zapUser");

        // Deploy a 4th mock token for 4-token pool tests
        // Use an address guaranteed to be > USDT (0xdAC17F958D2ee523a2206206994597C13D831ec7)
        address mockToken3Address = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        MockERC20 mockToken3Impl = new MockERC20("Mock Token 3", "MT3", 18);
        vm.etch(mockToken3Address, address(mockToken3Impl).code);
        currency3 = Currency.wrap(mockToken3Address);
        _deployHooks4();

        // Deal tokens to zap user
        deal(Currency.unwrap(currency0), zapUser, _toTokenWei(currency0, 10e6));
        deal(Currency.unwrap(currency1), zapUser, _toTokenWei(currency1, 10e6));
        deal(Currency.unwrap(currency2), zapUser, _toTokenWei(currency2, 10e6));
        // MockERC20.mint for currency3
        MockERC20(Currency.unwrap(currency3)).mint(zapUser, 10e6 * 1e18);

        // Approve zap contract
        vm.startPrank(zapUser);
        IERC20(Currency.unwrap(currency0)).forceApprove(address(zapIn), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).forceApprove(address(zapIn), type(uint256).max);
        IERC20(Currency.unwrap(currency2)).forceApprove(address(zapIn), type(uint256).max);
        IERC20(Currency.unwrap(currency3)).forceApprove(address(zapIn), type(uint256).max);
        vm.stopPrank();
    }

    function _deployHooks4() private {
        Currency[] memory currencies = new Currency[](4);
        currencies[0] = currency0;
        currencies[1] = currency1;
        currencies[2] = currency2;
        currencies[3] = currency3;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](4);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[2] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[3] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, code);

        hooks4 = StableSwapHooks(factory.deploy(currencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, salt, code));

        vm.startPrank(defaultAdmin);
        hooks4.setProtocolFeePercentage(BASE_PROTOCOL_FEE_PERCENTAGE);
        hooks4.setHookFeePercentage(BASE_HOOK_FEE_PERCENTAGE);
        vm.stopPrank();

        // Approve and mint tokens for liquidity provider for hooks4
        deal(Currency.unwrap(currency3), liquidityProvider, 2e6 * 1e18);

        vm.startPrank(liquidityProvider);
        IERC20(Currency.unwrap(currency0)).forceApprove(address(hooks4), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).forceApprove(address(hooks4), type(uint256).max);
        IERC20(Currency.unwrap(currency2)).forceApprove(address(hooks4), type(uint256).max);
        IERC20(Currency.unwrap(currency3)).forceApprove(address(hooks4), type(uint256).max);
        vm.stopPrank();
    }

    function _addLiquidity4(uint256 _amount0, uint256 _amount1, uint256 _amount2, uint256 _amount3) internal {
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = _toTokenWei(currency0, _amount0);
        amounts[1] = _toTokenWei(currency1, _amount1);
        amounts[2] = _toTokenWei(currency2, _amount2);
        amounts[3] = _amount3 * 1e18; // currency3 is always 18 decimals

        uint256[] memory minAmounts = new uint256[](4);

        vm.prank(liquidityProvider);
        hooks4.addLiquidity(amounts, minAmounts, 0);
    }

    /// @dev Helper to assert that at least 99.9% of provided tokens were used (leftover < 0.1%)
    /// @param _amounts The amounts that were provided to zap
    /// @param _currencies The currencies array
    /// @param _balancesBefore The user's balances before the zap
    function _assertMinimalLeftover(
        uint256[] memory _amounts,
        Currency[] memory _currencies,
        uint256[] memory _balancesBefore
    ) internal view {
        uint256 totalInputValue = 0;
        uint256 totalLeftoverValue = 0;

        for (uint256 i = 0; i < _amounts.length; ++i) {
            if (_amounts[i] == 0) continue;

            // Scale to 18 decimals for fair comparison
            uint8 decimals = IERC20Metadata(Currency.unwrap(_currencies[i])).decimals();
            uint256 scaledInput = _amounts[i] * 1e18 / (10 ** decimals);
            totalInputValue += scaledInput;

            // Calculate leftover for tokens where input was provided
            uint256 balanceAfter = IERC20(Currency.unwrap(_currencies[i])).balanceOf(zapUser);
            // If balance increased, no leftover from this token
            if (balanceAfter >= _balancesBefore[i]) continue;

            uint256 used = _balancesBefore[i] - balanceAfter;
            if (used < _amounts[i]) {
                uint256 leftover = _amounts[i] - used;
                uint256 scaledLeftover = leftover * 1e18 / (10 ** decimals);
                totalLeftoverValue += scaledLeftover;
            }
        }

        // At least 99.9% of total input value should be used (leftover < 0.1%)
        assertLt(totalLeftoverValue * 1000, totalInputValue, "Leftover should be < 0.1% of input");
    }

    /// @dev Get balances before zap for 2-token pool
    function _getBalancesBefore2() internal view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](2);
        balances[0] = IERC20(Currency.unwrap(currency0)).balanceOf(zapUser);
        balances[1] = IERC20(Currency.unwrap(currency1)).balanceOf(zapUser);
        return balances;
    }

    /// @dev Get balances before zap for 3-token pool
    function _getBalancesBefore3() internal view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](3);
        balances[0] = IERC20(Currency.unwrap(currency0)).balanceOf(zapUser);
        balances[1] = IERC20(Currency.unwrap(currency1)).balanceOf(zapUser);
        balances[2] = IERC20(Currency.unwrap(currency2)).balanceOf(zapUser);
        return balances;
    }

    /// @dev Get balances before zap for 4-token pool
    function _getBalancesBefore4() internal view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](4);
        balances[0] = IERC20(Currency.unwrap(currency0)).balanceOf(zapUser);
        balances[1] = IERC20(Currency.unwrap(currency1)).balanceOf(zapUser);
        balances[2] = IERC20(Currency.unwrap(currency2)).balanceOf(zapUser);
        balances[3] = IERC20(Currency.unwrap(currency3)).balanceOf(zapUser);
        return balances;
    }

    /// @dev Get currencies array for 2-token pool
    function _getCurrencies2() internal view returns (Currency[] memory) {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;
        return currencies;
    }

    /// @dev Get currencies array for 3-token pool
    function _getCurrencies3() internal view returns (Currency[] memory) {
        Currency[] memory currencies = new Currency[](3);
        currencies[0] = currency0;
        currencies[1] = currency1;
        currencies[2] = currency2;
        return currencies;
    }

    /// @dev Get currencies array for 4-token pool
    function _getCurrencies4() internal view returns (Currency[] memory) {
        Currency[] memory currencies = new Currency[](4);
        currencies[0] = currency0;
        currencies[1] = currency1;
        currencies[2] = currency2;
        currencies[3] = currency3;
        return currencies;
    }

    // ============ 2-Token Pool Tests ============

    function test_zapIn_2tokens_balanced() public {
        // Add initial liquidity
        _addLiquidity(1000, 1000);

        // Prepare zap amounts (balanced)
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 100);
        amounts[1] = _toTokenWei(currency1, 100);

        // Quote first
        (uint256 quotedShares,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);
        assertGt(quotedShares, 0, "Quoted shares should be > 0");
        // For balanced deposit, no swaps needed
        assertEq(swaps.length, 0, "No swap needed for balanced deposit");

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore2();

        // Execute zap with pre-calculated swaps
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies2(), balancesBefore);
    }

    function test_zapIn_2tokens_singleSided_token0Only() public {
        // Add initial liquidity
        _addLiquidity(1000, 1000);

        // Prepare zap amounts (only token0)
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 200);
        amounts[1] = 0;

        // Quote first - should indicate a swap is needed
        (uint256 quotedShares,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);
        assertGt(quotedShares, 0, "Quoted shares should be > 0");
        assertGt(swaps.length, 0, "Should have swaps");
        assertEq(swaps[0].tokenInIndex, 0, "Should swap from token0");
        assertEq(swaps[0].tokenOutIndex, 1, "Should swap to token1");

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore2();

        // Execute zap with pre-calculated swaps
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies2(), balancesBefore);
    }

    function test_zapIn_2tokens_singleSided_token1Only() public {
        // Add initial liquidity
        _addLiquidity(1000, 1000);

        // Prepare zap amounts (only token1)
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = _toTokenWei(currency1, 200);

        // Quote to get swaps
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore2();

        // Execute zap with pre-calculated swaps
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies2(), balancesBefore);
    }

    function test_zapIn_2tokens_imbalanced() public {
        // Add initial liquidity
        _addLiquidity(1000, 1000);

        // Prepare imbalanced zap amounts (3:1 ratio into 1:1 pool)
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 300);
        amounts[1] = _toTokenWei(currency1, 100);

        // Quote to get swaps
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore2();

        // Execute zap with pre-calculated swaps
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies2(), balancesBefore);
    }

    function test_zapIn_2tokens_initialDeposit() public {
        // No initial liquidity - first deposit

        // Prepare zap amounts
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 1000);
        amounts[1] = _toTokenWei(currency1, 1000);

        // Quote to get swaps (should be empty for initial deposit)
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore2();

        // Execute zap as initial deposit
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies2(), balancesBefore);
    }

    function test_zapIn_2tokens_slippageProtection() public {
        // Add initial liquidity
        _addLiquidity(1000, 1000);

        // Prepare zap amounts
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 100);
        amounts[1] = _toTokenWei(currency1, 100);

        // Quote to get expected shares and swaps
        (uint256 quotedShares,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);

        // Set minShares higher than possible - should revert
        vm.prank(zapUser);
        vm.expectRevert(StableSwapZapIn.SlippageExceeded.selector);
        zapIn.zapIn(address(hooks), amounts, swaps, quotedShares * 2);
    }

    function test_zapIn_2tokens_revertNoTokens() public {
        _addLiquidity(1000, 1000);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        Swap[] memory swaps = new Swap[](0);

        vm.prank(zapUser);
        vm.expectRevert(StableSwapZapIn.NoTokensProvided.selector);
        zapIn.zapIn(address(hooks), amounts, swaps, 0);
    }

    function test_zapIn_2tokens_revertArrayLengthMismatch() public {
        _addLiquidity(1000, 1000);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 100);
        amounts[1] = _toTokenWei(currency1, 100);
        amounts[2] = 100;

        Swap[] memory swaps = new Swap[](0);

        vm.prank(zapUser);
        vm.expectRevert(StableSwapZapIn.ArrayLengthMismatch.selector);
        zapIn.zapIn(address(hooks), amounts, swaps, 0);
    }

    function test_zapIn_2tokens_revertInvalidSwapIndex_outOfBounds() public {
        _addLiquidity(1000, 1000);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 100);
        amounts[1] = _toTokenWei(currency1, 100);

        // Create swap with out-of-bounds index
        Swap[] memory swaps = new Swap[](1);
        swaps[0] = Swap({tokenInIndex: 0, tokenOutIndex: 5, amountIn: 100, expectedAmountOut: 100});

        vm.prank(zapUser);
        vm.expectRevert(StableSwapZapIn.InvalidSwapIndex.selector);
        zapIn.zapIn(address(hooks), amounts, swaps, 0);
    }

    function test_zapIn_2tokens_revertInvalidSwapIndex_sameToken() public {
        _addLiquidity(1000, 1000);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 100);
        amounts[1] = _toTokenWei(currency1, 100);

        // Create swap with same in/out index
        Swap[] memory swaps = new Swap[](1);
        swaps[0] = Swap({tokenInIndex: 0, tokenOutIndex: 0, amountIn: 100, expectedAmountOut: 100});

        vm.prank(zapUser);
        vm.expectRevert(StableSwapZapIn.InvalidSwapIndex.selector);
        zapIn.zapIn(address(hooks), amounts, swaps, 0);
    }

    function test_zapIn_revertZeroAddress() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 100;

        Swap[] memory swaps = new Swap[](0);

        vm.prank(zapUser);
        vm.expectRevert(StableSwapZapIn.ZeroAddress.selector);
        zapIn.zapIn(address(0), amounts, swaps, 0);
    }

    // ============ 3-Token Pool Tests ============

    function test_zapIn_3tokens_balanced() public {
        // Add initial liquidity
        _addLiquidity3(1000, 1000, 1000);

        // Prepare zap amounts (balanced)
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 100);
        amounts[1] = _toTokenWei(currency1, 100);
        amounts[2] = _toTokenWei(currency2, 100);

        // Quote to get swaps
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks3), amounts, 6);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore3();

        // Execute zap
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks3), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks3.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies3(), balancesBefore);
    }

    function test_zapIn_3tokens_singleSided() public {
        // Add initial liquidity
        _addLiquidity3(1000, 1000, 1000);

        // Prepare zap amounts (only token0)
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 300);
        amounts[1] = 0;
        amounts[2] = 0;

        // Quote to get swaps
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks3), amounts, 6);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore3();

        // Execute zap - should swap to get other tokens
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks3), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks3.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies3(), balancesBefore);
    }

    function test_zapIn_3tokens_twoTokensOnly() public {
        // Add initial liquidity
        _addLiquidity3(1000, 1000, 1000);

        // Prepare zap amounts (two tokens only - missing token2)
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 200);
        amounts[1] = _toTokenWei(currency1, 100);
        amounts[2] = 0;

        // Quote to get swaps
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks3), amounts, 6);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore3();

        // Execute zap - should swap to get token2
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks3), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks3.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies3(), balancesBefore);
    }

    function test_zapIn_3tokens_imbalanced() public {
        // Add initial liquidity (imbalanced)
        _addLiquidity3(1000, 1000, 1000);

        // Prepare heavily imbalanced zap amounts
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 500);
        amounts[1] = _toTokenWei(currency1, 100);
        amounts[2] = _toTokenWei(currency2, 50);

        // Quote to get swaps
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks3), amounts, 6);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore3();

        // Execute zap
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks3), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks3.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies3(), balancesBefore);
    }

    // ============ 4-Token Pool Tests ============

    function test_zapIn_4tokens_balanced() public {
        // Add initial liquidity
        _addLiquidity4(1000, 1000, 1000, 1000);

        // Prepare zap amounts (balanced)
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = _toTokenWei(currency0, 100);
        amounts[1] = _toTokenWei(currency1, 100);
        amounts[2] = _toTokenWei(currency2, 100);
        amounts[3] = 100 * 1e18;

        // Quote to get swaps
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks4), amounts, 8);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore4();

        // Execute zap
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks4), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks4.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies4(), balancesBefore);
    }

    function test_zapIn_4tokens_singleSided() public {
        // Add initial liquidity
        _addLiquidity4(1000, 1000, 1000, 1000);

        // Prepare zap amounts (only token2)
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 0;
        amounts[1] = 0;
        amounts[2] = _toTokenWei(currency2, 400);
        amounts[3] = 0;

        // Quote to get swaps
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks4), amounts, 8);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore4();

        // Execute zap - should swap to get other tokens
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks4), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks4.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies4(), balancesBefore);
    }

    function test_zapIn_4tokens_twoTokensOnly() public {
        // Add initial liquidity
        _addLiquidity4(1000, 1000, 1000, 1000);

        // Prepare zap amounts (tokens 0 and 3 only - missing tokens 1 and 2)
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = _toTokenWei(currency0, 200);
        amounts[1] = 0;
        amounts[2] = 0;
        amounts[3] = 200 * 1e18;

        // Quote to get swaps
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks4), amounts, 8);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore4();

        // Execute zap - should swap to get missing tokens
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks4), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks4.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies4(), balancesBefore);
    }

    function test_zapIn_4tokens_imbalanced() public {
        // Add initial liquidity
        _addLiquidity4(1000, 1000, 1000, 1000);

        // Prepare heavily imbalanced zap amounts
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = _toTokenWei(currency0, 1000);
        amounts[1] = _toTokenWei(currency1, 100);
        amounts[2] = _toTokenWei(currency2, 50);
        amounts[3] = 25 * 1e18;

        // Quote to get swaps
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks4), amounts, 8);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore4();

        // Execute zap
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks4), amounts, swaps, 0);

        // Verify LP tokens received
        uint256 lpBalance = hooks4.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies4(), balancesBefore);
    }

    // ============ Quote Tests ============

    function test_quoteZapIn_matchesActual() public {
        _addLiquidity(1000, 1000);

        // Use balanced amounts for this test
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 100);
        amounts[1] = _toTokenWei(currency1, 100);

        // Get quote
        (uint256 quotedShares,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);

        // Execute zap
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, swaps, 0);

        // Actual shares should match quoted exactly for balanced deposit
        uint256 actualShares = hooks.balanceOf(zapUser);

        assertEq(actualShares, quotedShares, "Actual shares should match quoted");
    }

    // ============ Edge Cases ============

    function test_zapIn_smallAmounts() public {
        _addLiquidity(1000, 1000);

        // Very small balanced amounts
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 1); // 1 token
        amounts[1] = _toTokenWei(currency1, 1); // 1 token

        // Quote to get swaps
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore2();

        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, swaps, 0);

        uint256 lpBalance = hooks.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens even for small amounts");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies2(), balancesBefore);
    }

    function test_zapIn_largeAmounts() public {
        _addLiquidity(100000, 100000);

        // Large amounts
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 50000);
        amounts[1] = _toTokenWei(currency1, 10000);

        // Quote to get swaps
        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooks), amounts, 1);

        // Capture balances before
        uint256[] memory balancesBefore = _getBalancesBefore2();

        vm.prank(zapUser);
        zapIn.zapIn(address(hooks), amounts, swaps, 0);

        uint256 lpBalance = hooks.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens for large amounts");

        // Verify minimal leftover
        _assertMinimalLeftover(amounts, _getCurrencies2(), balancesBefore);
    }

    // ============ Max Iterations Tests ============

    function test_quoteZapIn_explicitIterations_2tokens() public {
        _addLiquidity(1000, 1000);

        // Single-sided deposit
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 200);
        amounts[1] = 0;

        // With 1 iteration - sufficient for 2-token pool
        (uint256 shares1,, Swap[] memory swaps1) = zapIn.quoteZapIn(address(hooks), amounts, 1);
        assertGt(shares1, 0, "Should get shares with 1 iteration");
        assertEq(swaps1.length, 1, "Should have 1 swap with 1 iteration");

        // With more iterations - should give same result (already balanced after 1)
        (uint256 shares2,, Swap[] memory swaps2) = zapIn.quoteZapIn(address(hooks), amounts, 2);
        assertGe(shares2, shares1, "2 iterations should be >= 1 iteration");
        assertGe(swaps2.length, swaps1.length, "More iterations may refine");
    }

    function test_quoteZapIn_explicitIterations_3tokens() public {
        _addLiquidity3(1000, 1000, 1000);

        // Single-sided deposit into 3-token pool
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _toTokenWei(currency0, 300);
        amounts[1] = 0;
        amounts[2] = 0;

        // With 6 iterations - recommended for 3-token pool single-sided
        (uint256 shares6,, Swap[] memory swaps6) = zapIn.quoteZapIn(address(hooks3), amounts, 6);
        assertGt(shares6, 0, "Should get shares with 6 iterations");
        assertGt(swaps6.length, 0, "Should have swaps");

        // Execute with swaps
        uint256[] memory balancesBefore = _getBalancesBefore3();
        vm.prank(zapUser);
        zapIn.zapIn(address(hooks3), amounts, swaps6, 0);

        uint256 lpBalance = hooks3.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify minimal leftover with recommended iterations
        _assertMinimalLeftover(amounts, _getCurrencies3(), balancesBefore);
    }

    function test_quoteZapIn_zeroIterations_noSwaps() public {
        _addLiquidity(1000, 1000);

        // Use balanced amounts so we can add liquidity without swaps
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 100);
        amounts[1] = _toTokenWei(currency1, 100);

        // 0 iterations should return no swaps
        (uint256 shares0,, Swap[] memory swaps0) = zapIn.quoteZapIn(address(hooks), amounts, 0);
        assertGt(shares0, 0, "Should quote shares for balanced deposit");
        assertEq(swaps0.length, 0, "Zero iterations should return no swaps");

        // For imbalanced deposit, 0 iterations means no rebalancing
        uint256[] memory imbalancedAmounts = new uint256[](2);
        imbalancedAmounts[0] = _toTokenWei(currency0, 200);
        imbalancedAmounts[1] = 0;

        (,, Swap[] memory swapsImbalanced) = zapIn.quoteZapIn(address(hooks), imbalancedAmounts, 0);
        assertEq(swapsImbalanced.length, 0, "Zero iterations should return no swaps even for imbalanced");
    }
}

import {IWstETH} from "lib/uniswap-hooks/lib/v4-periphery/src/interfaces/external/IWstETH.sol";
import {MockWstETH} from "lib/uniswap-hooks/lib/v4-periphery/test/mocks/MockWstETH.sol";

/// @notice Mock stETH for testing - matches interface expected by MockWstETH
contract MockStETHForZapIn is MockERC20 {
    constructor() MockERC20("Liquid staked Ether 2.0", "stETH", 18) {}

    function getSharesByPooledEth(uint256 pooledEth) public pure returns (uint256) {
        return pooledEth;
    }

    function getPooledEthByShares(uint256 shares) public pure returns (uint256) {
        return shares;
    }
}

/// @notice Tests ZapIn with rate oracles (non-1:1 relationships like wstETH/stETH)
contract StableSwapZapInRateOracleTest is StableSwapHooksBaseTest {
    using SafeERC20 for IERC20;

    StableSwapZapIn internal zapIn;
    StableSwapHooks internal hooksRateOracle;

    Currency internal stETH;
    Currency internal wstETH;

    address internal zapUser;

    uint256 internal constant EXCHANGE_RATE = 11e17; // 1.1 - MockWstETH exchange rate

    function setUp() public override {
        super.setUp();

        zapIn = new StableSwapZapIn(address(poolManager));
        zapUser = makeAddr("zapUser");

        // Deploy stETH and wstETH mocks
        MockStETHForZapIn mockStETH = new MockStETHForZapIn();
        MockWstETH mockWstETH = new MockWstETH(address(mockStETH));
        stETH = Currency.wrap(address(mockStETH));
        wstETH = Currency.wrap(address(mockWstETH));

        _deployHooksWithRateOracle();

        // Deal tokens
        deal(Currency.unwrap(stETH), liquidityProvider, 10_000_000e18);
        deal(Currency.unwrap(wstETH), liquidityProvider, 10_000_000e18);
        deal(Currency.unwrap(stETH), zapUser, 10_000_000e18);
        deal(Currency.unwrap(wstETH), zapUser, 10_000_000e18);

        // Approve hooks for LP
        vm.startPrank(liquidityProvider);
        IERC20(Currency.unwrap(stETH)).forceApprove(address(hooksRateOracle), type(uint256).max);
        IERC20(Currency.unwrap(wstETH)).forceApprove(address(hooksRateOracle), type(uint256).max);
        vm.stopPrank();

        // Approve zap contract for user
        vm.startPrank(zapUser);
        IERC20(Currency.unwrap(stETH)).forceApprove(address(zapIn), type(uint256).max);
        IERC20(Currency.unwrap(wstETH)).forceApprove(address(zapIn), type(uint256).max);
        vm.stopPrank();
    }

    function _deployHooksWithRateOracle() private {
        // Sort currencies
        Currency currency0Local;
        Currency currency1Local;
        if (Currency.unwrap(stETH) < Currency.unwrap(wstETH)) {
            currency0Local = stETH;
            currency1Local = wstETH;
        } else {
            currency0Local = wstETH;
            currency1Local = stETH;
        }

        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0Local;
        currencies[1] = currency1Local;

        // Configure rate oracle for wstETH only
        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        if (Currency.unwrap(stETH) < Currency.unwrap(wstETH)) {
            // stETH is currency0, wstETH is currency1
            rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
            rateOracles[1] =
                Base.RateOracleConfig({oracle: Currency.unwrap(wstETH), selector: IWstETH.stEthPerToken.selector});
        } else {
            // wstETH is currency0, stETH is currency1
            rateOracles[0] =
                Base.RateOracleConfig({oracle: Currency.unwrap(wstETH), selector: IWstETH.stEthPerToken.selector});
            rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        }

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, code);

        hooksRateOracle =
            StableSwapHooks(factory.deploy(currencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, salt, code));

        vm.startPrank(defaultAdmin);
        hooksRateOracle.setProtocolFeePercentage(BASE_PROTOCOL_FEE_PERCENTAGE);
        hooksRateOracle.setHookFeePercentage(BASE_HOOK_FEE_PERCENTAGE);
        vm.stopPrank();
    }

    function _addLiquidityRateOracle(uint256 _amountStETH, uint256 _amountWstETH) internal {
        uint256[] memory amounts = new uint256[](2);

        // Order amounts according to currency order
        if (Currency.unwrap(stETH) < Currency.unwrap(wstETH)) {
            amounts[0] = _amountStETH;
            amounts[1] = _amountWstETH;
        } else {
            amounts[0] = _amountWstETH;
            amounts[1] = _amountStETH;
        }

        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooksRateOracle.addLiquidity(amounts, minAmounts, 0);
    }

    function _getStETHIndex() internal view returns (uint256) {
        return Currency.unwrap(stETH) < Currency.unwrap(wstETH) ? 0 : 1;
    }

    function _getWstETHIndex() internal view returns (uint256) {
        return Currency.unwrap(stETH) < Currency.unwrap(wstETH) ? 1 : 0;
    }

    /// @notice Test zapIn with rate oracle - balanced deposit (rate-adjusted amounts)
    function test_zapIn_rateOracle_balanced() public {
        // Add initial liquidity with rate-adjusted amounts
        // 1 wstETH = 1.1 stETH, so for balanced pool: 1100 stETH + 1000 wstETH
        uint256 stETHAmount = 1_100_000e18;
        uint256 wstETHAmount = 1_000_000e18;
        _addLiquidityRateOracle(stETHAmount, wstETHAmount);

        // Zap with rate-adjusted amounts (should require no swaps)
        uint256[] memory amounts = new uint256[](2);
        if (Currency.unwrap(stETH) < Currency.unwrap(wstETH)) {
            amounts[0] = 1100e18; // stETH
            amounts[1] = 1000e18; // wstETH (worth 1100 stETH)
        } else {
            amounts[0] = 1000e18; // wstETH
            amounts[1] = 1100e18; // stETH
        }

        (uint256 quotedShares,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooksRateOracle), amounts, 1);
        assertGt(quotedShares, 0, "Should get shares for balanced deposit");
        assertEq(swaps.length, 0, "Should not need swaps for rate-adjusted balanced deposit");

        vm.prank(zapUser);
        zapIn.zapIn(address(hooksRateOracle), amounts, swaps, 0);

        uint256 lpBalance = hooksRateOracle.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");
        assertApproxEqRel(lpBalance, quotedShares, 0.001e18, "Actual shares should match quoted");
    }

    /// @notice Test zapIn with rate oracle - single-sided stETH (should swap to wstETH)
    function test_zapIn_rateOracle_singleSided_stETH() public {
        // Add initial liquidity
        uint256 stETHAmount = 1_100_000e18;
        uint256 wstETHAmount = 1_000_000e18;
        _addLiquidityRateOracle(stETHAmount, wstETHAmount);

        // Zap with only stETH
        uint256[] memory amounts = new uint256[](2);
        uint256 stETHIndex = _getStETHIndex();
        amounts[stETHIndex] = 1100e18;

        uint256 stETHBefore = IERC20(Currency.unwrap(stETH)).balanceOf(zapUser);
        uint256 wstETHBefore = IERC20(Currency.unwrap(wstETH)).balanceOf(zapUser);

        (uint256 quotedShares,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooksRateOracle), amounts, 1);
        assertGt(quotedShares, 0, "Should get shares");
        assertGt(swaps.length, 0, "Should need swaps for single-sided");

        // Verify swap direction: should swap stETH -> wstETH
        assertEq(swaps[0].tokenInIndex, stETHIndex, "Should swap from stETH");
        assertEq(swaps[0].tokenOutIndex, _getWstETHIndex(), "Should swap to wstETH");

        vm.prank(zapUser);
        zapIn.zapIn(address(hooksRateOracle), amounts, swaps, 0);

        uint256 lpBalance = hooksRateOracle.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify tokens were used
        uint256 stETHAfter = IERC20(Currency.unwrap(stETH)).balanceOf(zapUser);
        assertLt(stETHAfter, stETHBefore, "Should have used stETH");

        // May have received some wstETH back as leftover or used some for swap
        uint256 wstETHAfter = IERC20(Currency.unwrap(wstETH)).balanceOf(zapUser);
        // wstETH balance should be close to before (minor changes from swap output leftovers)
        assertApproxEqRel(wstETHAfter, wstETHBefore, 0.1e18, "wstETH balance change should be minimal");
    }

    /// @notice Test zapIn with rate oracle - single-sided wstETH (should swap to stETH)
    function test_zapIn_rateOracle_singleSided_wstETH() public {
        // Add initial liquidity
        uint256 stETHAmount = 1_100_000e18;
        uint256 wstETHAmount = 1_000_000e18;
        _addLiquidityRateOracle(stETHAmount, wstETHAmount);

        // Zap with only wstETH
        uint256[] memory amounts = new uint256[](2);
        uint256 wstETHIndex = _getWstETHIndex();
        amounts[wstETHIndex] = 1000e18;

        uint256 stETHBefore = IERC20(Currency.unwrap(stETH)).balanceOf(zapUser);
        uint256 wstETHBefore = IERC20(Currency.unwrap(wstETH)).balanceOf(zapUser);

        (uint256 quotedShares,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooksRateOracle), amounts, 1);
        assertGt(quotedShares, 0, "Should get shares");
        assertGt(swaps.length, 0, "Should need swaps for single-sided");

        // Verify swap direction: should swap wstETH -> stETH
        assertEq(swaps[0].tokenInIndex, wstETHIndex, "Should swap from wstETH");
        assertEq(swaps[0].tokenOutIndex, _getStETHIndex(), "Should swap to stETH");

        vm.prank(zapUser);
        zapIn.zapIn(address(hooksRateOracle), amounts, swaps, 0);

        uint256 lpBalance = hooksRateOracle.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");

        // Verify tokens were used
        uint256 wstETHAfter = IERC20(Currency.unwrap(wstETH)).balanceOf(zapUser);
        assertLt(wstETHAfter, wstETHBefore, "Should have used wstETH");

        // stETH balance should be close to before
        uint256 stETHAfter = IERC20(Currency.unwrap(stETH)).balanceOf(zapUser);
        assertApproxEqRel(stETHAfter, stETHBefore, 0.1e18, "stETH balance change should be minimal");
    }

    /// @notice Test zapIn with rate oracle - imbalanced deposit (not rate-adjusted)
    function test_zapIn_rateOracle_imbalanced() public {
        // Add initial liquidity
        uint256 stETHAmount = 1_100_000e18;
        uint256 wstETHAmount = 1_000_000e18;
        _addLiquidityRateOracle(stETHAmount, wstETHAmount);

        // Zap with equal amounts (NOT rate-adjusted, so imbalanced for the pool)
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000e18;
        amounts[1] = 1000e18;

        (uint256 quotedShares,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooksRateOracle), amounts, 2);
        assertGt(quotedShares, 0, "Should get shares");
        assertGt(swaps.length, 0, "Should need swaps to rebalance");

        vm.prank(zapUser);
        zapIn.zapIn(address(hooksRateOracle), amounts, swaps, 0);

        uint256 lpBalance = hooksRateOracle.balanceOf(zapUser);
        assertGt(lpBalance, 0, "Should receive LP tokens");
        assertApproxEqRel(lpBalance, quotedShares, 0.01e18, "Actual shares should be close to quoted");
    }

    /// @notice Test that swap amounts respect the rate oracle scaling
    function test_zapIn_rateOracle_swapAmountsRespectRate() public {
        // Add initial liquidity
        uint256 stETHAmount = 1_100_000e18;
        uint256 wstETHAmount = 1_000_000e18;
        _addLiquidityRateOracle(stETHAmount, wstETHAmount);

        // Single-sided deposit with stETH
        uint256[] memory amounts = new uint256[](2);
        uint256 stETHIndex = _getStETHIndex();
        amounts[stETHIndex] = 2200e18; // 2200 stETH

        (,, Swap[] memory swaps) = zapIn.quoteZapIn(address(hooksRateOracle), amounts, 1);
        assertGt(swaps.length, 0, "Should need swaps");

        // The swap should convert roughly half the value
        // Since 1 wstETH = 1.1 stETH, swapping X stETH should give approximately X/1.1 wstETH
        Swap memory swap = swaps[0];

        // For a single-sided 2200 stETH deposit into a 1.1:1 (stETH:wstETH rate-adjusted) pool,
        // we need to swap approximately half the value
        // Expected swap: ~1100 stETH -> ~1000 wstETH (accounting for rate)
        // The amountIn should be roughly half the input
        assertGt(swap.amountIn, 900e18, "Swap amount should be significant");
        assertLt(swap.amountIn, 1300e18, "Swap amount should not exceed value proportion");

        // Expected output should respect the 1.1 rate (minus fees)
        // expectedOutput ~= amountIn / 1.1 (minus small fee)
        uint256 expectedOutputApprox = (swap.amountIn * 1e18) / EXCHANGE_RATE;
        assertApproxEqRel(swap.expectedAmountOut, expectedOutputApprox, 0.02e18, "Output should respect exchange rate");
    }

    /// @notice Test quote accuracy with rate oracle
    function test_quoteZapIn_rateOracle_accuracy() public {
        // Add initial liquidity
        uint256 stETHAmount = 1_100_000e18;
        uint256 wstETHAmount = 1_000_000e18;
        _addLiquidityRateOracle(stETHAmount, wstETHAmount);

        // Test with various deposit ratios
        uint256[] memory amounts = new uint256[](2);
        uint256 stETHIndex = _getStETHIndex();
        uint256 wstETHIndex = _getWstETHIndex();

        // Test 1: 2:1 ratio (stETH heavy)
        amounts[stETHIndex] = 2000e18;
        amounts[wstETHIndex] = 1000e18;

        (uint256 quotedShares1, uint256[] memory resultingAmounts1, Swap[] memory swaps1) =
            zapIn.quoteZapIn(address(hooksRateOracle), amounts, 2);

        vm.prank(zapUser);
        zapIn.zapIn(address(hooksRateOracle), amounts, swaps1, 0);

        uint256 actualShares1 = hooksRateOracle.balanceOf(zapUser);
        assertApproxEqRel(actualShares1, quotedShares1, 0.01e18, "Quoted shares should match actual for stETH heavy");

        // Verify resultingAmounts make sense
        assertGt(resultingAmounts1[stETHIndex], 0, "Should have stETH after swaps");
        assertGt(resultingAmounts1[wstETHIndex], amounts[wstETHIndex], "wstETH should increase after swaps");
    }
}

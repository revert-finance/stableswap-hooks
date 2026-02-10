// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {V4Quoter} from "@uniswap/v4-periphery/src/lens/V4Quoter.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";

import {Base} from "src/Base.sol";
import {Liquidity} from "src/Liquidity.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactoryHarness} from "test/testUtils/StableSwapHooksFactoryHarness.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";
import {MockERC20} from "test/scenarios/mocks/MockERC20.sol";

/// @notice Tests for Native ETH + MockERC20 pool
contract NativeEthMockERC20Test is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 internal constant LP_FEE_PERCENTAGE = 300;
    uint256 internal constant AMP = 100;
    uint256 internal constant INITIAL_LIQUIDITY = 10_000 ether;

    StableSwapHooksFactoryHarness internal factory;
    StableSwapHooks internal hooks;
    MockERC20 internal token;

    Currency internal nativeEth;
    Currency internal tokenCurrency;

    address internal admin;
    address internal liquidityProvider;
    address internal swapper;

    function setUp() public override {
        super.setUp();

        nativeEth = Currency.wrap(address(0));
        token = new MockERC20("Mock Token", "MOCK", 18);
        tokenCurrency = Currency.wrap(address(token));

        admin = makeAddr("admin");
        liquidityProvider = makeAddr("liquidityProvider");
        swapper = makeAddr("swapper");

        factory = new StableSwapHooksFactoryHarness(
            IPoolManager(poolManager),
            admin,
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );

        _deployHooks();
        _dealTokens();
        _addInitialLiquidity();
    }

    // ==========================================================================
    // Revert Tests - Add Liquidity
    // ==========================================================================

    function test_addLiquidity_revertsWhenValueLessThanAmount() public {
        uint256 ethAmount = 10 ether;
        uint256 tokenAmount = 10 ether;
        uint256 incorrectValue = 5 ether; // Less than ethAmount

        uint256[] memory amounts = _makeAmounts(ethAmount, tokenAmount);
        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        vm.expectRevert(Liquidity.AmountValueMismatch.selector);
        hooks.addLiquidity{value: incorrectValue}(amounts, minAmounts, 0);
    }

    function test_addLiquidity_revertsWhenValueGreaterThanAmount() public {
        uint256 ethAmount = 10 ether;
        uint256 tokenAmount = 10 ether;
        uint256 incorrectValue = 15 ether; // Greater than ethAmount

        uint256[] memory amounts = _makeAmounts(ethAmount, tokenAmount);
        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        vm.expectRevert(Liquidity.AmountValueMismatch.selector);
        hooks.addLiquidity{value: incorrectValue}(amounts, minAmounts, 0);
    }

    function test_addLiquidity_revertsWhenValueIsZeroButAmountIsNot() public {
        uint256 ethAmount = 10 ether;
        uint256 tokenAmount = 10 ether;

        uint256[] memory amounts = _makeAmounts(ethAmount, tokenAmount);
        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        vm.expectRevert(Liquidity.AmountValueMismatch.selector);
        hooks.addLiquidity(amounts, minAmounts, 0); // No value sent
    }

    // ==========================================================================
    // Tests - ETH Refund on Add Liquidity
    // ==========================================================================

    function test_addLiquidity_noRefundWhenActualEqualsAmount() public {
        uint256[] memory quotedAmounts = _makeAmounts(15 ether, 15 ether);
        (, uint256[] memory expectedActualAmounts) = hooks.quoteAddLiquidity(quotedAmounts);

        uint256 ethAmount = expectedActualAmounts[0];
        uint256 tokenAmount = expectedActualAmounts[1];

        uint256 ethBefore = liquidityProvider.balance;

        _addLiquidity(ethAmount, tokenAmount);

        uint256 ethAfter = liquidityProvider.balance;
        uint256 actualEthSpent = ethBefore - ethAfter;

        assertEq(actualEthSpent, ethAmount, "No refund when actual == amount");
    }

    function test_addLiquidity_refundsWhenActualLessThanAmount() public {
        uint256 ethAmount = 20 ether;
        uint256 tokenAmount = 10 ether;

        uint256[] memory amounts = _makeAmounts(ethAmount, tokenAmount);
        (, uint256[] memory expectedActualAmounts) = hooks.quoteAddLiquidity(amounts);

        assertLt(expectedActualAmounts[0], ethAmount, "Expected refund path");

        uint256 ethBefore = liquidityProvider.balance;

        _addLiquidity(ethAmount, tokenAmount);

        uint256 ethAfter = liquidityProvider.balance;
        uint256 actualEthSpent = ethBefore - ethAfter;

        assertEq(actualEthSpent, expectedActualAmounts[0], "Spend only actual ETH");
        assertLt(actualEthSpent, ethAmount, "Refund excess ETH");
    }

    function testFuzz_addLiquidity_refundsExcessEth(uint96 _ethAmount, uint96 _tokenAmount) public {
        uint256 ethAmount = bound(uint256(_ethAmount), 10 ether, 1000 ether);
        uint256 tokenAmount = bound(uint256(_tokenAmount), 10 ether, 1000 ether);

        // Quote to get expected actual amounts
        uint256[] memory amounts = _makeAmounts(ethAmount, tokenAmount);
        (, uint256[] memory expectedActualAmounts) = hooks.quoteAddLiquidity(amounts);

        uint256 expectedEthUsed = expectedActualAmounts[0];

        uint256 ethBefore = liquidityProvider.balance;

        _addLiquidity(ethAmount, tokenAmount);

        uint256 ethAfter = liquidityProvider.balance;
        uint256 actualEthSpent = ethBefore - ethAfter;

        // Should only spend the actual amount needed
        assertEq(actualEthSpent, expectedEthUsed, "Should only spend actual ETH needed");

        // Pool has equal reserves, so:
        // - If ethAmount > tokenAmount: token is limiting factor, ETH refund occurs
        // - If ethAmount <= tokenAmount: ETH is limiting factor, no refund
        if (ethAmount > tokenAmount) {
            assertLt(actualEthSpent, ethAmount, "Should refund when ETH > token");
        } else {
            assertEq(actualEthSpent, ethAmount, "Should use all ETH when ETH <= token");
        }
    }

    /// @notice Verifies reentrancy is blocked during ETH refund
    /// @dev Flow: attack() -> addLiquidity() -> refund via sendValue() -> receive() -> addLiquidity() -> REVERTS
    /// The PoolManager lock prevents nested unlock() calls, reverting with AlreadyUnlocked
    function test_addLiquidity_reentrancyProtected() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(hooks, token);

        // Use more ETH than tokens to trigger a refund
        uint256 ethAmount = 100 ether;
        uint256 tokenAmount = 50 ether;
        vm.deal(address(attacker), ethAmount);
        token.mint(address(attacker), tokenAmount);

        vm.expectRevert(IPoolManager.AlreadyUnlocked.selector);
        attacker.attack(ethAmount, tokenAmount);
    }

    // ==========================================================================
    // Fuzz Tests - Add Liquidity
    // ==========================================================================

    function testFuzz_addLiquidity_withNativeEth(uint96 _ethAmount, uint96 _tokenAmount) public {
        // Bound to reasonable amounts (0.01 to 1000 tokens)
        uint256 ethAmount = bound(uint256(_ethAmount), 0.01 ether, 1000 ether);
        uint256 tokenAmount = bound(uint256(_tokenAmount), 0.01 ether, 1000 ether);

        uint256 lpBefore = hooks.balanceOf(liquidityProvider);
        uint256 ethBefore = liquidityProvider.balance;
        uint256 tokenBefore = token.balanceOf(liquidityProvider);

        _addLiquidity(ethAmount, tokenAmount);

        uint256 lpAfter = hooks.balanceOf(liquidityProvider);
        uint256 ethAfter = liquidityProvider.balance;
        uint256 tokenAfter = token.balanceOf(liquidityProvider);

        // Should receive LP tokens
        assertGt(lpAfter, lpBefore, "Should receive LP tokens");

        // Should spend ETH (may be less than requested due to proportional deposits)
        assertLe(ethAfter, ethBefore, "Should spend ETH");

        // Should spend tokens
        assertLe(tokenAfter, tokenBefore, "Should spend tokens");
    }

    function testFuzz_addLiquidity_proportionalDeposit(uint96 _amount) public {
        // Bound to reasonable amounts
        uint256 amount = bound(uint256(_amount), 0.01 ether, 100 ether);

        // Get current reserves ratio
        uint256 reserve0 = hooks.reserves(0);
        uint256 reserve1 = hooks.reserves(1);
        uint256 ratio = (reserve1 * 1e18) / reserve0;

        // Calculate proportional amounts
        uint256 ethAmount = amount;
        uint256 tokenAmount = (amount * ratio) / 1e18;

        (uint256 expectedShares, uint256[] memory expectedAmounts) =
            hooks.quoteAddLiquidity(_makeAmounts(ethAmount, tokenAmount));

        _addLiquidity(ethAmount, tokenAmount);

        // For proportional deposits, actual amounts should match expected
        assertApproxEqRel(expectedAmounts[0], ethAmount, 0.01e18, "ETH amount should be close to requested");
        assertApproxEqRel(expectedAmounts[1], tokenAmount, 0.01e18, "Token amount should be close to requested");
        assertGt(expectedShares, 0, "Should receive shares");
    }

    // ==========================================================================
    // Fuzz Tests - Remove Liquidity
    // ==========================================================================

    function testFuzz_removeLiquidity_partialWithdraw(uint96 _sharesFraction) public {
        // Bound to 1-99% of LP balance
        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 shares = bound(uint256(_sharesFraction), lpBalance / 100, (lpBalance * 99) / 100);

        uint256 ethBefore = liquidityProvider.balance;
        uint256 tokenBefore = token.balanceOf(liquidityProvider);
        uint256 lpBefore = hooks.balanceOf(liquidityProvider);

        // Quote expected amounts
        uint256[] memory expectedAmounts = hooks.quoteRemoveLiquidity(shares);

        _removeLiquidity(shares);

        uint256 ethAfter = liquidityProvider.balance;
        uint256 tokenAfter = token.balanceOf(liquidityProvider);
        uint256 lpAfter = hooks.balanceOf(liquidityProvider);

        // Should burn LP tokens
        assertEq(lpBefore - lpAfter, shares, "Should burn exact shares");

        // Should receive ETH
        assertEq(ethAfter - ethBefore, expectedAmounts[0], "Should receive expected ETH");

        // Should receive tokens
        assertEq(tokenAfter - tokenBefore, expectedAmounts[1], "Should receive expected tokens");
    }

    function testFuzz_removeLiquidity_fullWithdraw(uint96 _additionalDeposit) public {
        uint256 additionalDeposit = bound(uint256(_additionalDeposit), 1 ether, 100 ether);

        // Add more liquidity
        _addLiquidity(additionalDeposit, additionalDeposit);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 ethBefore = liquidityProvider.balance;
        uint256 tokenBefore = token.balanceOf(liquidityProvider);

        // Remove all liquidity
        uint256[] memory minAmounts = new uint256[](2);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(lpBalance, minAmounts);

        assertEq(hooks.balanceOf(liquidityProvider), 0, "Should have no LP tokens left");
        assertGt(liquidityProvider.balance, ethBefore, "Should have received ETH back");
        assertGt(token.balanceOf(liquidityProvider), tokenBefore, "Should have received tokens back");
    }

    // ==========================================================================
    // Fuzz Tests - Exact Input Swaps
    // ==========================================================================

    function testFuzz_exactInputSwap_ethToToken(uint96 _amountIn) public {
        // Bound to reasonable swap size (0.001 to 100 ETH)
        uint256 amountIn = bound(uint256(_amountIn), 0.001 ether, 100 ether);

        uint256 ethBefore = swapper.balance;
        uint256 tokenBefore = token.balanceOf(swapper);

        _executeExactInputSwap(true, amountIn);

        uint256 ethAfter = swapper.balance;
        uint256 tokenAfter = token.balanceOf(swapper);

        // Should spend ETH
        assertEq(ethBefore - ethAfter, amountIn, "Should spend exact ETH amount");

        // Should receive tokens
        assertGt(tokenAfter - tokenBefore, 0, "Should receive tokens");
    }

    function testFuzz_exactInputSwap_tokenToEth(uint96 _amountIn) public {
        // Bound to reasonable swap size
        uint256 amountIn = bound(uint256(_amountIn), 0.001 ether, 100 ether);

        uint256 ethBefore = swapper.balance;
        uint256 tokenBefore = token.balanceOf(swapper);

        _executeExactInputSwap(false, amountIn);

        uint256 ethAfter = swapper.balance;
        uint256 tokenAfter = token.balanceOf(swapper);

        // Should spend tokens
        assertEq(tokenBefore - tokenAfter, amountIn, "Should spend exact token amount");

        // Should receive ETH
        assertGt(ethAfter - ethBefore, 0, "Should receive ETH");
    }

    // ==========================================================================
    // Fuzz Tests - Exact Output Swaps
    // ==========================================================================

    function testFuzz_exactOutputSwap_ethToToken(uint96 _amountOut) public {
        uint256 maxAmountOut = (hooks.reserves(1) * 99) / 100;
        uint256 amountOut = bound(uint256(_amountOut), 1, maxAmountOut);

        V4Quoter quoter = new V4Quoter(IPoolManager(poolManager));

        (uint256 quotedAmountIn,) = quoter.quoteExactOutputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: _getPoolKey(), zeroForOne: true, exactAmount: uint128(amountOut), hookData: bytes("")
            })
        );
        uint256 amountInMaximum = quotedAmountIn * 3;

        vm.deal(swapper, amountInMaximum);

        uint256 ethBefore = swapper.balance;
        uint256 tokenBefore = token.balanceOf(swapper);

        _executeExactOutputSwap(true, amountOut, amountInMaximum);

        uint256 ethAfter = swapper.balance;
        uint256 tokenAfter = token.balanceOf(swapper);

        // Should receive exact token amount
        assertEq(tokenAfter - tokenBefore, amountOut, "Should receive exact token amount");

        // Should only spend quoted ETH amount and refund extra
        assertEq(ethBefore - ethAfter, quotedAmountIn, "Should spend quoted ETH amount");
        assertGt(amountInMaximum, quotedAmountIn, "Should send more ETH than needed");
    }

    function testFuzz_exactOutputSwap_tokenToEth(uint96 _amountOut) public {
        // Bound to reasonable output
        uint256 amountOut = bound(uint256(_amountOut), 0.001 ether, 50 ether);

        uint256 ethBefore = swapper.balance;
        uint256 tokenBefore = token.balanceOf(swapper);

        _executeExactOutputSwap(false, amountOut, 0);

        uint256 ethAfter = swapper.balance;
        uint256 tokenAfter = token.balanceOf(swapper);

        // Should receive exact ETH amount
        assertEq(ethAfter - ethBefore, amountOut, "Should receive exact ETH amount");

        // Should spend some tokens
        assertGt(tokenBefore - tokenAfter, 0, "Should spend tokens");
    }

    // ==========================================================================
    // Invariant-style Fuzz Tests
    // ==========================================================================

    function testFuzz_reservesNeverNegative(uint96 _ethAmount, uint96 _tokenAmount, bool _isSwap) public {
        uint256 ethAmount = bound(uint256(_ethAmount), 0.01 ether, 100 ether);
        uint256 tokenAmount = bound(uint256(_tokenAmount), 0.01 ether, 100 ether);

        if (_isSwap) {
            // Do a swap
            uint256 swapAmount = bound(ethAmount, 0.001 ether, 10 ether);
            _executeExactInputSwap(true, swapAmount);
        } else {
            // Add liquidity
            _addLiquidity(ethAmount, tokenAmount);
        }

        // Reserves should always be positive
        assertGt(hooks.reserves(0), 0, "ETH reserve should be positive");
        assertGt(hooks.reserves(1), 0, "Token reserve should be positive");
    }

    function testFuzz_lpTokensMatchReserves(uint96 _depositAmount) public {
        uint256 depositAmount = bound(uint256(_depositAmount), 1 ether, 100 ether);

        // Get state before
        uint256 totalSupplyBefore = hooks.totalSupply();
        uint256 reserve0Before = hooks.reserves(0);
        uint256 reserve1Before = hooks.reserves(1);

        // Add liquidity
        _addLiquidity(depositAmount, depositAmount);

        // Get state after
        uint256 totalSupplyAfter = hooks.totalSupply();
        uint256 reserve0After = hooks.reserves(0);
        uint256 reserve1After = hooks.reserves(1);

        // LP tokens should increase proportionally with reserves
        uint256 supplyRatio = (totalSupplyAfter * 1e18) / totalSupplyBefore;
        uint256 reserve0Ratio = (reserve0After * 1e18) / reserve0Before;
        uint256 reserve1Ratio = (reserve1After * 1e18) / reserve1Before;

        // Ratios should be similar (within 0.01%)
        assertApproxEqRel(supplyRatio, reserve0Ratio, 0.0001e18, "Supply should grow with reserve0");
        assertApproxEqRel(supplyRatio, reserve1Ratio, 0.0001e18, "Supply should grow with reserve1");
    }

    // ==========================================================================
    // Fuzz Tests - Large Amounts (Overflow Protection)
    // ==========================================================================

    function testFuzz_addLiquidity_largeAmounts(uint128 _ethAmount, uint128 _tokenAmount) public {
        // Use uint128 to allow very large amounts (up to ~340 undecillion wei)
        // Bound to at least 1 ETH and up to 100 billion ETH (more than total supply)
        uint256 ethAmount = bound(uint256(_ethAmount), 1 ether, 100_000_000_000 ether);
        uint256 tokenAmount = bound(uint256(_tokenAmount), 1 ether, 100_000_000_000 ether);

        // Deal large amounts
        vm.deal(liquidityProvider, ethAmount);
        token.mint(liquidityProvider, tokenAmount);

        uint256 lpBefore = hooks.balanceOf(liquidityProvider);

        _addLiquidity(ethAmount, tokenAmount);

        uint256 lpAfter = hooks.balanceOf(liquidityProvider);

        // Should receive LP tokens without overflow
        assertGt(lpAfter, lpBefore, "Should receive LP tokens");

        // Reserves should be updated correctly
        assertGt(hooks.reserves(0), 0, "ETH reserve should be positive");
        assertGt(hooks.reserves(1), 0, "Token reserve should be positive");
    }

    function testFuzz_swap_largeAmounts(uint128 _amountIn) public {
        // First add large liquidity to support large swaps
        uint256 largeLiquidity = 100_000_000_000 ether; // 100 billion
        vm.deal(liquidityProvider, largeLiquidity);
        token.mint(liquidityProvider, largeLiquidity);
        _addLiquidity(largeLiquidity, largeLiquidity);

        // Bound swap to 0.1% to 100% of pool
        uint256 amountIn = bound(uint256(_amountIn), largeLiquidity / 1000, largeLiquidity);

        // Deal swap amount to swapper
        vm.deal(swapper, amountIn);

        uint256 tokenBefore = token.balanceOf(swapper);

        _executeExactInputSwap(true, amountIn);

        uint256 tokenAfter = token.balanceOf(swapper);

        // Should receive tokens without overflow
        assertGt(tokenAfter, tokenBefore, "Should receive tokens");

        // Reserves should remain positive even after large swap
        assertGt(hooks.reserves(0), 0, "ETH reserve should remain positive");
        assertGt(hooks.reserves(1), 0, "Token reserve should remain positive");
    }

    function testFuzz_removeLiquidity_largeAmounts(uint128 _depositAmount) public {
        // Use large deposit amounts
        uint256 depositAmount = bound(uint256(_depositAmount), 1_000 ether, 100_000_000_000 ether);

        // Deal large amounts
        vm.deal(liquidityProvider, depositAmount);
        token.mint(liquidityProvider, depositAmount);

        _addLiquidity(depositAmount, depositAmount);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        uint256 ethBefore = liquidityProvider.balance;
        uint256 tokenBefore = token.balanceOf(liquidityProvider);

        // Remove all liquidity
        uint256[] memory minAmounts = new uint256[](2);
        vm.prank(liquidityProvider);
        hooks.removeLiquidity(lpBalance, minAmounts);

        // Should receive back tokens without overflow
        assertGt(liquidityProvider.balance, ethBefore, "Should receive ETH back");
        assertGt(token.balanceOf(liquidityProvider), tokenBefore, "Should receive tokens back");
        assertEq(hooks.balanceOf(liquidityProvider), 0, "Should have no LP tokens left");
    }

    // ==========================================================================
    // Tests - Fee Withdrawal with Native ETH
    // ==========================================================================

    function test_withdrawProtocolFees_withNativeEth() public {
        // Set up protocol fees
        uint256 protocolFeePercentage = 1000; // 0.1%
        vm.prank(admin);
        hooks.setProtocolFeePercentage(protocolFeePercentage);

        // Do swaps to accumulate fees
        uint256 swapAmount = 100 ether;
        vm.deal(swapper, swapAmount);
        _executeExactInputSwap(true, swapAmount); // ETH -> Token

        // Check protocol fees accumulated
        uint256 protocolFeeEth = hooks.protocolFees(0);
        uint256 protocolFeeToken = hooks.protocolFees(1);
        assertGt(protocolFeeEth + protocolFeeToken, 0, "Should have accumulated fees");

        // Get protocol fee collector
        address protocolFeeCollector = factory.protocolFeeCollector();
        uint256 collectorEthBefore = protocolFeeCollector.balance;
        uint256 collectorTokenBefore = token.balanceOf(protocolFeeCollector);

        // Withdraw protocol fees
        hooks.withdrawProtocolFees();

        // Verify ETH was received
        uint256 collectorEthAfter = protocolFeeCollector.balance;
        uint256 collectorTokenAfter = token.balanceOf(protocolFeeCollector);

        assertEq(collectorEthAfter - collectorEthBefore, protocolFeeEth, "Should receive ETH fees");
        assertEq(collectorTokenAfter - collectorTokenBefore, protocolFeeToken, "Should receive token fees");

        // Verify fees were cleared
        assertEq(hooks.protocolFees(0), 0, "ETH protocol fees should be cleared");
        assertEq(hooks.protocolFees(1), 0, "Token protocol fees should be cleared");
    }

    function test_withdrawHookFees_withNativeEth() public {
        // Set up hook fees
        uint256 hookFeePercentage = 1000; // 0.1%
        vm.prank(admin);
        hooks.setHookFeePercentage(hookFeePercentage);

        // Do swaps to accumulate fees
        uint256 swapAmount = 100 ether;
        vm.deal(swapper, swapAmount);
        _executeExactInputSwap(true, swapAmount); // ETH -> Token

        // Check hook fees accumulated
        uint256 hookFeeEth = hooks.hookFees(0);
        uint256 hookFeeToken = hooks.hookFees(1);
        assertGt(hookFeeEth + hookFeeToken, 0, "Should have accumulated fees");

        // Get hook fee collector
        address hookFeeCollector = factory.hookFeeCollector();
        uint256 collectorEthBefore = hookFeeCollector.balance;
        uint256 collectorTokenBefore = token.balanceOf(hookFeeCollector);

        // Withdraw hook fees
        hooks.withdrawHookFees();

        // Verify ETH was received
        uint256 collectorEthAfter = hookFeeCollector.balance;
        uint256 collectorTokenAfter = token.balanceOf(hookFeeCollector);

        assertEq(collectorEthAfter - collectorEthBefore, hookFeeEth, "Should receive ETH fees");
        assertEq(collectorTokenAfter - collectorTokenBefore, hookFeeToken, "Should receive token fees");

        // Verify fees were cleared
        assertEq(hooks.hookFees(0), 0, "ETH hook fees should be cleared");
        assertEq(hooks.hookFees(1), 0, "Token hook fees should be cleared");
    }

    // ==========================================================================
    // Internal Helpers
    // ==========================================================================

    function _deployHooks() private {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = nativeEth; // address(0) < any ERC20 address
        currencies[1] = tokenCurrency;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, code);

        hooks = StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, salt, code));
    }

    function _dealTokens() private {
        vm.deal(liquidityProvider, INITIAL_LIQUIDITY * 10);
        token.mint(liquidityProvider, INITIAL_LIQUIDITY * 10);

        vm.deal(swapper, 1000 ether);
        token.mint(swapper, 1000 ether);

        vm.prank(liquidityProvider);
        token.approve(address(hooks), type(uint256).max);

        vm.startPrank(swapper);
        token.approve(address(permit2), type(uint256).max);
        permit2.approve(address(token), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _addInitialLiquidity() private {
        uint256[] memory amounts = _makeAmounts(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.addLiquidity{value: INITIAL_LIQUIDITY}(amounts, minAmounts, 0);
    }

    function _addLiquidity(uint256 _ethAmount, uint256 _tokenAmount) internal {
        uint256[] memory amounts = _makeAmounts(_ethAmount, _tokenAmount);
        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.addLiquidity{value: _ethAmount}(amounts, minAmounts, 0);
    }

    function _removeLiquidity(uint256 _shares) internal {
        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.removeLiquidity(_shares, minAmounts);
    }

    function _makeAmounts(uint256 _eth, uint256 _token) internal pure returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _eth;
        amounts[1] = _token;
        return amounts;
    }

    function _getPoolKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: nativeEth,
            currency1: tokenCurrency,
            fee: uint24(LP_FEE_PERCENTAGE),
            tickSpacing: hooks.TICK_SPACING(),
            hooks: IHooks(address(hooks))
        });
    }

    function _executeExactInputSwap(bool _zeroForOne, uint256 _amountIn) internal returns (uint256 amountOut) {
        PoolKey memory poolKey = _getPoolKey();

        Currency inputCurrency = _zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = _zeroForOne ? poolKey.currency1 : poolKey.currency0;

        uint256 outputBefore = _getBalance(outputCurrency, swapper);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: _zeroForOne,
                amountIn: uint128(_amountIn),
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(inputCurrency, _amountIn);
        params[2] = abi.encode(outputCurrency, 0);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        uint256 value = _zeroForOne ? _amountIn : 0;

        vm.prank(swapper);
        universalRouter.execute{value: value}(commands, inputs, block.timestamp + 100);

        amountOut = _getBalance(outputCurrency, swapper) - outputBefore;
    }

    function _executeExactOutputSwap(bool _zeroForOne, uint256 _amountOut, uint256 _amountInMaximum) internal {
        PoolKey memory poolKey = _getPoolKey();

        Currency inputCurrency = _zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = _zeroForOne ? poolKey.currency1 : poolKey.currency0;

        uint256 maxInput = _amountInMaximum > 0 ? _amountInMaximum : (_zeroForOne ? _amountOut * 3 : type(uint128).max);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: poolKey,
                zeroForOne: _zeroForOne,
                amountOut: uint128(_amountOut),
                amountInMaximum: uint128(maxInput),
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(inputCurrency, maxInput);
        params[2] = abi.encode(outputCurrency, _amountOut);

        bytes memory commands;
        bytes[] memory inputs;

        if (_zeroForOne) {
            // Add SWEEP command to return unused ETH
            commands = abi.encodePacked(uint8(Commands.V4_SWAP), uint8(Commands.SWEEP));
            inputs = new bytes[](2);
            inputs[0] = abi.encode(actions, params);
            inputs[1] = abi.encode(address(0), swapper, 0);
        } else {
            commands = abi.encodePacked(uint8(Commands.V4_SWAP));
            inputs = new bytes[](1);
            inputs[0] = abi.encode(actions, params);
        }

        uint256 value = _zeroForOne ? maxInput : 0;

        vm.prank(swapper);
        universalRouter.execute{value: value}(commands, inputs, block.timestamp + 100);
    }

    function _getBalance(Currency _currency, address _account) internal view returns (uint256) {
        if (_currency.isAddressZero()) {
            return _account.balance;
        }
        return IERC20(Currency.unwrap(_currency)).balanceOf(_account);
    }
}

/// @notice Malicious contract that attempts reentrancy during ETH refund
/// @dev When ETH is refunded via Address.sendValue(), receive() triggers and attempts to re-enter addLiquidity()
contract ReentrancyAttacker {
    StableSwapHooks private hooks;

    constructor(StableSwapHooks _hooks, MockERC20 _token) {
        hooks = _hooks;
        _token.approve(address(_hooks), type(uint256).max);
    }

    /// @notice Entry point - calls addLiquidity with more ETH than tokens to trigger refund
    function attack(uint256 _ethAmount, uint256 _tokenAmount) external {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _ethAmount;
        amounts[1] = _tokenAmount;
        hooks.addLiquidity{value: _ethAmount}(amounts, new uint256[](2), 0);
    }

    /// @notice Called when receiving ETH refund - attempts reentrancy
    receive() external payable {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = msg.value;
        hooks.addLiquidity{value: msg.value}(amounts, new uint256[](2), 0);
    }
}

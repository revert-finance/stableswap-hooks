// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";
import {StableSwapHooksFactoryHarness} from "test/testUtils/StableSwapHooksFactoryHarness.sol";
import {console} from "forge-std/console.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";

/// @notice Tests swap slippage behavior at different amplification coefficient values
/// @dev Uses currency1 (USDC) and currency2 (USDT) which both have 6 decimals for simpler slippage math
contract AmplificationExtremesTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 internal constant LP_FEE_PERCENTAGE = 300;
    uint256 internal constant LIQUIDITY_AMOUNT = 1_000_000;
    uint256 internal constant SWAP_AMOUNT = 100_000;

    uint256 internal constant AMP_LOW = 1;
    uint256 internal constant AMP_MEDIUM = 100;
    uint256 internal constant AMP_HIGH = 999_999;

    // Use USDC and USDT (both 6 decimals) for simpler slippage calculations
    Currency internal usdc;
    Currency internal usdt;

    StableSwapHooksFactoryHarness internal factory;
    StableSwapHooks internal hooksLowAmp;
    StableSwapHooks internal hooksMediumAmp;
    StableSwapHooks internal hooksHighAmp;

    address internal liquidityProvider;
    address internal swapper;

    function setUp() public override {
        super.setUp();

        if (block.chainid == 31337) {
            vm.warp(1731337000);
        }

        usdc = currency1;
        usdt = currency2;

        liquidityProvider = makeAddr("liquidityProvider");
        swapper = makeAddr("swapper");

        factory = new StableSwapHooksFactoryHarness(
            IPoolManager(poolManager),
            makeAddr("admin"),
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );

        hooksLowAmp = _deployHooksWithAmp(AMP_LOW);
        hooksMediumAmp = _deployHooksWithAmp(AMP_MEDIUM);
        hooksHighAmp = _deployHooksWithAmp(AMP_HIGH);

        _dealTokens();

        _addLiquidity(hooksLowAmp, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        _addLiquidity(hooksMediumAmp, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
        _addLiquidity(hooksHighAmp, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
    }

    /// @notice Low A behaves like constant product - high slippage on large swaps
    function test_lowAmp_highSlippage() public {
        uint256 amountIn = _toTokenWei(usdc, SWAP_AMOUNT);
        uint256 amountOut = _executeSwapAndGetOutput(hooksLowAmp, true, amountIn);

        uint256 slippageBps = (amountIn - amountOut) * 10000 / amountIn;

        console.log("A=1 Swap Results:");
        console.log("Amount In:   ", amountIn);
        console.log("Amount Out:  ", amountOut);
        console.log("Slippage:    ", slippageBps, "bps");

        // Low A should have noticeable slippage (>0.4% for 1% of pool)
        assertGt(slippageBps, 40);
    }

    /// @notice High A behaves like constant sum - minimal slippage
    function test_highAmp_minimalSlippage() public {
        uint256 amountIn = _toTokenWei(usdc, SWAP_AMOUNT);
        uint256 amountOut = _executeSwapAndGetOutput(hooksHighAmp, true, amountIn);

        uint256 slippageBps = (amountIn - amountOut) * 10000 / amountIn;

        console.log("A=999999 Swap Results:");
        console.log("Amount In:   ", amountIn);
        console.log("Amount Out:  ", amountOut);
        console.log("Slippage:    ", slippageBps, "bps");

        // High A should have minimal slippage (fee only, ~3bps for 0.03% fee)
        assertLt(slippageBps, 10);
    }

    /// @notice Compare slippage across all A values
    function test_slippageComparison_acrossAmpValues() public {
        uint256 amountIn = _toTokenWei(usdc, SWAP_AMOUNT);

        uint256 outLow = _executeSwapAndGetOutput(hooksLowAmp, true, amountIn);
        uint256 outMedium = _executeSwapAndGetOutput(hooksMediumAmp, true, amountIn);
        uint256 outHigh = _executeSwapAndGetOutput(hooksHighAmp, true, amountIn);

        console.log("Slippage Comparison (", SWAP_AMOUNT, " token swap):");
        console.log("A=1:      ", (amountIn - outLow) * 10000 / amountIn, "bps");
        console.log("A=100:    ", (amountIn - outMedium) * 10000 / amountIn, "bps");
        console.log("A=999999: ", (amountIn - outHigh) * 10000 / amountIn, "bps");

        // Higher A = less slippage
        assertGt(outHigh, outMedium);
        assertGt(outMedium, outLow);
    }

    /// @notice Large swap with low A has extreme slippage
    function test_lowAmp_largeSwap_extremeSlippage() public {
        uint256 amountIn = _toTokenWei(usdc, LIQUIDITY_AMOUNT / 2);
        uint256 amountOut = _executeSwapAndGetOutput(hooksLowAmp, true, amountIn);

        uint256 slippageBps = (amountIn - amountOut) * 10000 / amountIn;

        console.log("A=1 Large Swap (50% of liquidity):");
        console.log("Amount In:   ", amountIn);
        console.log("Amount Out:  ", amountOut);
        console.log("Slippage:    ", slippageBps, "bps");

        // 50% swap with A=1 should have significant slippage (>20%)
        assertGt(slippageBps, 2000);
    }

    /// @notice Large swap with high A maintains efficiency
    function test_highAmp_largeSwap_maintainsEfficiency() public {
        uint256 amountIn = _toTokenWei(usdc, LIQUIDITY_AMOUNT / 2);
        uint256 amountOut = _executeSwapAndGetOutput(hooksHighAmp, true, amountIn);

        uint256 slippageBps = (amountIn - amountOut) * 10000 / amountIn;

        console.log("A=999999 Large Swap (50% of liquidity):");
        console.log("Amount In:   ", amountIn);
        console.log("Amount Out:  ", amountOut);
        console.log("Slippage:    ", slippageBps, "bps");

        // 50% swap with max A should still have reasonable slippage (<5%)
        assertLt(slippageBps, 500);
    }

    function _deployHooksWithAmp(uint256 _amp) private returns (StableSwapHooks) {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = usdc;
        currencies[1] = usdt;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, _amp, code);

        return StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, _amp, salt, code));
    }

    function _dealTokens() private {
        uint256 totalNeeded = _toTokenWei(usdc, LIQUIDITY_AMOUNT * 4);

        deal(Currency.unwrap(usdc), liquidityProvider, totalNeeded);
        deal(Currency.unwrap(usdt), liquidityProvider, totalNeeded);
        deal(Currency.unwrap(usdc), swapper, totalNeeded);
        deal(Currency.unwrap(usdt), swapper, totalNeeded);

        vm.startPrank(liquidityProvider);
        IERC20(Currency.unwrap(usdc)).forceApprove(address(hooksLowAmp), type(uint256).max);
        IERC20(Currency.unwrap(usdt)).forceApprove(address(hooksLowAmp), type(uint256).max);
        IERC20(Currency.unwrap(usdc)).forceApprove(address(hooksMediumAmp), type(uint256).max);
        IERC20(Currency.unwrap(usdt)).forceApprove(address(hooksMediumAmp), type(uint256).max);
        IERC20(Currency.unwrap(usdc)).forceApprove(address(hooksHighAmp), type(uint256).max);
        IERC20(Currency.unwrap(usdt)).forceApprove(address(hooksHighAmp), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper);
        IERC20(Currency.unwrap(usdc)).forceApprove(address(permit2), type(uint256).max);
        IERC20(Currency.unwrap(usdt)).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(usdc), address(universalRouter), type(uint160).max, type(uint48).max);
        permit2.approve(Currency.unwrap(usdt), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _toTokenWei(Currency _currency, uint256 _amount) internal view returns (uint256) {
        return _amount * 10 ** IERC20Metadata(Currency.unwrap(_currency)).decimals();
    }

    function _addLiquidity(StableSwapHooks _hooks, uint256 _amount0, uint256 _amount1) internal {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(usdc, _amount0);
        amounts[1] = _toTokenWei(usdt, _amount1);

        uint256[] memory minAmounts = new uint256[](2);

        vm.startPrank(liquidityProvider);
        IERC20(Currency.unwrap(usdc)).forceApprove(address(_hooks), type(uint256).max);
        IERC20(Currency.unwrap(usdt)).forceApprove(address(_hooks), type(uint256).max);
        _hooks.addLiquidity(amounts, minAmounts, 0);
        vm.stopPrank();
    }

    function _getPoolKey(StableSwapHooks _hooks) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: usdc,
            currency1: usdt,
            fee: uint24(LP_FEE_PERCENTAGE),
            tickSpacing: _hooks.TICK_SPACING(),
            hooks: IHooks(address(_hooks))
        });
    }

    function _executeSwapAndGetOutput(StableSwapHooks _hooks, bool _zeroForOne, uint256 _amountIn)
        internal
        returns (uint256 amountOut)
    {
        PoolKey memory poolKey = _getPoolKey(_hooks);

        Currency inputCurrency = _zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = _zeroForOne ? poolKey.currency1 : poolKey.currency0;

        uint256 outputBefore = IERC20(Currency.unwrap(outputCurrency)).balanceOf(swapper);

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

        vm.prank(swapper);
        universalRouter.execute(commands, inputs, block.timestamp + 100);

        uint256 outputAfter = IERC20(Currency.unwrap(outputCurrency)).balanceOf(swapper);
        amountOut = outputAfter - outputBefore;
    }
}

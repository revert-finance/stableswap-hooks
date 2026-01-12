// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IWstETH} from "lib/uniswap-hooks/lib/v4-periphery/src/interfaces/external/IWstETH.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";
import {console} from "forge-std/console.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";

/// @notice Tests WETH/wstETH pool with rate oracle on mainnet fork
/// @dev This test only runs on mainnet fork (chainid == 1)
/// @dev wstETH (0x7f39...) < WETH (0xC02a...), so wsteth is currency0
contract WethWstethRateOracleTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    address internal constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant LP_FEE_PERCENTAGE = 300;
    uint256 internal constant AMP = 100;
    uint256 internal constant LIQUIDITY_AMOUNT = 1000 ether;
    uint256 internal constant SWAP_AMOUNT = 1 ether;

    StableSwapHooksFactory internal factory;
    StableSwapHooks internal hooks;

    Currency internal wsteth;
    Currency internal weth;

    address internal admin;
    address internal liquidityProvider;
    address internal swapper;

    modifier onlyMainnet() {
        vm.skip(block.chainid != 1);
        _;
    }

    function setUp() public override {
        super.setUp();

        if (block.chainid != 1) {
            return;
        }

        wsteth = Currency.wrap(WSTETH_ADDRESS);
        weth = Currency.wrap(WETH_ADDRESS);

        admin = makeAddr("admin");
        liquidityProvider = makeAddr("liquidityProvider");
        swapper = makeAddr("swapper");

        factory = new StableSwapHooksFactory(
            IPoolManager(poolManager),
            admin,
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );

        _deployHooks();
        _dealTokens();
    }

    function test_rateOracle_wstethExchangeRate() public onlyMainnet {
        uint256 rate = IWstETH(Currency.unwrap(wsteth)).stEthPerToken();
        console.log("wstETH exchange rate (stETH per wstETH):", rate);
        assertGt(rate, 1e18);
    }

    function test_rateOracle_addLiquidity() public onlyMainnet {
        uint256 rate = IWstETH(Currency.unwrap(wsteth)).stEthPerToken();

        uint256 wethAmount = LIQUIDITY_AMOUNT;
        uint256 wstethAmount = (LIQUIDITY_AMOUNT * 1e18) / rate;

        _addLiquidity(wstethAmount, wethAmount);

        uint256 lpBalance = hooks.balanceOf(liquidityProvider);
        console.log("LP tokens received:", lpBalance);
        assertGt(lpBalance, 0);
    }

    function test_rateOracle_quoteAddLiquidity_imbalancedDeposit() public onlyMainnet {
        uint256 rate = IWstETH(Currency.unwrap(wsteth)).stEthPerToken();

        // First deposit: proportional amounts
        uint256 wethAmount = LIQUIDITY_AMOUNT;
        uint256 wstethAmount = (LIQUIDITY_AMOUNT * 1e18) / rate;
        _addLiquidity(wstethAmount, wethAmount);

        // Second deposit: equal amounts (100 each)
        uint256 depositAmount = 100 ether;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = depositAmount; // wsteth
        amounts[1] = depositAmount; // weth

        (uint256 shares, uint256[] memory actualAmounts) = hooks.quoteAddLiquidity(amounts);

        console.log("Quote for 100 wstETH + 100 WETH:");
        console.log("Shares:              ", shares);
        console.log("Actual wstETH used:  ", actualAmounts[0]);
        console.log("Actual WETH used:    ", actualAmounts[1]);
        console.log("Exchange Rate:       ", rate);

        assertGt(shares, 0);
        // Since wstETH is worth more than WETH (rate > 1e18), less wstETH is needed
        assertLt(actualAmounts[0], actualAmounts[1]);
    }

    function test_rateOracle_swapWethToWsteth() public onlyMainnet {
        uint256 rate = IWstETH(Currency.unwrap(wsteth)).stEthPerToken();

        uint256 wethAmount = LIQUIDITY_AMOUNT;
        uint256 wstethAmount = (LIQUIDITY_AMOUNT * 1e18) / rate;
        _addLiquidity(wstethAmount, wethAmount);

        // zeroForOne=false means WETH -> wstETH
        uint256 amountOut = _executeSwap(false, SWAP_AMOUNT);

        uint256 expectedOut = (SWAP_AMOUNT * 1e18) / rate;

        console.log("Swap: WETH -> wstETH");
        console.log("Amount In (WETH):      ", SWAP_AMOUNT);
        console.log("Amount Out (wstETH):   ", amountOut);
        console.log("Expected Out (approx): ", expectedOut);
        console.log("Exchange Rate:         ", rate);

        assertGt(amountOut, 0);
        assertApproxEqRel(amountOut, expectedOut, 0.01e18);
    }

    function test_rateOracle_swapWstethToWeth() public onlyMainnet {
        uint256 rate = IWstETH(Currency.unwrap(wsteth)).stEthPerToken();

        uint256 wethAmount = LIQUIDITY_AMOUNT;
        uint256 wstethAmount = (LIQUIDITY_AMOUNT * 1e18) / rate;
        _addLiquidity(wstethAmount, wethAmount);

        // zeroForOne=true means wstETH -> WETH
        uint256 amountOut = _executeSwap(true, SWAP_AMOUNT);

        uint256 expectedOut = (SWAP_AMOUNT * rate) / 1e18;

        console.log("Swap: wstETH -> WETH");
        console.log("Amount In (wstETH):    ", SWAP_AMOUNT);
        console.log("Amount Out (WETH):     ", amountOut);
        console.log("Expected Out (approx): ", expectedOut);
        console.log("Exchange Rate:         ", rate);

        assertGt(amountOut, 0);
        assertApproxEqRel(amountOut, expectedOut, 0.01e18);
    }

    function test_rateOracle_exactOut_swapWethToWsteth() public onlyMainnet {
        uint256 rate = IWstETH(Currency.unwrap(wsteth)).stEthPerToken();

        uint256 wethAmount = LIQUIDITY_AMOUNT;
        uint256 wstethAmount = (LIQUIDITY_AMOUNT * 1e18) / rate;
        _addLiquidity(wstethAmount, wethAmount);

        // zeroForOne=false means WETH -> wstETH
        uint256 amountIn = _executeExactOutputSwap(false, SWAP_AMOUNT);

        // To get 1 wstETH out, we need approximately rate WETH in
        uint256 expectedIn = (SWAP_AMOUNT * rate) / 1e18;

        console.log("Exact Out Swap: WETH -> wstETH");
        console.log("Amount Out (wstETH):  ", SWAP_AMOUNT);
        console.log("Amount In (WETH):     ", amountIn);
        console.log("Expected In (approx): ", expectedIn);
        console.log("Exchange Rate:        ", rate);

        assertGt(amountIn, 0);
        assertApproxEqRel(amountIn, expectedIn, 0.01e18);
    }

    function test_rateOracle_exactOut_swapWstethToWeth() public onlyMainnet {
        uint256 rate = IWstETH(Currency.unwrap(wsteth)).stEthPerToken();

        uint256 wethAmount = LIQUIDITY_AMOUNT;
        uint256 wstethAmount = (LIQUIDITY_AMOUNT * 1e18) / rate;
        _addLiquidity(wstethAmount, wethAmount);

        // zeroForOne=true means wstETH -> WETH
        uint256 amountIn = _executeExactOutputSwap(true, SWAP_AMOUNT);

        // To get 1 WETH out, we need approximately 1/rate wstETH in
        uint256 expectedIn = (SWAP_AMOUNT * 1e18) / rate;

        console.log("Exact Out Swap: wstETH -> WETH");
        console.log("Amount Out (WETH):     ", SWAP_AMOUNT);
        console.log("Amount In (wstETH):    ", amountIn);
        console.log("Expected In (approx):  ", expectedIn);
        console.log("Exchange Rate:         ", rate);

        assertGt(amountIn, 0);
        assertApproxEqRel(amountIn, expectedIn, 0.01e18);
    }

    function test_rateOracle_roundTripSwap() public onlyMainnet {
        uint256 rate = IWstETH(Currency.unwrap(wsteth)).stEthPerToken();

        uint256 wethAmount = LIQUIDITY_AMOUNT;
        uint256 wstethAmount = (LIQUIDITY_AMOUNT * 1e18) / rate;
        _addLiquidity(wstethAmount, wethAmount);

        uint256 wethBefore = IERC20(Currency.unwrap(weth)).balanceOf(swapper);

        // WETH -> wstETH (zeroForOne=false)
        uint256 wstethReceived = _executeSwap(false, SWAP_AMOUNT);

        // wstETH -> WETH (zeroForOne=true)
        uint256 wethReceived = _executeSwap(true, wstethReceived);

        uint256 wethAfter = IERC20(Currency.unwrap(weth)).balanceOf(swapper);
        uint256 totalWethSpent = wethBefore - wethAfter;

        console.log("Round trip: WETH -> wstETH -> WETH");
        console.log("Initial WETH:     ", SWAP_AMOUNT);
        console.log("wstETH received:  ", wstethReceived);
        console.log("Final WETH:       ", wethReceived);
        console.log("Total WETH lost:  ", totalWethSpent);

        assertApproxEqRel(wethAfter, wethBefore, 0.005e18); // Less than 0.5% loss
    }

    function _deployHooks() private {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = wsteth;
        currencies[1] = weth;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] =
            Base.RateOracleConfig({oracle: Currency.unwrap(wsteth), selector: IWstETH.stEthPerToken.selector});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, code);

        hooks = StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, salt, code));
    }

    function _dealTokens() private {
        deal(Currency.unwrap(weth), liquidityProvider, LIQUIDITY_AMOUNT * 2);
        deal(Currency.unwrap(wsteth), liquidityProvider, LIQUIDITY_AMOUNT * 2);
        deal(Currency.unwrap(weth), swapper, SWAP_AMOUNT * 100);
        deal(Currency.unwrap(wsteth), swapper, SWAP_AMOUNT * 100);

        vm.startPrank(liquidityProvider);
        IERC20(Currency.unwrap(weth)).forceApprove(address(hooks), type(uint256).max);
        IERC20(Currency.unwrap(wsteth)).forceApprove(address(hooks), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper);
        IERC20(Currency.unwrap(weth)).forceApprove(address(permit2), type(uint256).max);
        IERC20(Currency.unwrap(wsteth)).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(weth), address(universalRouter), type(uint160).max, type(uint48).max);
        permit2.approve(Currency.unwrap(wsteth), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _getPoolKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: wsteth,
            currency1: weth,
            fee: uint24(LP_FEE_PERCENTAGE),
            tickSpacing: hooks.TICK_SPACING(),
            hooks: IHooks(address(hooks))
        });
    }

    function _addLiquidity(uint256 _wstethAmount, uint256 _wethAmount) internal {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _wstethAmount;
        amounts[1] = _wethAmount;

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);
    }

    function _executeSwap(bool _zeroForOne, uint256 _amountIn) internal returns (uint256 amountOut) {
        PoolKey memory poolKey = _getPoolKey();

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

    function _executeExactOutputSwap(bool _zeroForOne, uint256 _amountOut) internal returns (uint256 amountIn) {
        PoolKey memory poolKey = _getPoolKey();

        Currency inputCurrency = _zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = _zeroForOne ? poolKey.currency1 : poolKey.currency0;

        uint256 inputBefore = IERC20(Currency.unwrap(inputCurrency)).balanceOf(swapper);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: poolKey,
                zeroForOne: _zeroForOne,
                amountOut: uint128(_amountOut),
                amountInMaximum: type(uint128).max,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(inputCurrency, type(uint128).max);
        params[2] = abi.encode(outputCurrency, _amountOut);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.prank(swapper);
        universalRouter.execute(commands, inputs, block.timestamp + 100);

        uint256 inputAfter = IERC20(Currency.unwrap(inputCurrency)).balanceOf(swapper);
        amountIn = inputBefore - inputAfter;
    }
}

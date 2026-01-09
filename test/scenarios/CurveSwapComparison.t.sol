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
import {console} from "forge-std/console.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";

/// @notice Compares StableSwap Hooks swap with a real Curve crv2pool transaction
/// @dev Reference TX: 0xbf89f5f9b648f09864cf4e7754fe28a79b0f71f42d2f456b8d88c1af1a4b9635
/// @dev Uses currency1 (USDC) and currency2 (USDT) to match Curve crv2pool
contract CurveSwapComparisonTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    // Curve crv2pool parameters
    uint256 internal constant AMP = 10_000;
    uint256 internal constant LP_FEE_PERCENTAGE = 300; // 0.03%

    // Pool reserves from Curve transaction (raw values, 6 decimals for USDC/USDT)
    uint256 internal constant USDC_RESERVE = 457_528_290620;
    uint256 internal constant USDT_RESERVE = 3_328_069_001635;

    // Swap amounts from Curve transaction
    uint256 internal constant SWAP_AMOUNT_IN = 5_920_000000; // 5,920 USDC
    uint256 internal constant CURVE_OUTPUT = 5_924_773812; // 5,924.773812 USDT
    uint256 internal constant CURVE_GAS = 212_760;

    // Use USDC (currency1) and USDT (currency2) to match Curve crv2pool
    Currency internal usdc;
    Currency internal usdt;

    StableSwapHooksFactory internal factory;
    StableSwapHooks internal hooks;

    address internal admin;
    address internal liquidityProvider;
    address internal swapper;

    function setUp() public override {
        super.setUp();

        if (block.chainid == 31337) {
            vm.warp(1731337000);
        }

        // Use USDC and USDT to match Curve crv2pool
        usdc = currency1;
        usdt = currency2;

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
        _addImbalancedLiquidity();
    }

    function _deployHooks() private {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = usdc;
        currencies[1] = usdt;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, code);

        hooks = StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, salt, code));
    }

    function _dealTokens() private {
        // Deal enough tokens for liquidity and swaps
        uint256 lpAmount0 = USDC_RESERVE + 1e6; // Extra buffer
        uint256 lpAmount1 = USDT_RESERVE + 1e6;

        deal(Currency.unwrap(usdc), liquidityProvider, lpAmount0);
        deal(Currency.unwrap(usdt), liquidityProvider, lpAmount1);
        deal(Currency.unwrap(usdc), swapper, SWAP_AMOUNT_IN * 10);
        deal(Currency.unwrap(usdt), swapper, CURVE_OUTPUT * 10);

        vm.startPrank(liquidityProvider);
        IERC20(Currency.unwrap(usdc)).forceApprove(address(hooks), type(uint256).max);
        IERC20(Currency.unwrap(usdt)).forceApprove(address(hooks), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper);
        IERC20(Currency.unwrap(usdc)).forceApprove(address(permit2), type(uint256).max);
        IERC20(Currency.unwrap(usdt)).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(usdc), address(universalRouter), type(uint160).max, type(uint48).max);
        permit2.approve(Currency.unwrap(usdt), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _addImbalancedLiquidity() private {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = USDC_RESERVE;
        amounts[1] = USDT_RESERVE;

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, 0);
    }

    function _getPoolKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: usdc,
            currency1: usdt,
            fee: uint24(LP_FEE_PERCENTAGE),
            tickSpacing: hooks.TICK_SPACING(),
            hooks: IHooks(address(hooks))
        });
    }

    function _calldataCost(bytes memory data) internal pure returns (uint256 cost) {
        for (uint256 i = 0; i < data.length; i++) {
            cost += data[i] == 0 ? 4 : 16;
        }
    }

    function _executeExactInputSwap(bool _zeroForOne, uint256 _amountIn)
        internal
        returns (uint256 gasUsed, uint256 intrinsicGas)
    {
        PoolKey memory poolKey = _getPoolKey();

        Currency inputCurrency = _zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = _zeroForOne ? poolKey.currency1 : poolKey.currency0;

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

        // Calculate intrinsic gas (21000 base + calldata costs)
        bytes memory fullCalldata =
            abi.encodeCall(universalRouter.execute, (commands, inputs, block.timestamp + 100));
        intrinsicGas = 21000 + _calldataCost(fullCalldata);

        vm.prank(swapper);
        uint256 gasBefore = gasleft();
        universalRouter.execute(commands, inputs, block.timestamp + 100);
        gasUsed = gasBefore - gasleft();
    }

    /// @notice Compare our swap output and gas with Curve's crv2pool
    function test_curveSwapComparison_usdcToUsdt() public {
        // Verify pool state matches Curve
        uint256 reserve0 = hooks.reserves(0);
        uint256 reserve1 = hooks.reserves(1);
        assertEq(reserve0, USDC_RESERVE);
        assertEq(reserve1, USDT_RESERVE);

        // Record balances before swap
        uint256 swapperBalance0Before = IERC20(Currency.unwrap(usdc)).balanceOf(swapper);
        uint256 swapperBalance1Before = IERC20(Currency.unwrap(usdt)).balanceOf(swapper);

        // Execute swap and measure gas
        (uint256 execGas, uint256 intrinsicGas) = _executeExactInputSwap(true, SWAP_AMOUNT_IN);
        uint256 fullTxGas = execGas + intrinsicGas;

        // Calculate output
        uint256 swapperBalance0After = IERC20(Currency.unwrap(usdc)).balanceOf(swapper);
        uint256 swapperBalance1After = IERC20(Currency.unwrap(usdt)).balanceOf(swapper);

        uint256 amountIn = swapperBalance0Before - swapperBalance0After;
        uint256 amountOut = swapperBalance1After - swapperBalance1Before;

        console.log("Curve Output:", CURVE_OUTPUT);
        console.log("Our Output:  ", amountOut);
        console.log("Output Diff: ", int256(amountOut) - int256(CURVE_OUTPUT));
        console.log("Curve Gas:   ", CURVE_GAS);
        console.log("Our Gas:     ", fullTxGas);
        console.log("Gas Diff:    ", int256(fullTxGas) - int256(CURVE_GAS));
        assertEq(amountIn, SWAP_AMOUNT_IN);
        assertGt(amountOut, 0);
        assertApproxEqRel(amountOut, CURVE_OUTPUT, 0.0005e18);
    }
}

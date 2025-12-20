// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {IWstETH} from "lib/uniswap-hooks/lib/v4-periphery/src/interfaces/external/IWstETH.sol";
import {MockWstETH} from "lib/uniswap-hooks/lib/v4-periphery/test/mocks/MockWstETH.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooksHarness} from "test/testUtils/StableSwapHooksHarness.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";

/// @notice Mock stETH for testing - matches interface expected by MockWstETH
contract MockStETH is MockERC20 {
    constructor() MockERC20("Liquid staked Ether 2.0", "stETH", 18) {}

    function getSharesByPooledEth(uint256 pooledEth) public pure returns (uint256) {
        return pooledEth;
    }

    function getPooledEthByShares(uint256 shares) public pure returns (uint256) {
        return shares;
    }
}

/// @title StableSwapHooks Rate Oracle Test
/// @notice Tests for StableSwap hooks with dynamic rate oracles (e.g., wstETH/stETH)
contract StableSwapHooksRateOracleTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 internal constant BASE_PROTOCOL_FEE_PERCENTAGE = 100;
    uint256 internal constant BASE_HOOK_FEE_PERCENTAGE = 200;
    uint256 internal constant BASE_LP_FEE_PERCENTAGE = 300;
    uint160 internal constant BASE_SQRT_PRICE_X96 = 1 << 96;
    uint256 internal constant BASE_AMP = 100;
    uint160 internal constant HOOK_FLAGS = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
        | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        | Hooks.BEFORE_DONATE_FLAG;

    uint256 internal constant SWAP_AMOUNT = 100;
    uint256 internal constant LIQUIDITY_AMOUNT = 1_000_000;
    uint256 internal constant STABLESWAP_SLIPPAGE_TOLERANCE = 0.01e18; // 1% tolerance for rate-adjusted swaps
    uint256 internal constant EXCHANGE_RATE = 11e17; // 1.1e18 - MockWstETH exchange rate

    StableSwapHooksHarness internal hooksWstETH;

    Currency internal stETH;
    Currency internal wstETH;

    address internal defaultAdmin;
    address internal unauthorizedUser;
    address internal liquidityProvider;
    address internal swapper;
    address internal protocolFeeCollector;

    function setUp() public virtual override {
        super.setUp();

        defaultAdmin = makeAddr("defaultAdmin");
        liquidityProvider = makeAddr("liquidityProvider");
        swapper = makeAddr("swapper");
        unauthorizedUser = makeAddr("unauthorizedUser");
        protocolFeeCollector = makeAddr("protocolFeeCollector");

        // Deploy stETH and wstETH mocks directly
        MockStETH mockStETH = new MockStETH();
        MockWstETH mockWstETH = new MockWstETH(address(mockStETH));
        stETH = Currency.wrap(address(mockStETH));
        wstETH = Currency.wrap(address(mockWstETH));
        vm.label(address(mockStETH), "stETH");
        vm.label(address(mockWstETH), "wstETH");

        _deployHooksWithWstETHOracle();
        _dealWstETHTokens();
    }

    function _deployHooksWithWstETHOracle() private {
        // Sort currencies
        Currency currency0;
        Currency currency1;
        if (Currency.unwrap(stETH) < Currency.unwrap(wstETH)) {
            currency0 = stETH;
            currency1 = wstETH;
        } else {
            currency0 = wstETH;
            currency1 = stETH;
        }

        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;

        // Configure rate oracles:
        // - stETH: no oracle (static rate of 1e18)
        // - wstETH: uses stEthPerToken() to get the exchange rate
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

        (, bytes32 salt) = HookMiner.find(
            defaultAdmin,
            HOOK_FLAGS,
            type(StableSwapHooksHarness).creationCode,
            abi.encode(
                poolManager,
                currencies,
                rateOracles,
                protocolFeeCollector,
                BASE_PROTOCOL_FEE_PERCENTAGE,
                BASE_HOOK_FEE_PERCENTAGE,
                BASE_LP_FEE_PERCENTAGE,
                BASE_AMP
            )
        );

        vm.prank(defaultAdmin);
        hooksWstETH = new StableSwapHooksHarness{salt: salt}(
            IPoolManager(poolManager),
            currencies,
            rateOracles,
            protocolFeeCollector,
            BASE_PROTOCOL_FEE_PERCENTAGE,
            BASE_HOOK_FEE_PERCENTAGE,
            BASE_LP_FEE_PERCENTAGE,
            BASE_AMP
        );
    }

    function _dealWstETHTokens() private {
        // Deal stETH tokens (can be minted directly on the mock)
        deal(Currency.unwrap(stETH), liquidityProvider, 2_000_000e18);
        deal(Currency.unwrap(stETH), swapper, 2_000_000e18);

        // Deal wstETH tokens
        deal(Currency.unwrap(wstETH), liquidityProvider, 2_000_000e18);
        deal(Currency.unwrap(wstETH), swapper, 2_000_000e18);

        // Approve tokens for hooks
        vm.startPrank(liquidityProvider);
        IERC20(Currency.unwrap(stETH)).forceApprove(address(hooksWstETH), type(uint256).max);
        IERC20(Currency.unwrap(wstETH)).forceApprove(address(hooksWstETH), type(uint256).max);
        vm.stopPrank();

        // Approve tokens for swapper via permit2
        vm.startPrank(swapper);
        IERC20(Currency.unwrap(stETH)).forceApprove(address(permit2), type(uint256).max);
        IERC20(Currency.unwrap(wstETH)).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(stETH), address(universalRouter), type(uint160).max, type(uint48).max);
        permit2.approve(Currency.unwrap(wstETH), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _getPoolKeyWstETH() internal view returns (PoolKey memory) {
        Currency currency0;
        Currency currency1;
        if (Currency.unwrap(stETH) < Currency.unwrap(wstETH)) {
            currency0 = stETH;
            currency1 = wstETH;
        } else {
            currency0 = wstETH;
            currency1 = stETH;
        }

        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(BASE_LP_FEE_PERCENTAGE),
            tickSpacing: hooksWstETH.TICK_SPACING(),
            hooks: IHooks(address(hooksWstETH))
        });
    }

    function _addLiquidityWstETH(uint256 _amountStETH, uint256 _amountWstETH) internal {
        uint256[] memory amounts = new uint256[](2);

        // Order amounts according to currency order
        if (Currency.unwrap(stETH) < Currency.unwrap(wstETH)) {
            amounts[0] = _amountStETH;
            amounts[1] = _amountWstETH;
        } else {
            amounts[0] = _amountWstETH;
            amounts[1] = _amountStETH;
        }

        vm.prank(liquidityProvider);
        hooksWstETH.addLiquidity(amounts, 0);
    }

    function _executeSwapWstETH(bool _stETHToWstETH, uint256 _amountIn) internal {
        PoolKey memory poolKey = _getPoolKeyWstETH();

        // Determine if this is zeroForOne based on token ordering
        bool zeroForOne;
        if (Currency.unwrap(stETH) < Currency.unwrap(wstETH)) {
            // stETH is currency0, wstETH is currency1
            zeroForOne = _stETHToWstETH;
        } else {
            // wstETH is currency0, stETH is currency1
            zeroForOne = !_stETHToWstETH;
        }

        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
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
    }

    function test_rateOracle_addLiquidity_WithDynamicRate() public {
        // Add liquidity with rate-adjusted amounts
        // Since 1 wstETH = 1.1 stETH, we should add proportionally
        uint256 stETHAmount = 1_100_000e18; // 1.1M stETH
        uint256 wstETHAmount = 1_000_000e18; // 1M wstETH (worth 1.1M stETH)

        uint256 lpBalanceBefore = hooksWstETH.balanceOf(liquidityProvider);

        _addLiquidityWstETH(stETHAmount, wstETHAmount);

        uint256 lpBalanceAfter = hooksWstETH.balanceOf(liquidityProvider);

        assertGt(lpBalanceAfter, lpBalanceBefore, "LP should receive tokens");
    }

    function test_rateOracle_swap_stETHToWstETH() public {
        uint256 stETHAmount = 1_100_000e18;
        uint256 wstETHAmount = 1_000_000e18;
        _addLiquidityWstETH(stETHAmount, wstETHAmount);

        uint256 swapAmount = 1000e18;

        uint256 swapperStETHBefore = IERC20(Currency.unwrap(stETH)).balanceOf(swapper);
        uint256 swapperWstETHBefore = IERC20(Currency.unwrap(wstETH)).balanceOf(swapper);

        _executeSwapWstETH(true, swapAmount); // stETH -> wstETH

        uint256 swapperStETHAfter = IERC20(Currency.unwrap(stETH)).balanceOf(swapper);
        uint256 swapperWstETHAfter = IERC20(Currency.unwrap(wstETH)).balanceOf(swapper);

        assertEq(swapperStETHBefore - swapperStETHAfter, swapAmount, "Should spend exact stETH amount");
        assertGt(swapperWstETHAfter, swapperWstETHBefore, "Should receive wstETH");

        // Expected output should account for the 1.1x rate
        // 1000 stETH should give approximately 1000/1.1 = ~909 wstETH (minus fees)
        uint256 wstETHReceived = swapperWstETHAfter - swapperWstETHBefore;
        uint256 expectedWstETH = (swapAmount * 1e18) / 1.1e18; // Approximate expected output before fees

        assertApproxEqRel(wstETHReceived, expectedWstETH, STABLESWAP_SLIPPAGE_TOLERANCE, "Output should match rate");
    }

    function test_rateOracle_swap_wstETHToStETH() public {
        uint256 stETHAmount = 1_100_000e18;
        uint256 wstETHAmount = 1_000_000e18;
        _addLiquidityWstETH(stETHAmount, wstETHAmount);

        uint256 swapAmount = 1000e18;

        uint256 swapperStETHBefore = IERC20(Currency.unwrap(stETH)).balanceOf(swapper);
        uint256 swapperWstETHBefore = IERC20(Currency.unwrap(wstETH)).balanceOf(swapper);

        _executeSwapWstETH(false, swapAmount); // wstETH -> stETH

        uint256 swapperStETHAfter = IERC20(Currency.unwrap(stETH)).balanceOf(swapper);
        uint256 swapperWstETHAfter = IERC20(Currency.unwrap(wstETH)).balanceOf(swapper);

        assertEq(swapperWstETHBefore - swapperWstETHAfter, swapAmount, "Should spend exact wstETH amount");
        assertGt(swapperStETHAfter, swapperStETHBefore, "Should receive stETH");

        // Expected output should account for the 1.1x rate
        // 1000 wstETH should give approximately 1000*1.1 = ~1100 stETH (minus fees)
        uint256 stETHReceived = swapperStETHAfter - swapperStETHBefore;
        uint256 expectedStETH = (swapAmount * 1.1e18) / 1e18; // Approximate expected output before fees

        assertApproxEqRel(stETHReceived, expectedStETH, STABLESWAP_SLIPPAGE_TOLERANCE, "Output should match rate");
    }
}

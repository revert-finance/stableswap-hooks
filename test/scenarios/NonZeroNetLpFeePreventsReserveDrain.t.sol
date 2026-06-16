// SPDX-License-Identifier: BUSL-1.1
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
import {StableSwapHooksFactoryHarness} from "test/testUtils/StableSwapHooksFactoryHarness.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";

contract NonZeroNetLpFeePreventsReserveDrainTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 internal constant LP_FEE_PERCENTAGE = 300;
    uint256 internal constant AMP = 100;
    uint256 internal constant LIQUIDITY_AMOUNT = 1_000_000;

    StableSwapHooksFactoryHarness internal factory;
    StableSwapHooks internal hooks;

    address internal admin;
    address internal liquidityProvider;
    address internal swapper;

    function setUp() public override {
        super.setUp();

        if (block.chainid == 31337) {
            vm.warp(1731337000);
        }

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
        _addLiquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
    }

    function test_exactInput_maxValidFeeSplit_cannotDrainReserve_poolStaysOperational() public {
        uint256 maxValidHookFee = hooks.FEE_PRECISION() - 1;

        vm.prank(admin);
        hooks.setHookFeePercentage(maxValidHookFee);

        uint256 drainAmount = 100 * _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        deal(Currency.unwrap(currency0), swapper, drainAmount);

        _executeExactInputSwap(true, drainAmount);

        assertGt(hooks.reserves(1), 0, "positive net lp fee must leave a reserve floor above zero");

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, LIQUIDITY_AMOUNT);
        amounts[1] = _toTokenWei(currency1, LIQUIDITY_AMOUNT);
        uint256[] memory minAmounts = new uint256[](2);

        deal(Currency.unwrap(currency0), liquidityProvider, amounts[0]);
        deal(Currency.unwrap(currency1), liquidityProvider, amounts[1]);

        uint256 reserve1Before = hooks.reserves(1);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, minAmounts, 0);

        assertGt(hooks.reserves(1), reserve1Before, "addLiquidity must remain functional after the drain attempt");
    }

    function _deployHooks() private {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, code);

        hooks = StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, salt, code));
    }

    function _dealTokens() private {
        deal(Currency.unwrap(currency0), liquidityProvider, _toTokenWei(currency0, 2e6));
        deal(Currency.unwrap(currency1), liquidityProvider, _toTokenWei(currency1, 2e6));
        deal(Currency.unwrap(currency0), swapper, _toTokenWei(currency0, 100e6));
        deal(Currency.unwrap(currency1), swapper, _toTokenWei(currency1, 100e6));

        vm.startPrank(liquidityProvider);
        IERC20(Currency.unwrap(currency0)).forceApprove(address(hooks), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).forceApprove(address(hooks), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper);
        IERC20(Currency.unwrap(currency0)).forceApprove(address(permit2), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(currency0), address(universalRouter), type(uint160).max, type(uint48).max);
        permit2.approve(Currency.unwrap(currency1), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _toTokenWei(Currency _currency, uint256 _amount) internal view returns (uint256) {
        return _amount * 10 ** IERC20Metadata(Currency.unwrap(_currency)).decimals();
    }

    function _addLiquidity(uint256 _amount0, uint256 _amount1) internal {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, _amount0);
        amounts[1] = _toTokenWei(currency1, _amount1);

        uint256[] memory minAmounts = new uint256[](2);

        vm.prank(liquidityProvider);
        hooks.addLiquidity(amounts, minAmounts, 0);
    }

    function _getPoolKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(LP_FEE_PERCENTAGE),
            tickSpacing: hooks.TICK_SPACING(),
            hooks: IHooks(address(hooks))
        });
    }

    function _executeExactInputSwap(bool _zeroForOne, uint256 _amountIn) internal {
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

        vm.prank(swapper);
        universalRouter.execute(commands, inputs, block.timestamp + 100);
    }
}

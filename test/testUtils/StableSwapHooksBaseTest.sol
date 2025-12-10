// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {StableSwapHooksHarness} from "test/testUtils/StableSwapHooksHarness.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";

abstract contract StableSwapHooksBaseTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 internal constant BASE_PROTOCOL_FEE_PERCENTAGE = 100;
    uint256 internal constant BASE_HOOK_FEE_PERCENTAGE = 200;
    uint256 internal constant BASE_LP_FEE_PERCENTAGE = 300;
    uint160 internal constant BASE_SQRT_PRICE_X96 = 1 << 96;
    uint256 internal constant BASE_AMP = 100;

    StableSwapHooksHarness internal hooks;

    address internal defaultAdmin;
    address internal unauthorizedUser;
    address internal liquidityProvider;
    address internal swapper;
    address internal protocolFeeCollector;

    function setUp() public virtual override {
        super.setUp();

        // Warp to realistic timestamp on local chain to avoid time-based issues
        if (block.chainid == 31337) {
            vm.warp(1731337000); // Monday, November 11, 2024 11:56:40 AM GMT-03:00
        }

        defaultAdmin = makeAddr("defaultAdmin");
        liquidityProvider = makeAddr("liquidityProvider");
        swapper = makeAddr("swapper");
        unauthorizedUser = makeAddr("unauthorizedUser");
        protocolFeeCollector = makeAddr("protocolFeeCollector");

        _deployHooks();
        _dealTokens();
        _initializePool();
    }

    function _getPoolKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(BASE_LP_FEE_PERCENTAGE),
            tickSpacing: hooks.TICK_SPACING(),
            hooks: IHooks(address(hooks))
        });
    }

    function _deployHooks() private {
        uint160 flags = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            | Hooks.BEFORE_DONATE_FLAG;

        (, bytes32 salt) = HookMiner.find(
            defaultAdmin,
            flags,
            type(StableSwapHooksHarness).creationCode,
            abi.encode(
                poolManager,
                currency0,
                currency1,
                protocolFeeCollector,
                BASE_PROTOCOL_FEE_PERCENTAGE,
                BASE_HOOK_FEE_PERCENTAGE,
                BASE_LP_FEE_PERCENTAGE,
                BASE_AMP
            )
        );

        vm.prank(defaultAdmin);
        hooks = new StableSwapHooksHarness{salt: salt}(
            IPoolManager(poolManager),
            currency0,
            currency1,
            protocolFeeCollector,
            BASE_PROTOCOL_FEE_PERCENTAGE,
            BASE_HOOK_FEE_PERCENTAGE,
            BASE_LP_FEE_PERCENTAGE,
            BASE_AMP
        );
    }

    function _dealTokens() private {
        deal(Currency.unwrap(currency0), liquidityProvider, _toTokenWei(currency0, 1e6));
        deal(Currency.unwrap(currency1), liquidityProvider, _toTokenWei(currency1, 1e6));
        deal(Currency.unwrap(currency0), swapper, _toTokenWei(currency0, 1e6));
        deal(Currency.unwrap(currency1), swapper, _toTokenWei(currency1, 1e6));

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

    function _initializePool() private {
        poolManager.initialize(_getPoolKey(), BASE_SQRT_PRICE_X96);
    }

    function _toTokenWei(Currency _currency, uint256 _amount) internal view returns (uint256) {
        return _amount * 10 ** IERC20Metadata(Currency.unwrap(_currency)).decimals();
    }

    function _addLiquidity(uint256 _amount0, uint256 _amount1) internal {
        vm.startPrank(liquidityProvider);
        hooks.addLiquidity(_toTokenWei(currency0, _amount0), _toTokenWei(currency1, _amount1), 0);
        vm.stopPrank();
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

    function _executeExactOutputSwap(bool _zeroForOne, uint256 _amountOut) internal {
        PoolKey memory poolKey = _getPoolKey();

        Currency inputCurrency = _zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = _zeroForOne ? poolKey.currency1 : poolKey.currency0;

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
    }
}

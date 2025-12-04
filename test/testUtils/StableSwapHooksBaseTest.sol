// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {ExternalContractsDeployer} from "./ExternalContractsDeployer.sol";

abstract contract StableSwapHooksBaseTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    StableSwapHooks internal hooks;

    address internal defaultAdmin;
    address internal amplificationAdmin;
    address internal unauthorizedUser;
    address internal liquidityProvider;
    address internal swapper;

    function setUp() public virtual {
        defaultAdmin = makeAddr("defaultAdmin");
        amplificationAdmin = makeAddr("amplificationAdmin");
        liquidityProvider = makeAddr("liquidityProvider");
        swapper = makeAddr("swapper");
        unauthorizedUser = makeAddr("unauthorizedUser");

        _deployExternalContracts();
        _deployHooks();
        _grantRoles();
        _dealTokens();
    }

    function _deployHooks() private {
        uint160 flags = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            | Hooks.BEFORE_DONATE_FLAG;

        uint256 amplification = 100;

        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(StableSwapHooks).creationCode,
            abi.encode(amplification, poolManager, currency0, currency1)
        );

        hooks = new StableSwapHooks{salt: salt}(amplification, IPoolManager(poolManager), currency0, currency1);
    }

    function _getPoolKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: hooks.FEE(),
            tickSpacing: hooks.TICK_SPACING(),
            hooks: IHooks(address(hooks))
        });
    }

    function _grantRoles() private {
        hooks.grantRole(hooks.DEFAULT_ADMIN_ROLE(), defaultAdmin);
        hooks.grantRole(hooks.A_ADMIN_ROLE(), amplificationAdmin);
    }

    function _dealTokens() private {
        deal(Currency.unwrap(currency0), liquidityProvider, _toTokenWei(currency0, 1000));
        deal(Currency.unwrap(currency1), liquidityProvider, _toTokenWei(currency1, 1000));
        deal(Currency.unwrap(currency0), swapper, _toTokenWei(currency0, 1000));
        deal(Currency.unwrap(currency1), swapper, _toTokenWei(currency1, 1000));

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
}

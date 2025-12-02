// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";

// TODO: Move to mocks folder
contract MockERC20 {
    uint8 public decimals = 18;
}

/// @title StableSwapHooksBaseTest
/// @notice Base test contract with shared setup for StableSwapHooks tests
abstract contract StableSwapHooksBaseTest is Test {
    StableSwapHooks internal hooks;
    PoolKey internal key;
    address internal poolManager;
    address internal deployer;
    address internal ampAdmin;
    address internal unauthorizedUser;

    function setUp() public virtual {
        MockERC20 mockToken0 = new MockERC20();
        MockERC20 mockToken1 = new MockERC20();

        poolManager = address(0x1);
        deployer = address(this);
        ampAdmin = address(0x2);
        unauthorizedUser = address(0x3);

        uint256 initialAmp = 1e3;

        uint160 flags = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;

        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(StableSwapHooks).creationCode,
            abi.encode(initialAmp, poolManager, address(mockToken0), address(mockToken1))
        );

        hooks = new StableSwapHooks{salt: salt}(
            initialAmp,
            IPoolManager(poolManager),
            Currency.wrap(address(mockToken0)),
            Currency.wrap(address(mockToken1))
        );

        key = PoolKey({
            currency0: Currency.wrap(address(mockToken0)),
            currency1: Currency.wrap(address(mockToken1)),
            fee: hooks.FEE(),
            tickSpacing: hooks.TICK_SPACING(),
            hooks: IHooks(address(hooks))
        });

        // Grant AMP_ADMIN_ROLE to ampAdmin
        hooks.grantRole(hooks.A_ADMIN_ROLE(), ampAdmin);
    }
}

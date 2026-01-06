// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";

contract StableSwapHooksFactoryTest is ExternalContractsDeployer {
    uint256 internal constant BASE_PROTOCOL_FEE_PERCENTAGE = 100;
    uint256 internal constant BASE_HOOK_FEE_PERCENTAGE = 200;
    uint256 internal constant BASE_LP_FEE_PERCENTAGE = 300;
    uint256 internal constant BASE_AMP = 100;

    StableSwapHooksFactory internal factory;

    address internal owner;
    address internal unauthorizedUser;
    address internal protocolFeeCollector;
    address internal hookFeeCollector;

    function setUp() public override {
        super.setUp();

        owner = makeAddr("owner");
        unauthorizedUser = makeAddr("unauthorizedUser");
        protocolFeeCollector = makeAddr("protocolFeeCollector");
        hookFeeCollector = makeAddr("hookFeeCollector");

        factory = new StableSwapHooksFactory(IPoolManager(poolManager), owner, protocolFeeCollector, hookFeeCollector);
    }

    function _deployHook() internal returns (StableSwapHooks) {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP);

        return factory.deploy(currencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, salt);
    }

    // ==========================================================================
    // Constructor
    // ==========================================================================

    function test_constructor_ShouldSetStateCorrectly() public view {
        assertEq(address(factory.poolManager()), address(poolManager));
        assertEq(factory.protocolFeeCollector(), protocolFeeCollector);
        assertEq(factory.hookFeeCollector(), hookFeeCollector);
        assertEq(factory.owner(), owner);
    }

    function test_constructor_ShouldRevertWhenProtocolFeeCollectorIsZero() public {
        vm.expectRevert(StableSwapHooksFactory.ZeroAddress.selector);
        new StableSwapHooksFactory(IPoolManager(poolManager), owner, address(0), hookFeeCollector);
    }

    function test_constructor_ShouldRevertWhenHookFeeCollectorIsZero() public {
        vm.expectRevert(StableSwapHooksFactory.ZeroAddress.selector);
        new StableSwapHooksFactory(IPoolManager(poolManager), owner, protocolFeeCollector, address(0));
    }

    // ==========================================================================
    // Protocol Fee Collector
    // ==========================================================================

    function test_setProtocolFeeCollector_ShouldSucceedWhenCalledByOwner() public {
        address newCollector = makeAddr("newCollector");

        vm.prank(owner);
        vm.expectEmit(address(factory));
        emit StableSwapHooksFactory.ProtocolFeeCollectorSet(owner, newCollector);
        factory.setProtocolFeeCollector(newCollector);

        assertEq(factory.protocolFeeCollector(), newCollector);
    }

    function test_setProtocolFeeCollector_ShouldRevertWhenCalledByNonOwner() public {
        address newCollector = makeAddr("newCollector");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedUser));
        vm.prank(unauthorizedUser);
        factory.setProtocolFeeCollector(newCollector);
    }

    function test_setProtocolFeeCollector_ShouldRevertWhenZeroAddress() public {
        vm.expectRevert(StableSwapHooksFactory.ZeroAddress.selector);
        vm.prank(owner);
        factory.setProtocolFeeCollector(address(0));
    }

    // ==========================================================================
    // Hook Fee Collector
    // ==========================================================================

    function test_setHookFeeCollector_ShouldSucceedWhenCalledByOwner() public {
        address newCollector = makeAddr("newCollector");

        vm.prank(owner);
        vm.expectEmit(address(factory));
        emit StableSwapHooksFactory.HookFeeCollectorSet(owner, newCollector);
        factory.setHookFeeCollector(newCollector);

        assertEq(factory.hookFeeCollector(), newCollector);
    }

    function test_setHookFeeCollector_ShouldRevertWhenCalledByNonOwner() public {
        address newCollector = makeAddr("newCollector");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedUser));
        vm.prank(unauthorizedUser);
        factory.setHookFeeCollector(newCollector);
    }

    function test_setHookFeeCollector_ShouldRevertWhenZeroAddress() public {
        vm.expectRevert(StableSwapHooksFactory.ZeroAddress.selector);
        vm.prank(owner);
        factory.setHookFeeCollector(address(0));
    }

    // ==========================================================================
    // Pause/Unpause
    // ==========================================================================

    function test_pause_ShouldPreventDeployment() public {
        vm.prank(owner);
        factory.pause();

        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        factory.deploy(currencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, salt);
    }

    function test_unpause_ShouldAllowDeployment() public {
        vm.startPrank(owner);
        factory.pause();
        factory.unpause();
        vm.stopPrank();

        StableSwapHooks hook = _deployHook();
        assertTrue(factory.isDeployedByFactory(address(hook)));
    }

    function test_pause_ShouldRevertWhenCalledByNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedUser));
        vm.prank(unauthorizedUser);
        factory.pause();
    }

    function test_unpause_ShouldRevertWhenCalledByNonOwner() public {
        vm.prank(owner);
        factory.pause();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedUser));
        vm.prank(unauthorizedUser);
        factory.unpause();
    }

    // ==========================================================================
    // Deploy
    // ==========================================================================

    function test_deploy_ShouldDeployHookCorrectly() public {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        (address expectedAddress, bytes32 salt) =
            factory.mineSalt(currencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP);

        vm.expectEmit(true, true, false, false, address(factory));
        emit StableSwapHooksFactory.StableSwapHooksDeployed(address(this), expectedAddress);

        StableSwapHooks hook = factory.deploy(currencies, rateOracles, BASE_LP_FEE_PERCENTAGE, BASE_AMP, salt);

        assertEq(address(hook), expectedAddress);
        assertTrue(factory.isDeployedByFactory(address(hook)));
    }

    function test_deploy_ShouldRevertWhenLpFeePercentageExceedsPrecision() public {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        uint256 invalidFee = factory.FEE_PRECISION() + 1;

        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, invalidFee, BASE_AMP);

        vm.expectRevert(StableSwapHooksFactory.InvalidFeePercentage.selector);
        factory.deploy(currencies, rateOracles, invalidFee, BASE_AMP, salt);
    }
}

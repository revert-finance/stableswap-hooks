// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {ChainConfig} from "./config/ChainConfig.sol";

/// @notice Script to deploy StableSwapHooksFactory using CREATE3 for deterministic addresses
/// @dev Usage:
///   forge script script/DeployFactoryCreate3.s.sol:DeployFactoryCreate3 \
///     --rpc-url <RPC_URL> \
///     --account <ACCOUNT_NAME> \
///     --broadcast --verify
contract DeployFactoryCreate3 is Script {
    /// @notice Salt for CREATE3 deployment - change this to get different addresses
    /// @dev Same salt + same deployer = same address across chains
    /// @dev With CREATE3, address is independent of bytecode (unlike CREATE2)
    bytes32 public constant SALT = keccak256("StableSwapHooksFactory");

    /// @notice Get deployment configuration from environment variables and chain config
    /// @return poolManager The PoolManager address
    /// @return factoryOwner The owner of the factory
    /// @return protocolFeeCollector The protocol fee collector address
    /// @return hookFeeCollector The hook fee collector address
    function _getDeploymentConfig()
        internal
        view
        returns (address poolManager, address factoryOwner, address protocolFeeCollector, address hookFeeCollector)
    {
        // Get chain config
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);

        // Get PoolManager address (env var overrides chain config)
        poolManager = vm.envOr("POOL_MANAGER", config.poolManager);

        // Get other addresses from environment
        factoryOwner = vm.envOr("FACTORY_OWNER", address(0));
        protocolFeeCollector = vm.envOr("PROTOCOL_FEE_COLLECTOR", address(0));
        hookFeeCollector = vm.envOr("HOOK_FEE_COLLECTOR", address(0));
    }

    /// @notice Prepare factory bytecode for CREATE3 deployment
    /// @param poolManager The PoolManager address
    /// @param factoryOwner The owner of the factory
    /// @param protocolFeeCollector The protocol fee collector address
    /// @param hookFeeCollector The hook fee collector address
    /// @return initCode The complete initialization code for deployment
    /// @return hooksCreationCodeHash The hash of the hooks creation code
    function _prepareFactoryBytecode(
        address poolManager,
        address factoryOwner,
        address protocolFeeCollector,
        address hookFeeCollector
    ) internal pure returns (bytes memory initCode, bytes32 hooksCreationCodeHash) {
        hooksCreationCodeHash = keccak256(type(StableSwapHooks).creationCode);

        initCode = abi.encodePacked(
            type(StableSwapHooksFactory).creationCode,
            abi.encode(poolManager, factoryOwner, protocolFeeCollector, hookFeeCollector, hooksCreationCodeHash)
        );
    }

    /// @notice Main deployment function
    /// @dev Reads configuration from environment variables or CLI args:
    ///      - POOL_MANAGER: Address of PoolManager (optional if using known chain)
    ///      - FACTORY_OWNER: Address that will own the factory
    ///      - PROTOCOL_FEE_COLLECTOR: Address for protocol fees
    ///      - HOOK_FEE_COLLECTOR: Address for hook fees
    function run() external returns (StableSwapHooksFactory factory) {
        console2.log("=== StableSwapHooksFactory CREATE3 Deployment ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("Deployer:", msg.sender);

        // Get chain config for logging
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);
        console2.log("Chain:", config.name);

        // Get deployment configuration
        (address poolManagerAddr, address factoryOwner, address protocolFeeCollector, address hookFeeCollector) =
            _getDeploymentConfig();

        require(poolManagerAddr != address(0), "PoolManager address not configured");
        require(factoryOwner != address(0), "Factory owner not configured");
        require(protocolFeeCollector != address(0), "Protocol fee collector not configured");
        require(hookFeeCollector != address(0), "Hook fee collector not configured");

        console2.log("PoolManager:", poolManagerAddr);
        console2.log("Factory Owner:", factoryOwner);
        console2.log("Protocol Fee Collector:", protocolFeeCollector);
        console2.log("Hook Fee Collector:", hookFeeCollector);

        // Prepare factory bytecode
        (bytes memory initCode, bytes32 hooksCreationCodeHash) =
            _prepareFactoryBytecode(poolManagerAddr, factoryOwner, protocolFeeCollector, hookFeeCollector);

        console2.log("Hooks Creation Code Hash:");
        console2.logBytes32(hooksCreationCodeHash);

        console2.log("\nDeploying...\n");

        // Start broadcast for actual deployment
        vm.startBroadcast();

        console2.log("Broadcaster:", msg.sender);
        console2.log("Salt:", vm.toString(SALT));

        // Deploy using CREATE3 with 0 value
        factory = StableSwapHooksFactory(CREATE3.deployDeterministic(0, initCode, SALT));

        vm.stopBroadcast();

        console2.log("\n=== Deployment Complete ===");
        console2.log("Factory Address:", address(factory));
        console2.log("\nThis address will be the SAME on all chains if deployed by the same account!");
        console2.log("CREATE3 makes the address independent of constructor arguments and bytecode.");
        console2.log("\nSave this address for hook deployments:");
        console2.log("FACTORY_ADDRESS=%s", address(factory));
    }
}

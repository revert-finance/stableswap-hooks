// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {ChainConfig} from "./config/ChainConfig.sol";

/// @notice Script to deploy StableSwapHooksFactory
/// @dev Usage:
///   With keystore: forge script script/DeployFactory.s.sol:DeployFactory --rpc-url <RPC_URL> --account <ACCOUNT_NAME> --sender <ADDRESS> --broadcast --verify
///   With private key: forge script script/DeployFactory.s.sol:DeployFactory --rpc-url <RPC_URL> --private-key <KEY> --broadcast --verify
///   Interactive: forge script script/DeployFactory.s.sol:DeployFactory --rpc-url <RPC_URL> --interactive --broadcast --verify
contract DeployFactory is Script {
    /// @notice Main deployment function
    /// @dev Reads configuration from environment variables:
    ///      - POOL_MANAGER: Address of PoolManager (optional if using known chain)
    ///      - FACTORY_OWNER: Address that will own the factory
    ///      - PROTOCOL_FEE_COLLECTOR: Address for protocol fees
    ///      - HOOK_FEE_COLLECTOR: Address for hook fees
    function run() external returns (StableSwapHooksFactory factory) {
        console2.log("=== StableSwapHooksFactory Deployment ===");
        console2.log("Chain ID:", block.chainid);

        // Get chain config
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);
        console2.log("Chain:", config.name);

        // Get PoolManager address (from env or chain config)
        address poolManagerAddr = vm.envOr("POOL_MANAGER", config.poolManager);
        require(poolManagerAddr != address(0), "PoolManager address not configured");
        console2.log("PoolManager:", poolManagerAddr);

        IPoolManager poolManager = IPoolManager(poolManagerAddr);

        // Get addresses from environment variables
        address factoryOwner = vm.envAddress("FACTORY_OWNER");
        address protocolFeeCollector = vm.envAddress("PROTOCOL_FEE_COLLECTOR");
        address hookFeeCollector = vm.envAddress("HOOK_FEE_COLLECTOR");

        console2.log("Factory Owner:", factoryOwner);
        console2.log("Protocol Fee Collector:", protocolFeeCollector);
        console2.log("Hook Fee Collector:", hookFeeCollector);

        // Calculate creation code hash
        bytes32 creationCodeHash = keccak256(type(StableSwapHooks).creationCode);
        console2.log("Creation Code Hash:");
        console2.logBytes32(creationCodeHash);

        console2.log("\nDeploying...\n");

        // Deploy factory
        vm.startBroadcast();

        factory = new StableSwapHooksFactory(
            poolManager, factoryOwner, protocolFeeCollector, hookFeeCollector, creationCodeHash
        );

        vm.stopBroadcast();

        console2.log("=== Deployment Complete ===");
        console2.log("Factory:", address(factory));
        console2.log("Creation Code Hash:");
        console2.logBytes32(creationCodeHash);
        console2.log("\nSave the factory address for hook deployments:");
        console2.log("FACTORY_ADDRESS=%s", address(factory));
    }
}

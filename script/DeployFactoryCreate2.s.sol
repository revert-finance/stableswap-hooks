// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {ChainConfig} from "./config/ChainConfig.sol";

/// @notice Script to deploy StableSwapHooksFactory using CREATE2 for deterministic addresses
/// @dev Usage:
///   forge script script/DeployFactoryCreate2.s.sol:DeployFactoryCreate2 \
///     --rpc-url <RPC_URL> \
///     --account <ACCOUNT_NAME> \
///     --sender <ADDRESS> \
///     --broadcast --verify
contract DeployFactoryCreate2 is Script {
    /// @notice Salt for CREATE2 deployment - change this to get different addresses
    /// @dev Same salt + same deployer = same address across chains
    bytes32 public constant SALT = keccak256("StableSwapHooksFactory");

    /// @notice Main deployment function
    /// @dev Reads configuration from environment variables or CLI args:
    ///      - POOL_MANAGER: Address of PoolManager (optional if using known chain)
    ///      - FACTORY_OWNER: Address that will own the factory
    ///      - PROTOCOL_FEE_COLLECTOR: Address for protocol fees
    ///      - HOOK_FEE_COLLECTOR: Address for hook fees
    function run() external returns (StableSwapHooksFactory factory) {
        console2.log("=== StableSwapHooksFactory CREATE2 Deployment ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("Deployer:", msg.sender);

        // Get chain config
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);
        console2.log("Chain:", config.name);

        // Get PoolManager address
        address poolManagerAddr = vm.envOr("POOL_MANAGER", config.poolManager);
        require(poolManagerAddr != address(0), "PoolManager address not configured");
        console2.log("PoolManager:", poolManagerAddr);

        IPoolManager poolManager = IPoolManager(poolManagerAddr);

        // Get configuration
        address factoryOwner = vm.envAddress("FACTORY_OWNER");
        address protocolFeeCollector = vm.envAddress("PROTOCOL_FEE_COLLECTOR");
        address hookFeeCollector = vm.envAddress("HOOK_FEE_COLLECTOR");

        console2.log("Factory Owner:", factoryOwner);
        console2.log("Protocol Fee Collector:", protocolFeeCollector);
        console2.log("Hook Fee Collector:", hookFeeCollector);

        // Calculate creation code hash for hooks
        bytes32 hooksCreationCodeHash = keccak256(type(StableSwapHooks).creationCode);
        console2.log("Hooks Creation Code Hash:");
        console2.logBytes32(hooksCreationCodeHash);

        // Prepare factory bytecode
        bytes memory factoryBytecode = abi.encodePacked(
            type(StableSwapHooksFactory).creationCode,
            abi.encode(poolManager, factoryOwner, protocolFeeCollector, hookFeeCollector, hooksCreationCodeHash)
        );

        // Predict address
        address predictedAddress = Create2.computeAddress(SALT, keccak256(factoryBytecode), msg.sender);
        console2.log("\nPredicted Factory Address:", predictedAddress);
        console2.log("Salt:");
        console2.logBytes32(SALT);

        // Check if already deployed
        if (predictedAddress.code.length > 0) {
            console2.log("Factory already deployed at this address");
            console2.log("If you want a new deployment, change the SALT in the script");
            factory = StableSwapHooksFactory(predictedAddress);
        } else {
            console2.log("\nDeploying...\n");

            vm.startBroadcast();

            // Deploy using CREATE2
            factory = StableSwapHooksFactory(Create2.deploy(0, SALT, factoryBytecode));

            vm.stopBroadcast();

            require(address(factory) == predictedAddress, "Address mismatch!");
        }

        console2.log("\n=== Deployment Complete ===");
        console2.log("Factory Address:", address(factory));
        console2.log("Hooks Creation Code Hash:");
        console2.logBytes32(hooksCreationCodeHash);
        console2.log("\nThis address will be the SAME on all chains if deployed by the same account!");
        console2.log("\nSave for hook deployments:");
        console2.log("FACTORY_ADDRESS=%s", address(factory));
    }

    /// @notice Compute the factory address without deploying
    /// @dev Useful for verifying addresses before deployment
    function computeAddress() external view returns (address) {
        address poolManagerAddr = vm.envOr("POOL_MANAGER", address(0));
        address factoryOwner = vm.envOr("FACTORY_OWNER", address(0));
        address protocolFeeCollector = vm.envOr("PROTOCOL_FEE_COLLECTOR", address(0));
        address hookFeeCollector = vm.envOr("HOOK_FEE_COLLECTOR", address(0));
        bytes32 hooksCreationCodeHash = keccak256(type(StableSwapHooks).creationCode);

        bytes memory factoryBytecode = abi.encodePacked(
            type(StableSwapHooksFactory).creationCode,
            abi.encode(poolManagerAddr, factoryOwner, protocolFeeCollector, hookFeeCollector, hooksCreationCodeHash)
        );

        return Create2.computeAddress(SALT, keccak256(factoryBytecode), msg.sender);
    }
}

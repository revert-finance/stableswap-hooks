// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";
import {Base} from "src/Base.sol";
import {ChainConfig} from "./config/ChainConfig.sol";

/// @notice Script to deploy StableSwapHooks via factory and optionally initialize pools
/// @dev Usage:
///   With keystore: forge script script/DeployHook.s.sol:DeployHook --rpc-url <RPC_URL> --account <ACCOUNT_NAME> --sender <ADDRESS> --broadcast
///   With private key: forge script script/DeployHook.s.sol:DeployHook --rpc-url <RPC_URL> --private-key <KEY> --broadcast
///   Interactive: forge script script/DeployHook.s.sol:DeployHook --rpc-url <RPC_URL> --interactive --broadcast
contract DeployHook is Script {
    using PoolIdLibrary for PoolKey;

    /// @notice Deploy a StableSwapHooks contract via the factory
    /// @dev Reads configuration from environment variables:
    ///      - FACTORY_ADDRESS: Address of deployed StableSwapHooksFactory
    ///      - CURRENCIES: Comma-separated list of currency addresses (sorted ascending)
    ///      - RATE_ORACLES: Comma-separated list of rate oracle addresses (use 0x0 for none)
    ///      - RATE_ORACLE_SELECTORS: Comma-separated list of function selectors (use 0x00000000 for none)
    ///      - LP_FEE_PERCENTAGE: LP fee percentage (scaled by 1e6)
    ///      - BASE_AMP: Initial amplification coefficient
    ///      - INITIALIZE_POOLS: Set to "true" to initialize pools after deployment
    ///      - SQRT_PRICE_X96: Initial sqrt price (default: 1<<96, only if INITIALIZE_POOLS=true)
    function run() external returns (StableSwapHooks hooks) {
        console2.log("=== StableSwapHooks Deployment ===");
        console2.log("Chain ID:", block.chainid);

        // Get chain config
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);
        console2.log("Chain:", config.name);

        // Get factory
        address factoryAddr = vm.envAddress("FACTORY_ADDRESS");
        StableSwapHooksFactory factory = StableSwapHooksFactory(factoryAddr);
        console2.log("Factory:", factoryAddr);

        // Parse currencies
        string memory currenciesStr = vm.envString("CURRENCIES");
        Currency[] memory currencies = _parseCurrencies(currenciesStr);
        console2.log("Number of currencies:", currencies.length);
        for (uint256 i = 0; i < currencies.length; i++) {
            console2.log("  Currency", i, ":", Currency.unwrap(currencies[i]));
        }

        // Parse rate oracles
        string memory oraclesStr = vm.envString("RATE_ORACLES");
        string memory selectorsStr = vm.envString("RATE_ORACLE_SELECTORS");
        Base.RateOracleConfig[] memory rateOracles = _parseRateOracles(oraclesStr, selectorsStr, currencies.length);

        // Get fee and amp parameters
        uint256 lpFeePercentage = vm.envUint("LP_FEE_PERCENTAGE");
        uint256 baseAmp = vm.envUint("BASE_AMP");

        console2.log("LP Fee Percentage:", lpFeePercentage);
        console2.log("Base Amplification:", baseAmp);

        // Get creation code
        bytes memory creationCode = type(StableSwapHooks).creationCode;

        // Mine salt (simulate call to get salt without broadcasting)
        console2.log("\nMining salt for valid hook address...");
        (address predictedHookAddress, bytes32 salt) =
            factory.mineSalt(currencies, rateOracles, lpFeePercentage, baseAmp, creationCode);
        console2.log("Predicted hook address:", predictedHookAddress);
        console2.log("Salt:");
        console2.logBytes32(salt);

        console2.log("\nDeploying...\n");

        // Deploy hook
        vm.startBroadcast();

        hooks = StableSwapHooks(factory.deploy(currencies, rateOracles, lpFeePercentage, baseAmp, salt, creationCode));

        console2.log("Hook deployed at:", address(hooks));

        // Initialize pools if requested
        bool shouldInitialize = vm.envOr("INITIALIZE_POOLS", false);
        if (shouldInitialize) {
            console2.log("\nInitializing pools...");
            uint160 sqrtPriceX96 = uint160(vm.envOr("SQRT_PRICE_X96", uint256(1 << 96)));
            _initializePools(hooks, currencies, lpFeePercentage, sqrtPriceX96);
        }

        vm.stopBroadcast();

        console2.log("\n=== Deployment Complete ===");
        console2.log("Hook Address:", address(hooks));
        console2.log("Factory:", factoryAddr);
        console2.log("Number of Currencies:", currencies.length);
        console2.log("LP Fee:", lpFeePercentage);
        console2.log("Base Amp:", baseAmp);
        if (shouldInitialize) {
            console2.log("Pools: Initialized");
        }
    }

    /// @dev Parse comma-separated currency addresses
    function _parseCurrencies(string memory currenciesStr) private pure returns (Currency[] memory) {
        // Count commas to determine array size
        bytes memory data = bytes(currenciesStr);
        uint256 count = 1;
        for (uint256 i = 0; i < data.length; i++) {
            if (data[i] == ",") count++;
        }

        Currency[] memory currencies = new Currency[](count);
        uint256 index = 0;
        uint256 start = 0;

        for (uint256 i = 0; i <= data.length; i++) {
            if (i == data.length || data[i] == ",") {
                currencies[index] = Currency.wrap(_parseAddress(currenciesStr, start, i));
                index++;
                start = i + 1;
            }
        }

        return currencies;
    }

    /// @dev Parse rate oracle configurations
    function _parseRateOracles(string memory oraclesStr, string memory selectorsStr, uint256 count)
        private
        pure
        returns (Base.RateOracleConfig[] memory)
    {
        Base.RateOracleConfig[] memory configs = new Base.RateOracleConfig[](count);

        // Parse oracles
        bytes memory oracleData = bytes(oraclesStr);
        uint256 index = 0;
        uint256 start = 0;

        for (uint256 i = 0; i <= oracleData.length; i++) {
            if (i == oracleData.length || oracleData[i] == ",") {
                configs[index].oracle = _parseAddress(oraclesStr, start, i);
                index++;
                start = i + 1;
            }
        }

        // Parse selectors
        bytes memory selectorData = bytes(selectorsStr);
        index = 0;
        start = 0;

        for (uint256 i = 0; i <= selectorData.length; i++) {
            if (i == selectorData.length || selectorData[i] == ",") {
                configs[index].selector = _parseBytes4(selectorsStr, start, i);
                index++;
                start = i + 1;
            }
        }

        return configs;
    }

    /// @dev Parse address from substring
    function _parseAddress(string memory str, uint256 start, uint256 end) private pure returns (address) {
        bytes memory data = bytes(str);
        bytes memory substr = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            substr[i - start] = data[i];
        }
        return vm.parseAddress(string(substr));
    }

    /// @dev Parse bytes4 from substring
    function _parseBytes4(string memory str, uint256 start, uint256 end) private pure returns (bytes4) {
        bytes memory data = bytes(str);
        bytes memory substr = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            substr[i - start] = data[i];
        }
        return bytes4(vm.parseBytes(string(substr)));
    }

    /// @dev Initialize all pairwise pools
    function _initializePools(
        StableSwapHooks hooks,
        Currency[] memory currencies,
        uint256 lpFeePercentage,
        uint160 sqrtPriceX96
    ) private {
        IPoolManager poolManager = hooks.poolManager();

        // Initialize all pairwise combinations
        for (uint256 i = 0; i < currencies.length; i++) {
            for (uint256 j = i + 1; j < currencies.length; j++) {
                PoolKey memory key = PoolKey({
                    currency0: currencies[i],
                    currency1: currencies[j],
                    fee: uint24(lpFeePercentage),
                    tickSpacing: hooks.TICK_SPACING(),
                    hooks: IHooks(address(hooks))
                });

                PoolId poolId = key.toId();
                console2.log("Initializing pool:");
                console2.log("  currency0:", Currency.unwrap(key.currency0));
                console2.log("  currency1:", Currency.unwrap(key.currency1));
                console2.logBytes32(PoolId.unwrap(poolId));

                poolManager.initialize(key, sqrtPriceX96);
            }
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";
import {Base} from "src/Base.sol";

/// @notice Usage:
///   forge script script/DeployUSDSUSDCUSDTBaseStablePool.s.sol:DeployUSDSUSDCUSDTBaseStablePool \
///     --rpc-url base --broadcast --verify -vvvv \
///     --sig "run(address)" <FACTORY_ADDRESS>
contract DeployUSDSUSDCUSDTBaseStablePool is Script {
    // https://basescan.org/token/0x820c137fa70c8691f0e44dc420a5e53c168921dc
    address public constant USDS = 0x820C137fa70C8691f0e44Dc420a5e53c168921Dc;

    // https://basescan.org/token/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // https://basescan.org/token/0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2
    address public constant USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;

    // 0.05%
    uint256 public constant LP_FEE_PERCENTAGE = 500;

    uint256 public constant BASE_AMP = 500;

    // 10% of lp fee
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 100_000;

    // 20% of lp fee
    uint256 public constant HOOK_FEE_PERCENTAGE = 200_000;

    uint256 public constant BASE_CHAIN_ID = 8453;

    function run(address _factory) external {
        require(block.chainid == BASE_CHAIN_ID, "pool is Base-only");

        StableSwapHooksFactory factory = StableSwapHooksFactory(_factory);

        Currency[] memory currencies = new Currency[](3);
        currencies[0] = Currency.wrap(USDS);
        currencies[1] = Currency.wrap(USDC);
        currencies[2] = Currency.wrap(USDT);

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](3);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[2] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory creationCode = type(StableSwapHooks).creationCode;
        bytes32 creationCodeHash = keccak256(creationCode);
        bytes32 factoryCreationCodeHash = factory.creationCodeHash();

        require(factoryCreationCodeHash == creationCodeHash, "creation code missmatch");

        bytes memory constructorArgs =
            abi.encode(factory.poolManager(), currencies, rateOracles, LP_FEE_PERCENTAGE, BASE_AMP);

        console2.log("Mining CREATE2 salt...");

        (address predictedAddress, bytes32 salt) =
            HookMiner.find(address(factory), factory.HOOK_FLAGS(), creationCode, constructorArgs);

        console2.log("Salt found:         ", vm.toString(salt));
        console2.log("Predicted address:  ", predictedAddress);

        vm.startBroadcast();

        address deployedHook = factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, BASE_AMP, salt, creationCode);

        StableSwapHooks(deployedHook).setProtocolFeePercentage(PROTOCOL_FEE_PERCENTAGE);
        StableSwapHooks(deployedHook).setHookFeePercentage(HOOK_FEE_PERCENTAGE);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Deployment Complete ===");
        console2.log("Hook:               ", deployedHook);
        console2.log("Factory:            ", address(factory));
        console2.log("Pool Manager:       ", address(factory.poolManager()));
        console2.log("Currencies:          USDS, USDC, USDT");
        console2.log("Gross LP Fee:        0.05%");
        console2.log("Net LP Fee:          0.035%");
        console2.log("Amp:                ", BASE_AMP);
        console2.log("Protocol Fee Share:  10% of gross LP fee (0.005% of swap amount)");
        console2.log("Hook Fee Share:      20% of gross LP fee (0.01% of swap amount)");
    }
}

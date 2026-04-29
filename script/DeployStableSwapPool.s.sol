// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {console2} from "forge-std/Script.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";
import {Base} from "src/Base.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {StableSwapHooksCreationCodeResolver} from "./StableSwapHooksCreationCodeResolver.sol";

/// @notice Deploys a 3-token StableSwap pool (USDC, USDT, DAI) on Base mainnet.
/// @dev Assumes StableSwapHooksFactory is already deployed.
///      The deployer must be the factory owner to configure fees.
///
/// Usage:
///   forge script script/DeployStableSwapPool.s.sol:DeployStableSwapPool \
///     --rpc-url base --broadcast --verify -vvvv \
///     --sig "run(address)" <FACTORY_ADDRESS>
contract DeployStableSwapPool is StableSwapHooksCreationCodeResolver {
    // ── Base mainnet token addresses (sorted ascending) ──────────────────

    address constant USDS = 0x820C137fa70C8691f0e44Dc420a5e53c168921Dc; // 18 decimals
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // 6 decimals
    address constant USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2; // 6 decimals

    // ── Pool parameters ──────────────────────────────────────────────────

    uint256 constant LP_FEE_PERCENTAGE = 500; // 0.05% of swap amount
    uint256 constant BASE_AMP = 500;
    uint256 constant PROTOCOL_FEE_PERCENTAGE = 100_000; // 10% of gross LP fee = 0.005% of swap amount
    uint256 constant HOOK_FEE_PERCENTAGE = 200_000; // 20% of gross LP fee = 0.01% of swap amount

    /// @notice Deploys the StableSwap pool via an existing factory.
    /// @param _factory Address of the deployed StableSwapHooksFactory.
    function run(address _factory) external {
        StableSwapHooksFactory factory = StableSwapHooksFactory(_factory);

        // ── 1. Build deployment parameters ───────────────────────────────

        Currency[] memory currencies = new Currency[](3);
        currencies[0] = Currency.wrap(USDS);
        currencies[1] = Currency.wrap(USDC);
        currencies[2] = Currency.wrap(USDT);

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](3);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[2] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory creationCode = _resolveCreationCode(factory);
        bytes memory constructorArgs =
            abi.encode(factory.poolManager(), currencies, rateOracles, LP_FEE_PERCENTAGE, BASE_AMP);

        // ── 2. Mine CREATE2 salt (pure computation, no gas cost) ─────────

        console2.log("Mining CREATE2 salt...");

        (address predictedAddress, bytes32 salt) =
            HookMiner.find(address(factory), factory.HOOK_FLAGS(), creationCode, constructorArgs);

        console2.log("Salt found:         ", vm.toString(salt));
        console2.log("Predicted address:  ", predictedAddress);

        // ── 3. Deploy hook and configure fees ────────────────────────────

        vm.startBroadcast();

        address deployedHook = factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, BASE_AMP, salt, creationCode);

        StableSwapHooks(deployedHook).setProtocolFeePercentage(PROTOCOL_FEE_PERCENTAGE);
        StableSwapHooks(deployedHook).setHookFeePercentage(HOOK_FEE_PERCENTAGE);

        vm.stopBroadcast();

        // ── 4. Summary ──────────────────────────────────────────────────

        console2.log("");
        console2.log("=== Deployment Complete ===");
        console2.log("Hook:               ", deployedHook);
        console2.log("Factory:            ", address(factory));
        console2.log("Pool Manager:       ", address(factory.poolManager()));
        console2.log("Currencies:          USDS, USDC, USDT");
        console2.log("Gross LP Fee:        0.05%%");
        console2.log("Net LP Fee:          0.035%%");
        console2.log("Amp:                ", BASE_AMP);
        console2.log("Protocol Fee Share:  10%% of gross LP fee (0.005%% of swap amount)");
        console2.log("Hook Fee Share:      20%% of gross LP fee (0.01%% of swap amount)");
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {console2} from "forge-std/Script.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";
import {Base} from "src/Base.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {StableSwapHooksCreationCodeResolver} from "./StableSwapHooksCreationCodeResolver.sol";

interface IChainlinkAggregatorV3Like {
    function latestAnswer() external view returns (int256);
}

/// @notice Deploys a 2-token StableSwap pool (cbETH, WETH) on Base mainnet.
/// @dev Assumes StableSwapHooksFactory is already deployed.
///      cbETH is currency0 because 0x2ae3... < 0x4200...
///
/// Usage:
///   forge script script/DeployStableSwapCbETHWETHPool.s.sol:DeployStableSwapCbETHWETHPool ///     --rpc-url base --broadcast --verify -vvvv ///     --sig "run(address)" <FACTORY_ADDRESS>
contract DeployStableSwapCbETHWETHPool is StableSwapHooksCreationCodeResolver {
    // ── Base mainnet addresses (sorted ascending) ────────────────────────

    address constant CBETH = 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22;
    address constant WETH = 0x4200000000000000000000000000000000000006;

    // Chainlink cbETH / ETH feed on Base.
    address constant CBETH_ETH_FEED = 0x806b4Ac04501c29769051e42783cF04dCE41440b;

    // ── Pool parameters ──────────────────────────────────────────────────

    uint256 constant LP_FEE_PERCENTAGE = 300; // 0.03% of swap amount
    uint256 constant BASE_AMP = 100;
    uint256 constant PROTOCOL_FEE_PERCENTAGE = 100_000; // 10% of gross LP fee = 0.003% of swap amount
    uint256 constant HOOK_FEE_PERCENTAGE = 200_000; // 20% of gross LP fee = 0.006% of swap amount

    /// @notice Deploys the StableSwap pool via an existing factory.
    /// @param _factory Address of the deployed StableSwapHooksFactory.
    function run(address _factory) external {
        StableSwapHooksFactory factory = StableSwapHooksFactory(_factory);

        // ── 1. Build deployment parameters ───────────────────────────────

        Currency[] memory currencies = new Currency[](2);
        currencies[0] = Currency.wrap(CBETH);
        currencies[1] = Currency.wrap(WETH);

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] =
            Base.RateOracleConfig({oracle: CBETH_ETH_FEED, selector: IChainlinkAggregatorV3Like.latestAnswer.selector});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

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
        console2.log("Currencies:          cbETH, WETH");
        console2.log("cbETH Oracle:       ", CBETH_ETH_FEED);
        console2.log("Oracle Selector:     latestAnswer()");
        console2.log("Gross LP Fee:        0.03%%");
        console2.log("Net LP Fee:          0.021%%");
        console2.log("Amp:                ", BASE_AMP);
        console2.log("Protocol Fee Share:  10%% of gross LP fee (0.003%% of swap amount)");
        console2.log("Hook Fee Share:      20%% of gross LP fee (0.006%% of swap amount)");
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";
import {Base} from "src/Base.sol";
import {ChainlinkOracleAdapter} from "src/oracles/ChainlinkOracleAdapter.sol";

/// @notice Usage:
///   forge script script/DeployCbETHWETHBaseStablePool.s.sol:DeployCbETHWETHBaseStablePool \
///     --rpc-url base --broadcast --verify -vvvv \
///     --sig "run(address,address)" <FACTORY_ADDRESS> <ADAPTER_ADDRESS>
contract DeployCbETHWETHBaseStablePool is Script {
    // https://basescan.org/token/0x2ae3f1ec7f1f5012cfeab0185bfc7aa3cf0dec22
    address public constant CBETH = 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22;

    // https://basescan.org/token/0x4200000000000000000000000000000000000006
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    // 0.03%
    uint256 public constant LP_FEE_PERCENTAGE = 300;

    uint256 public constant BASE_AMP = 100;

    // 10% of lp fee
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 100_000;

    // 20% of lp fee
    uint256 public constant HOOK_FEE_PERCENTAGE = 200_000;

    uint256 public constant BASE_CHAIN_ID = 8453;

    function run(address _factory, address _adapter) external {
        require(block.chainid == BASE_CHAIN_ID, "pool is Base-only");

        StableSwapHooksFactory factory = StableSwapHooksFactory(_factory);

        Currency[] memory currencies = new Currency[](2);
        currencies[0] = Currency.wrap(CBETH);
        currencies[1] = Currency.wrap(WETH);

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: _adapter, selector: ChainlinkOracleAdapter.getRate.selector});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

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
        console2.log("Currencies:          cbETH, WETH");
        console2.log("cbETH Oracle:       ", _adapter);
        console2.log("Oracle Selector:     getRate()");
        console2.log("Gross LP Fee:        0.03%");
        console2.log("Net LP Fee:          0.021%");
        console2.log("Amp:                ", BASE_AMP);
        console2.log("Protocol Fee Share:  10% of gross LP fee (0.003% of swap amount)");
        console2.log("Hook Fee Share:      20% of gross LP fee (0.006% of swap amount)");
    }
}

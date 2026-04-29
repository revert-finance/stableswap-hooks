// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {StableSwapZapIn} from "src/periphery/StableSwapZapIn.sol";
import {IStableSwapHooksFactory} from "src/interfaces/IStableSwapHooksFactory.sol";

/// @notice Deploys the StableSwapZapIn periphery contract.
///
/// Usage:
///   forge script script/DeployStableSwapZapIn.s.sol:DeployStableSwapZapIn \
///     --rpc-url base --broadcast --verify -vvvv \
///     --sig "run(address)" <FACTORY_ADDRESS>
contract DeployStableSwapZapIn is Script {
    function run() external {
        _run(vm.envAddress("STABLESWAP_FACTORY"));
    }

    function run(address _factory) external {
        _run(_factory);
    }

    function _run(address _factory) private {
        address poolManager = address(IStableSwapHooksFactory(_factory).poolManager());
        address wrappedNative = _getWrappedNative();

        console2.log("Deploying StableSwapZapIn");
        console2.log("Chain ID:    ", block.chainid);
        console2.log("Factory:     ", _factory);
        console2.log("PoolManager: ", poolManager);
        console2.log("WrappedNative:", wrappedNative);

        vm.startBroadcast();
        StableSwapZapIn zapIn = new StableSwapZapIn(_factory, wrappedNative);
        vm.stopBroadcast();

        console2.log("StableSwapZapIn deployed at:", address(zapIn));
    }

    function _getWrappedNative() private view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 1) return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Ethereum WETH
        if (
            chainId == 10 || chainId == 130 || chainId == 8453 || chainId == 7777777 || chainId == 480
                || chainId == 57073 || chainId == 1868 || chainId == 1301 || chainId == 84532
        ) return 0x4200000000000000000000000000000000000006; // OP Stack wrapped native predeploy
        if (chainId == 42161) return 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // Arbitrum WETH

        // For other supported PoolManager chains, provide WRAPPED_NATIVE explicitly when running the script.
        return vm.envAddress("WRAPPED_NATIVE");
    }
}

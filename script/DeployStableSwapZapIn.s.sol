// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {StableSwapZapIn} from "src/periphery/StableSwapZapIn.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {IStableSwapHooksFactory} from "src/interfaces/IStableSwapHooksFactory.sol";

/// @notice Usage:
///   forge script script/DeployStableSwapZapIn.s.sol:DeployStableSwapZapIn \
///     --rpc-url base --broadcast --verify -vvvv \
///     --sig "run(address)" <FACTORY_ADDRESS>
contract DeployStableSwapZapIn is Script {
    function run(address _factory) external {
        address poolManager = address(IStableSwapHooksFactory(_factory).poolManager());
        bytes32 hooksCreationCodeHash = keccak256(type(StableSwapHooks).creationCode);

        console2.log("Deploying StableSwapZapIn");
        console2.log("Chain ID:    ", block.chainid);
        console2.log("Factory:     ", _factory);
        console2.log("PoolManager: ", poolManager);
        console2.log("Creation Code Hash:", vm.toString(hooksCreationCodeHash));

        vm.startBroadcast();

        StableSwapZapIn zapIn = new StableSwapZapIn(_factory, hooksCreationCodeHash);

        vm.stopBroadcast();

        console2.log("StableSwapZapIn deployed at:", address(zapIn));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {StableSwapZapIn} from "src/periphery/StableSwapZapIn.sol";

/// @notice Deploys the StableSwapZapIn periphery contract.
///
/// Usage:
///   forge script script/DeployStableSwapZapIn.s.sol:DeployStableSwapZapIn \
///     --rpc-url base --broadcast --verify -vvvv
contract DeployStableSwapZapIn is Script {
    function run() external {
        address poolManager = _getPoolManager();

        console2.log("Deploying StableSwapZapIn");
        console2.log("Chain ID:    ", block.chainid);
        console2.log("PoolManager: ", poolManager);

        vm.startBroadcast();
        StableSwapZapIn zapIn = new StableSwapZapIn(poolManager);
        vm.stopBroadcast();

        console2.log("StableSwapZapIn deployed at:", address(zapIn));
    }

    function _getPoolManager() private view returns (address) {
        uint256 chainId = block.chainid;

        // Mainnets
        if (chainId == 1) return 0x000000000004444c5dc75cB358380D2e3dE08A90; // Ethereum
        if (chainId == 130) return 0x1F98400000000000000000000000000000000004; // Unichain
        if (chainId == 10) return 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3; // Optimism
        if (chainId == 8453) return 0x498581fF718922c3f8e6A244956aF099B2652b2b; // Base
        if (chainId == 42161) return 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32; // Arbitrum
        if (chainId == 137) return 0x67366782805870060151383F4BbFF9daB53e5cD6; // Polygon
        if (chainId == 81457) return 0x1631559198A9e474033433b2958daBC135ab6446; // Blast
        if (chainId == 7777777) return 0x0575338e4C17006aE181B47900A84404247CA30f; // Zora
        if (chainId == 480) return 0xb1860D529182ac3BC1F51Fa2ABd56662b7D13f33; // Worldchain
        if (chainId == 57073) return 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32; // Ink
        if (chainId == 1868) return 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32; // Soneium
        if (chainId == 43114) return 0x06380C0e0912312B5150364B9DC4542BA0DbBc85; // Avalanche
        if (chainId == 56) return 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF; // BSC
        if (chainId == 42220) return 0x288dc841A52FCA2707c6947B3A777c5E56cd87BC; // Celo
        if (chainId == 10143) return 0x188d586Ddcf52439676Ca21A244753fA19F9Ea8e; // Monad

        // Testnets
        if (chainId == 1301) return 0x00B036B58a818B1BC34d502D3fE730Db729e62AC; // Unichain Sepolia
        if (chainId == 11155111) return 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543; // Sepolia
        if (chainId == 84532) return 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408; // Base Sepolia
        if (chainId == 421614) return 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317; // Arbitrum Sepolia

        revert("Unsupported chain");
    }
}

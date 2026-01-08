// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/// @notice Chain-specific configuration for deployments
/// @dev Stores configurations in a mapping-like pattern using pure functions
library ChainConfig {
    struct Config {
        uint256 chainId;
        string name;
        address poolManager;
    }

    /// @notice Unsupported chain error with chain ID
    error UnsupportedChain(uint256 chainId);

    /// @notice Get configuration for a specific chain
    /// @param chainId The chain ID to get config for
    /// @return config The chain configuration
    function getConfig(uint256 chainId) internal pure returns (Config memory config) {
        if (chainId == 1) return _ethereum();
        if (chainId == 42161) return _arbitrum();
        if (chainId == 10) return _optimism();
        if (chainId == 8453) return _base();
        if (chainId == 137) return _polygon();
        if (chainId == 56) return _bsc();
        if (chainId == 43114) return _avalanche();
        if (chainId == 42220) return _celo();
        if (chainId == 11155111) return _sepolia();
        if (chainId == 84532) return _baseSepolia();
        if (chainId == 421614) return _arbitrumSepolia();
        if (chainId == 11155420) return _optimismSepolia();
        if (chainId == 31337) return _anvil();

        revert UnsupportedChain(chainId);
    }

    /// @notice Check if a chain is supported
    function isSupported(uint256 chainId) internal pure returns (bool) {
        return chainId == 1 || chainId == 42161 || chainId == 10 || chainId == 8453 || chainId == 137 || chainId == 56
            || chainId == 43114 || chainId == 42220 || chainId == 11155111 || chainId == 84532 || chainId == 421614
            || chainId == 11155420 || chainId == 31337;
    }

    // Mainnet configurations
    function _ethereum() private pure returns (Config memory) {
        return Config({chainId: 1, name: "ethereum", poolManager: 0x000000000004444c5dc75cB358380D2e3dE08A90});
    }

    function _arbitrum() private pure returns (Config memory) {
        return Config({chainId: 42161, name: "arbitrum", poolManager: 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32});
    }

    function _optimism() private pure returns (Config memory) {
        return Config({chainId: 10, name: "optimism", poolManager: 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3});
    }

    function _base() private pure returns (Config memory) {
        return Config({chainId: 8453, name: "base", poolManager: 0x498581fF718922c3f8e6A244956aF099B2652b2b});
    }

    function _polygon() private pure returns (Config memory) {
        return Config({chainId: 137, name: "polygon", poolManager: 0x67366782805870060151383F4BbFF9daB53e5cD6});
    }

    function _bsc() private pure returns (Config memory) {
        return Config({chainId: 56, name: "bsc", poolManager: 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF});
    }

    function _avalanche() private pure returns (Config memory) {
        return Config({chainId: 43114, name: "avalanche", poolManager: 0x06380C0e0912312B5150364B9DC4542BA0DbBc85});
    }

    function _celo() private pure returns (Config memory) {
        return Config({chainId: 42220, name: "celo", poolManager: 0x288dc841A52FCA2707c6947B3A777c5E56cd87BC});
    }

    // Testnet configurations
    function _sepolia() private pure returns (Config memory) {
        return Config({chainId: 11155111, name: "sepolia", poolManager: 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543});
    }

    function _baseSepolia() private pure returns (Config memory) {
        return Config({chainId: 84532, name: "base-sepolia", poolManager: 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408});
    }

    function _arbitrumSepolia() private pure returns (Config memory) {
        return
            Config({chainId: 421614, name: "arbitrum-sepolia", poolManager: 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317});
    }

    function _optimismSepolia() private pure returns (Config memory) {
        return Config({chainId: 11155420, name: "optimism-sepolia", poolManager: address(0)});
    }

    // Local/Development
    function _anvil() private pure returns (Config memory) {
        return Config({chainId: 31337, name: "anvil", poolManager: address(0)});
    }
}

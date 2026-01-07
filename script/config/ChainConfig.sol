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
        bool testnet;
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
        return Config({chainId: 1, name: "ethereum", poolManager: address(0), testnet: false});
    }

    function _arbitrum() private pure returns (Config memory) {
        return Config({chainId: 42161, name: "arbitrum", poolManager: address(0), testnet: false});
    }

    function _optimism() private pure returns (Config memory) {
        return Config({chainId: 10, name: "optimism", poolManager: address(0), testnet: false});
    }

    function _base() private pure returns (Config memory) {
        return Config({chainId: 8453, name: "base", poolManager: address(0), testnet: false});
    }

    function _polygon() private pure returns (Config memory) {
        return Config({chainId: 137, name: "polygon", poolManager: address(0), testnet: false});
    }

    function _bsc() private pure returns (Config memory) {
        return Config({chainId: 56, name: "bsc", poolManager: address(0), testnet: false});
    }

    function _avalanche() private pure returns (Config memory) {
        return Config({chainId: 43114, name: "avalanche", poolManager: address(0), testnet: false});
    }

    function _celo() private pure returns (Config memory) {
        return Config({chainId: 42220, name: "celo", poolManager: address(0), testnet: false});
    }

    // Testnet configurations
    function _sepolia() private pure returns (Config memory) {
        return Config({chainId: 11155111, name: "sepolia", poolManager: address(0), testnet: true});
    }

    function _baseSepolia() private pure returns (Config memory) {
        return Config({chainId: 84532, name: "base-sepolia", poolManager: address(0), testnet: true});
    }

    function _arbitrumSepolia() private pure returns (Config memory) {
        return Config({chainId: 421614, name: "arbitrum-sepolia", poolManager: address(0), testnet: true});
    }

    function _optimismSepolia() private pure returns (Config memory) {
        return Config({chainId: 11155420, name: "optimism-sepolia", poolManager: address(0), testnet: true});
    }

    // Local/Development
    function _anvil() private pure returns (Config memory) {
        return Config({chainId: 31337, name: "anvil", poolManager: address(0), testnet: true});
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooksFactory} from "src/factories/StableSwapHooksFactory.sol";

/// @notice Test harness that adds mineSalt function for testing
/// @dev The mineSalt function consumes too much gas for production eth_call usage
contract StableSwapHooksFactoryHarness is StableSwapHooksFactory {
    constructor(
        IPoolManager _poolManager,
        address _owner,
        address _protocolFeeCollector,
        address _hookFeeCollector,
        bytes32 _creationCodeHash
    ) StableSwapHooksFactory(_poolManager, _owner, _protocolFeeCollector, _hookFeeCollector, _creationCodeHash) {}

    /// @notice Mines a CREATE2 salt that produces an address with the required hook permission flags
    /// @dev For testing only. Consumes too much gas for production eth_call usage.
    /// @param _currencies Array of currencies for the pool
    /// @param _rateOracles Array of rate oracle configurations for each currency
    /// @param _poolFeePercentage Total pool fee percentage (scaled by FEE_PRECISION)
    /// @param _baseAmp Initial amplification coefficient
    /// @param _creationCode StableSwapHooks creation bytecode
    function mineSalt(
        Currency[] calldata _currencies,
        Base.RateOracleConfig[] calldata _rateOracles,
        uint256 _poolFeePercentage,
        uint256 _baseAmp,
        bytes calldata _creationCode
    ) external view returns (address hookAddress, bytes32 salt) {
        bytes memory constructorArgs = abi.encode(poolManager, _currencies, _rateOracles, _poolFeePercentage, _baseAmp);

        (hookAddress, salt) = HookMiner.find(address(this), HOOK_FLAGS, _creationCode, constructorArgs);
    }
}

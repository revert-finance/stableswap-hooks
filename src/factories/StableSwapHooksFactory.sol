// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";

/// @notice Factory for deploying StableSwapHooks contracts using CREATE2
contract StableSwapHooksFactory {
    /// @notice Emitted when a new StableSwapHooks contract is deployed
    event StableSwapHooksDeployed(address indexed _hooks, address indexed _deployer);

    /// @notice Returns true if the hook was deployed by this factory
    mapping(address hook => bool deployed) public isDeployedByFactory;

    /// @notice Deploys a new StableSwapHooks contract using CREATE2
    /// @param _poolManager The Uniswap v4 PoolManager contract
    /// @param _currencies Array of currencies to create pools for (must be sorted ascending)
    /// @param _rateOracles Array of rate oracle configurations for each currency
    /// @param _protocolFeeCollector Address that receives protocol fees
    /// @param _protocolFeePercentage Protocol fee percentage (scaled by FEE_PRECISION)
    /// @param _hookFeePercentage Hook fee percentage (scaled by FEE_PRECISION)
    /// @param _lpFeePercentage LP fee percentage (scaled by FEE_PRECISION)
    /// @param _baseAmp Initial amplification coefficient
    /// @param _salt CREATE2 salt computed via mineSalt or off-chain using HookMiner
    function deploy(
        IPoolManager _poolManager,
        Currency[] memory _currencies,
        Base.RateOracleConfig[] memory _rateOracles,
        address _protocolFeeCollector,
        uint256 _protocolFeePercentage,
        uint256 _hookFeePercentage,
        uint256 _lpFeePercentage,
        uint256 _baseAmp,
        bytes32 _salt
    ) external returns (StableSwapHooks hooks) {
        hooks = new StableSwapHooks{salt: _salt}(
            _poolManager,
            _currencies,
            _rateOracles,
            _protocolFeeCollector,
            _protocolFeePercentage,
            _hookFeePercentage,
            _lpFeePercentage,
            _baseAmp
        );

        isDeployedByFactory[address(hooks)] = true;

        emit StableSwapHooksDeployed(address(hooks), msg.sender);
    }

    /// @notice Mines a CREATE2 salt that produces an address with the required hook permission flags
    /// @dev Intended for off-chain use via eth_call. Reverts if no valid salt found.
    /// @param _poolManager The Uniswap v4 PoolManager contract
    /// @param _currencies Array of currencies to create pools for
    /// @param _rateOracles Array of rate oracle configurations for each currency
    /// @param _protocolFeeCollector Address that receives protocol fees
    /// @param _protocolFeePercentage Protocol fee percentage (scaled by FEE_PRECISION)
    /// @param _hookFeePercentage Hook fee percentage (scaled by FEE_PRECISION)
    /// @param _lpFeePercentage LP fee percentage (scaled by FEE_PRECISION)
    /// @param _baseAmp Initial amplification coefficient
    /// @param _flags Required hook permission flags (bottom 14 bits of desired address)
    function mineSalt(
        IPoolManager _poolManager,
        Currency[] memory _currencies,
        Base.RateOracleConfig[] memory _rateOracles,
        address _protocolFeeCollector,
        uint256 _protocolFeePercentage,
        uint256 _hookFeePercentage,
        uint256 _lpFeePercentage,
        uint256 _baseAmp,
        uint160 _flags
    ) external view returns (address hookAddress, bytes32 salt) {
        bytes memory constructorArgs = abi.encode(
            _poolManager,
            _currencies,
            _rateOracles,
            _protocolFeeCollector,
            _protocolFeePercentage,
            _hookFeePercentage,
            _lpFeePercentage,
            _baseAmp
        );

        (hookAddress, salt) = HookMiner.find(address(this), _flags, type(StableSwapHooks).creationCode, constructorArgs);
    }
}

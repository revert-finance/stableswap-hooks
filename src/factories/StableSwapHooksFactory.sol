// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";

/// @notice Factory for deploying StableSwapHooks contracts using CREATE2
contract StableSwapHooksFactory is Ownable, Pausable {
    /// @notice The Uniswap v4 PoolManager contract
    IPoolManager public immutable poolManager;

    /// @notice Address that receives protocol fees
    address public protocolFeeCollector;

    /// @notice Address that receives hook fees
    address public hookFeeCollector;

    /// @notice Returns true if the hook was deployed by this factory
    mapping(address hook => bool deployed) public isDeployedByFactory;

    /// @notice Protocol fee percentage for each deployed hook
    mapping(address hook => uint256 feePercentage) public protocolFeePercentage;

    /// @notice Hook fee percentage for each deployed hook
    mapping(address hook => uint256 feePercentage) public hookFeePercentage;

    /// @notice Emitted when a new StableSwapHooks contract is deployed
    event StableSwapHooksDeployed(address indexed _sender, address indexed _hook);

    /// @notice Emitted when protocol fee collector is updated
    event ProtocolFeeCollectorSet(address indexed _sender, address indexed _collector);

    /// @notice Emitted when hook fee collector is updated
    event HookFeeCollectorSet(address indexed _sender, address indexed _collector);

    /// @notice Emitted when protocol fee percentage is updated for a hook
    event ProtocolFeePercentageSet(address indexed _sender, address indexed _hook, uint256 _feePercentage);

    /// @notice Emitted when hook fee percentage is updated for a hook
    event HookFeePercentageSet(address indexed _sender, address indexed _hook, uint256 _feePercentage);

    /// @notice Thrown when zero address is provided
    error ZeroAddress();

    /// @notice Constructs the factory
    /// @param _poolManager The Uniswap v4 PoolManager contract
    /// @param _owner The owner of the factory
    /// @param _protocolFeeCollector Address that receives protocol fees
    /// @param _hookFeeCollector Address that receives hook fees
    constructor(IPoolManager _poolManager, address _owner, address _protocolFeeCollector, address _hookFeeCollector)
        Ownable(_owner)
    {
        poolManager = _poolManager;
        _setProtocolFeeCollector(_protocolFeeCollector);
        _setHookFeeCollector(_hookFeeCollector);
    }

    /// @notice Sets the protocol fee collector address
    /// @param _collector New protocol fee collector address
    function setProtocolFeeCollector(address _collector) external onlyOwner {
        _setProtocolFeeCollector(_collector);
    }

    /// @notice Sets the hook fee collector address
    /// @param _collector New hook fee collector address
    function setHookFeeCollector(address _collector) external onlyOwner {
        _setHookFeeCollector(_collector);
    }

    /// @notice Sets the protocol fee percentage for a deployed hook
    /// @param _hook Address of the deployed hook
    /// @param _feePercentage Protocol fee percentage (scaled by FEE_PRECISION)
    function setProtocolFeePercentage(address _hook, uint256 _feePercentage) external onlyOwner {
        _setProtocolFeePercentage(_hook, _feePercentage);
    }

    /// @notice Sets the hook fee percentage for a deployed hook
    /// @param _hook Address of the deployed hook
    /// @param _feePercentage Hook fee percentage (scaled by FEE_PRECISION)
    function setHookFeePercentage(address _hook, uint256 _feePercentage) external onlyOwner {
        _setHookFeePercentage(_hook, _feePercentage);
    }

    /// @notice Pauses the factory, preventing new deployments
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the factory, allowing new deployments
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Deploys a new StableSwapHooks contract using CREATE2
    /// @param _currencies Array of currencies for the pool (must be sorted ascending)
    /// @param _rateOracles Array of rate oracle configurations for each currency
    /// @param _lpFeePercentage LP fee percentage (scaled by FEE_PRECISION)
    /// @param _baseAmp Initial amplification coefficient
    /// @param _salt CREATE2 salt computed via mineSalt or off-chain using HookMiner
    /// @return hook The deployed StableSwapHooks contract
    function deploy(
        Currency[] memory _currencies,
        Base.RateOracleConfig[] memory _rateOracles,
        uint256 _lpFeePercentage,
        uint256 _baseAmp,
        bytes32 _salt
    ) external whenNotPaused returns (StableSwapHooks hook) {
        hook = new StableSwapHooks{salt: _salt}(poolManager, _currencies, _rateOracles, _lpFeePercentage, _baseAmp);

        isDeployedByFactory[address(hook)] = true;

        emit StableSwapHooksDeployed(msg.sender, address(hook));
    }

    /// @notice Mines a CREATE2 salt that produces an address with the required hook permission flags
    /// @dev Intended for off-chain use via eth_call. Reverts if no valid salt found.
    /// @param _currencies Array of currencies for the pool
    /// @param _rateOracles Array of rate oracle configurations for each currency
    /// @param _lpFeePercentage LP fee percentage (scaled by FEE_PRECISION)
    /// @param _baseAmp Initial amplification coefficient
    /// @param _flags Required hook permission flags (bottom 14 bits of desired address)
    /// @return hookAddress The computed hook address
    /// @return salt The CREATE2 salt to use
    function mineSalt(
        Currency[] memory _currencies,
        Base.RateOracleConfig[] memory _rateOracles,
        uint256 _lpFeePercentage,
        uint256 _baseAmp,
        uint160 _flags
    ) external view returns (address hookAddress, bytes32 salt) {
        bytes memory constructorArgs = abi.encode(poolManager, _currencies, _rateOracles, _lpFeePercentage, _baseAmp);

        (hookAddress, salt) = HookMiner.find(address(this), _flags, type(StableSwapHooks).creationCode, constructorArgs);
    }

    /// @dev Internal setter for protocol fee collector
    function _setProtocolFeeCollector(address _collector) private {
        if (_collector == address(0)) revert ZeroAddress();
        protocolFeeCollector = _collector;
        emit ProtocolFeeCollectorSet(msg.sender, _collector);
    }

    /// @dev Internal setter for hook fee collector
    function _setHookFeeCollector(address _collector) private {
        if (_collector == address(0)) revert ZeroAddress();
        hookFeeCollector = _collector;
        emit HookFeeCollectorSet(msg.sender, _collector);
    }

    /// @dev Internal setter for protocol fee percentage
    function _setProtocolFeePercentage(address _hook, uint256 _feePercentage) private {
        protocolFeePercentage[_hook] = _feePercentage;
        emit ProtocolFeePercentageSet(msg.sender, _hook, _feePercentage);
    }

    /// @dev Internal setter for hook fee percentage
    function _setHookFeePercentage(address _hook, uint256 _feePercentage) private {
        hookFeePercentage[_hook] = _feePercentage;
        emit HookFeePercentageSet(msg.sender, _hook, _feePercentage);
    }
}

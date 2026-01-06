// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";

/// @notice Factory for deploying StableSwapHooks contracts using CREATE2
contract StableSwapHooksFactory is Ownable, Pausable {
    /// @notice Fee denominator for percentage calculations (100% = 1e6)
    uint256 public constant FEE_PRECISION = 1e6;

    /// @notice Hook permission flags required for StableSwapHooks
    uint160 public constant HOOK_FLAGS = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
        | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        | Hooks.BEFORE_DONATE_FLAG;

    /// @notice The Uniswap v4 PoolManager contract
    IPoolManager public immutable poolManager;

    /// @notice Address that receives protocol fees
    address public protocolFeeCollector;

    /// @notice Address that receives hook fees
    address public hookFeeCollector;

    /// @notice Returns true if the hook was deployed by this factory
    mapping(address hook => bool deployed) public isDeployedByFactory;

    /// @notice Emitted when a new StableSwapHooks contract is deployed
    event StableSwapHooksDeployed(address indexed _sender, address indexed _hook);

    /// @notice Emitted when protocol fee collector is updated
    event ProtocolFeeCollectorSet(address indexed _sender, address indexed _collector);

    /// @notice Emitted when hook fee collector is updated
    event HookFeeCollectorSet(address indexed _sender, address indexed _collector);

    /// @notice Thrown when zero address is provided
    error ZeroAddress();

    /// @notice Thrown when fee percentage exceeds FEE_PRECISION
    error InvalidFeePercentage();

    /// @notice Constructs the factory
    /// @param _poolManager The Uniswap v4 PoolManager contract
    /// @param _owner The owner of the factory
    /// @param _protocolFeeCollector Address that receives protocol fees
    /// @param _hookFeeCollector Address that receives hook fees
    constructor(IPoolManager _poolManager, address _owner, address _protocolFeeCollector, address _hookFeeCollector)
        Ownable(_owner)
    {
        _setProtocolFeeCollector(_protocolFeeCollector);
        _setHookFeeCollector(_hookFeeCollector);

        poolManager = _poolManager;
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
    function deploy(
        Currency[] memory _currencies,
        Base.RateOracleConfig[] memory _rateOracles,
        uint256 _lpFeePercentage,
        uint256 _baseAmp,
        bytes32 _salt
    ) external whenNotPaused returns (StableSwapHooks hook) {
        if (_lpFeePercentage > FEE_PRECISION) {
            revert InvalidFeePercentage();
        }

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
    function mineSalt(
        Currency[] memory _currencies,
        Base.RateOracleConfig[] memory _rateOracles,
        uint256 _lpFeePercentage,
        uint256 _baseAmp
    ) external view returns (address hookAddress, bytes32 salt) {
        bytes memory constructorArgs = abi.encode(poolManager, _currencies, _rateOracles, _lpFeePercentage, _baseAmp);

        (hookAddress, salt) =
            HookMiner.find(address(this), HOOK_FLAGS, type(StableSwapHooks).creationCode, constructorArgs);
    }

    /// @dev Internal setter for protocol fee collector
    function _setProtocolFeeCollector(address _collector) private {
        if (_collector == address(0)) {
            revert ZeroAddress();
        }

        protocolFeeCollector = _collector;

        emit ProtocolFeeCollectorSet(msg.sender, _collector);
    }

    /// @dev Internal setter for hook fee collector
    function _setHookFeeCollector(address _collector) private {
        if (_collector == address(0)) {
            revert ZeroAddress();
        }

        hookFeeCollector = _collector;

        emit HookFeeCollectorSet(msg.sender, _collector);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";

import {Actions} from "src/libraries/Actions.sol";
import {Base, RateOracleConfig} from "src/Base.sol";
import {Amp} from "src/Amp.sol";
import {Fees} from "src/Fees.sol";
import {Swap} from "src/Swap.sol";

/// @notice Main entry point contract implementing Uniswap v4 hooks for a StableSwap AMM
contract StableSwapHooks is IUnlockCallback, Swap {
    /// @notice Error thrown when an unrecognized action is passed to the unlock callback
    error InvalidAction();

    /// @notice Initializes the StableSwap hook with pool configuration and fee parameters
    /// @param _poolManager The Uniswap v4 PoolManager contract
    /// @param _currencies Array of currencies to create pools for (all pairwise combinations will be initialized)
    /// @param _rateOracles Array of rate oracle configurations for each currency (use address(0) for static rate)
    /// @param _protocolFeeCollector Address that receives protocol fees
    /// @param _protocolFeePercentage Protocol fee percentage (scaled by FEE_PRECISION)
    /// @param _hookFeePercentage Hook fee percentage (scaled by FEE_PRECISION)
    /// @param _lpFeePercentage LP fee percentage (scaled by FEE_PRECISION)
    /// @param _baseAmp Initial amplification coefficient
    constructor(
        IPoolManager _poolManager,
        Currency[] memory _currencies,
        RateOracleConfig[] memory _rateOracles,
        address _protocolFeeCollector,
        uint256 _protocolFeePercentage,
        uint256 _hookFeePercentage,
        uint256 _lpFeePercentage,
        uint256 _baseAmp
    )
        Base(_poolManager, _lpFeePercentage, _currencies, _rateOracles)
        Amp(_baseAmp)
        Fees(_protocolFeeCollector, _protocolFeePercentage, _hookFeePercentage, _lpFeePercentage)
    {}

    /// @notice Callback function invoked by the pool manager during unlock
    /// @dev Routes to appropriate handler based on the action type encoded in data
    /// @param data Encoded data containing action type and action-specific parameters
    /// @return Empty bytes on success
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        uint256 action = abi.decode(data, (uint256));

        if (action == Actions.ADD_LIQUIDITY) {
            _handleAddLiquidityCallback(data);
        } else if (action == Actions.REMOVE_LIQUIDITY) {
            _handleRemoveLiquidityCallback(data);
        } else if (action == Actions.WITHDRAW_PROTOCOL_FEES) {
            _handleWithdrawProtocolFeesCallback(data);
        } else if (action == Actions.WITHDRAW_HOOK_FEES) {
            _handleWithdrawHookFeesCallback(data);
        } else {
            revert InvalidAction();
        }

        return "";
    }
}

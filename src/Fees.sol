// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {Actions} from "src/libraries/Actions.sol";
import {Liquidity} from "src/Liquidity.sol";

/// @notice Abstract contract that manages protocol, hook, and LP fee collection and distribution
abstract contract Fees is Liquidity {
    /// @notice Accumulated protocol fees for currencies
    uint256[] public protocolFees;

    /// @notice Accumulated hook fees for currencies
    uint256[] public hookFees;

    /// @notice Emitted when protocol fees are withdrawn
    event ProtocolFeesWithdrawn(
        address indexed _sender, address indexed _protocolFeeCollector, uint256[] _protocolFees
    );

    /// @notice Emitted when hook fees are withdrawn
    event HookFeesWithdrawn(address indexed _sender, address indexed _hookFeeCollector, uint256[] _hookFees);

    /// @notice Error thrown when an invalid address (zero address) is provided
    error InvalidAddress();

    /// @notice Initializes the fee configuration
    /// @dev Each fee setter validates that the sum of all fee percentages does not exceed feePrecision
    constructor() {
        protocolFees = new uint256[](currenciesLength);
        hookFees = new uint256[](currenciesLength);
    }

    /// @notice Withdraws accumulated protocol fees to the protocol fee collector
    /// @dev Triggers an unlock callback to handle the withdrawal through the pool manager
    function withdrawProtocolFees() external {
        bytes memory data = abi.encode(Actions.WITHDRAW_PROTOCOL_FEES, _msgSender());

        poolManager.unlock(data);
    }

    /// @notice Withdraws accumulated hook fees to the hook fee collector
    /// @dev Triggers an unlock callback to handle the withdrawal through the pool manager
    function withdrawHookFees() external {
        bytes memory data = abi.encode(Actions.WITHDRAW_HOOK_FEES, _msgSender());

        poolManager.unlock(data);
    }

    /// @dev Callback handler for protocol fee withdrawals
    function _handleWithdrawProtocolFeesCallback(bytes calldata data) internal {
        (, address sender) = abi.decode(data, (uint256, address));

        address _protocolFeeCollector = factory.protocolFeeCollector();
        uint256[] memory _protocolFees = protocolFees;

        _handleWithdrawFeesPoolManagerAccounting(_protocolFeeCollector, _protocolFees);

        for (uint256 i = 0; i < currenciesLength; i++) {
            protocolFees[i] = 0;
        }

        emit ProtocolFeesWithdrawn(sender, _protocolFeeCollector, _protocolFees);
    }

    /// @dev Callback handler for hook fee withdrawals
    function _handleWithdrawHookFeesCallback(bytes calldata data) internal {
        (, address sender) = abi.decode(data, (uint256, address));

        address _hookFeeCollector = factory.hookFeeCollector();
        uint256[] memory _hookFees = hookFees;

        _handleWithdrawFeesPoolManagerAccounting(_hookFeeCollector, _hookFees);

        for (uint256 i = 0; i < currenciesLength; i++) {
            hookFees[i] = 0;
        }

        emit HookFeesWithdrawn(sender, _hookFeeCollector, _hookFees);
    }

    /// @dev Handles pool manager accounting for fee withdrawals
    function _handleWithdrawFeesPoolManagerAccounting(address _beneficiary, uint256[] memory _fees) private {
        if (_beneficiary == address(0)) {
            revert InvalidAddress();
        }

        for (uint256 i = 0; i < _fees.length; i++) {
            if (_fees[i] != 0) {
                poolManager.burn(address(this), currencies[i].toId(), _fees[i]);
                poolManager.take(currencies[i], _beneficiary, _fees[i]);
            }
        }
    }

    /// @dev Adds fees to the appropriate accumulators
    function _addFees(uint256 _currencyIndex, uint256 _protocolFees, uint256 _hookFees) internal {
        protocolFees[_currencyIndex] += _protocolFees;
        hookFees[_currencyIndex] += _hookFees;
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/// @notice Library containing action identifiers for pool manager unlock callbacks
library Actions {
    /// @notice Action identifier for adding liquidity to the pool
    uint256 internal constant ADD_LIQUIDITY = 1;

    /// @notice Action identifier for removing liquidity from the pool
    uint256 internal constant REMOVE_LIQUIDITY = 2;

    /// @notice Action identifier for withdrawing accumulated protocol fees
    uint256 internal constant WITHDRAW_PROTOCOL_FEES = 3;

    /// @notice Action identifier for withdrawing accumulated hook fees
    uint256 internal constant WITHDRAW_HOOK_FEES = 4;
}

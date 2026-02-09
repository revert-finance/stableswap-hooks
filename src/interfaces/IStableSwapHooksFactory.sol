// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/// @notice Interface for StableSwapHooksFactory
interface IStableSwapHooksFactory {
    /// @notice Returns the factory owner address
    function owner() external view returns (address);

    /// @notice Returns the protocol fee collector address
    function protocolFeeCollector() external view returns (address);

    /// @notice Returns the hook fee collector address
    function hookFeeCollector() external view returns (address);
}

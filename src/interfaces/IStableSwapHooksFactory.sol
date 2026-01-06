// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Interface for StableSwapHooksFactory fee configuration
interface IStableSwapHooksFactory {
    /// @notice Returns the factory owner address
    function owner() external view returns (address);

    /// @notice Returns the protocol fee collector address
    function protocolFeeCollector() external view returns (address);

    /// @notice Returns the hook fee collector address
    function hookFeeCollector() external view returns (address);

    /// @notice Returns the protocol fee percentage for a hook
    /// @param _hook The hook address
    function protocolFeePercentage(address _hook) external view returns (uint256);

    /// @notice Returns the hook fee percentage for a hook
    /// @param _hook The hook address
    function hookFeePercentage(address _hook) external view returns (uint256);

    /// @notice Calculates LP, hook, and protocol fees from a given amount for a hook
    /// @param _hook The hook address
    /// @param _amount The amount to calculate fees on
    function getFees(address _hook, uint256 _amount)
        external
        view
        returns (uint256 lpFees, uint256 hookFees, uint256 protocolFees);
}

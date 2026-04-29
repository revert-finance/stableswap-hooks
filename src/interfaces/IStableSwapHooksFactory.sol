// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/// @notice Interface for StableSwapHooksFactory
interface IStableSwapHooksFactory {
    /// @notice Returns the factory owner address
    function owner() external view returns (address);

    /// @notice Returns the PoolManager used by factory-deployed hooks
    function poolManager() external view returns (IPoolManager);

    /// @notice Returns the protocol fee collector address
    function protocolFeeCollector() external view returns (address);

    /// @notice Returns the hook fee collector address
    function hookFeeCollector() external view returns (address);

    /// @notice Returns true if a hook was deployed by this factory
    function isDeployedByFactory(address hook) external view returns (bool);
}

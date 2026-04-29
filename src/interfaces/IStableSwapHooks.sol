// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @notice Canonical interface for StableSwapHooks state queried by periphery contracts.
interface IStableSwapHooks {
    function currencies(uint256 index) external view returns (Currency);
    function currenciesLength() external view returns (uint256);
    function reserves(uint256 index) external view returns (uint256);
    function rates(uint256 index) external view returns (uint256);
    function rateOracles(uint256 index) external view returns (address oracle, bytes4 selector);
    function lpFeePercentage() external view returns (uint256);
    function hookFeePercentage() external view returns (uint256);
    function protocolFeePercentage() external view returns (uint256);
    function getCurrentAmp() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function TICK_SPACING() external view returns (int24);
    function addLiquidity(uint256[] calldata amounts, uint256[] calldata minAmounts, uint256 minShares) external;
    function quoteAddLiquidity(uint256[] calldata amounts)
        external
        view
        returns (uint256 shares, uint256[] memory actualAmounts);
}

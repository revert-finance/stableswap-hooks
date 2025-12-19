// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapHooks} from "src/StableSwapHooks.sol";

contract StableSwapHooksHarness is StableSwapHooks {
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
        StableSwapHooks(
            _poolManager,
            _currencies,
            _rateOracles,
            _protocolFeeCollector,
            _protocolFeePercentage,
            _hookFeePercentage,
            _lpFeePercentage,
            _baseAmp
        )
    {}

    // Amp.sol

    function currentAmp() external view returns (uint256) {
        return _currentAmp();
    }

    // Fees.sol

    function getFees(uint256 _amount) external view returns (uint256 lpFees, uint256 hookFees, uint256 protocolFees) {
        return _getFees(_amount);
    }

    // Liquidity.sol

    function computeNewShares(uint256[] memory _amounts) external view returns (uint256) {
        return _computeNewShares(_amounts);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapHooks} from "src/StableSwapHooks.sol";

contract StableSwapHooksHarness is StableSwapHooks {
    constructor(
        IPoolManager _poolManager,
        Currency _currency0,
        Currency _currency1,
        address _protocolFeeCollector,
        uint256 _protocolFeePercentage,
        uint256 _hookFeePercentage,
        uint256 _lpFeePercentage,
        uint256 _baseAmp
    )
        StableSwapHooks(
            _poolManager,
            _currency0,
            _currency1,
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

    function handleWithdrawProtocolFeesCallback() external {
        _handleWithdrawProtocolFeesCallback();
    }

    function handleWithdrawHookFeesCallback(bytes memory data) external {
        _handleWithdrawHookFeesCallback(data);
    }

    function getFees(uint256 _amount) external view returns (uint256 lpFees, uint256 hookFees, uint256 protocolFees) {
        return _getFees(_amount);
    }

    function addFees(bool _isCurrency0, uint256 _protocolFees, uint256 _hookFees) external {
        _addFees(_isCurrency0, _protocolFees, _hookFees);
    }
}

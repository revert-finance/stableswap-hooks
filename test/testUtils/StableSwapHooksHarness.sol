// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {StableSwapHooks} from "src/StableSwapHooks.sol";

contract StableSwapHooksHarness is StableSwapHooks {
    constructor(
        uint256 _initialA,
        IPoolManager _poolManager,
        Currency _currency0,
        Currency _currency1,
        address _protocolFeeCollector,
        uint256 _protocolFeePercentage,
        uint256 _hookFeePercentage,
        uint256 _lpFeePercentage
    )
        StableSwapHooks(
            _initialA,
            _poolManager,
            _currency0,
            _currency1,
            _protocolFeeCollector,
            _protocolFeePercentage,
            _hookFeePercentage,
            _lpFeePercentage
        )
    {}
}

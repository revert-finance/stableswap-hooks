// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";

import {Actions} from "src/libraries/Actions.sol";
import {Base} from "src/Base.sol";
import {Amp} from "src/Amp.sol";
import {Fees} from "src/Fees.sol";
import {Swap} from "src/Swap.sol";

contract StableSwapHooks is IUnlockCallback, Swap {
    error InvalidAction();

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
        Base(_poolManager, _currency0, _currency1, _lpFeePercentage)
        Amp(_baseAmp)
        Fees(_protocolFeeCollector, _protocolFeePercentage, _hookFeePercentage, _lpFeePercentage)
    {}

    /// @notice Callback function for the pool manager
    /// @param data The data passed to the unlock function
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        uint256 action = abi.decode(data, (uint256));

        if (action == Actions.ADD_LIQUIDITY) {
            _handleAddLiquidityCallback(data);
        } else if (action == Actions.REMOVE_LIQUIDITY) {
            _handleRemoveLiquidityCallback(data);
        } else if (action == Actions.WITHDRAW_PROTOCOL_FEES) {
            _handleWithdrawProtocolFeesCallback();
        } else if (action == Actions.WITHDRAW_HOOK_FEES) {
            _handleWithdrawHookFeesCallback(data);
        } else {
            revert InvalidAction();
        }

        return "";
    }
}

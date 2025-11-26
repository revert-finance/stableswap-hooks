// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {BaseHooks} from "./BaseHooks.sol";

contract StableSwapHooks is BaseHooks {
    using SafeCast for int256;

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external pure override returns (bytes4, BeforeSwapDelta, uint24) {
        BeforeSwapDelta delta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), 0);

        return (StableSwapHooks.beforeSwap.selector, delta, 0);
    }
}

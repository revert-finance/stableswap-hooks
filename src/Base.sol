// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";

abstract contract Base is BaseHook {
    Currency public currency0;
    Currency public currency1;

    constructor(address _currency0, address _currency1) {
        currency0 = Currency.wrap(_currency0);
        currency1 = Currency.wrap(_currency1);
    }
}

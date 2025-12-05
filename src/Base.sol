// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";

abstract contract Base is BaseHook {
    Currency public immutable currency0;
    Currency public immutable currency1;

    constructor(Currency _currency0, Currency _currency1) {
        currency0 = _currency0;
        currency1 = _currency1;
    }
}

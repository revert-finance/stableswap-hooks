// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";

abstract contract Base is BaseHook, AccessControlEnumerable {
    Currency public immutable currency0;
    Currency public immutable currency1;

    constructor(IPoolManager _poolManager, Currency _currency0, Currency _currency1) BaseHook(_poolManager) {
        currency0 = _currency0;
        currency1 = _currency1;
    }
}

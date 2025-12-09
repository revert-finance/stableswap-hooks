// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";

import {StableSwapMath} from "src/libraries/StableSwapMath.sol";

abstract contract Base is BaseHook, AccessControlEnumerable {
    int24 public constant TICK_SPACING = 1;

    PoolId public immutable poolId;

    Currency public immutable currency0;
    Currency public immutable currency1;

    uint256 public immutable rate0;
    uint256 public immutable rate1;

    uint256 public reserves0;
    uint256 public reserves1;

    constructor(IPoolManager _poolManager, Currency _currency0, Currency _currency1, uint256 _lpFeePercentage)
        BaseHook(_poolManager)
    {
        currency0 = _currency0;
        currency1 = _currency1;

        PoolKey memory poolKey = PoolKey({
            currency0: _currency0,
            currency1: _currency1,
            fee: uint24(_lpFeePercentage),
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(this))
        });

        poolId = poolKey.toId();

        rate0 = StableSwapMath.getRate(_currency0);
        rate1 = StableSwapMath.getRate(_currency1);

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
}

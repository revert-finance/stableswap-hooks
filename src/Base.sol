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

/// @notice Abstract base contract for StableSwap hooks providing core state and configuration
abstract contract Base is BaseHook, AccessControlEnumerable {
    /// @notice Fixed tick spacing used for the pool
    /// @dev We are not using concentrated liquidity so this value is just to form the pool key
    int24 public constant TICK_SPACING = 1;

    /// @notice Unique identifier for the pool using the hook
    PoolId public immutable poolId;

    /// @notice The first currency in the pool pair
    Currency public immutable currency0;

    /// @notice The second currency in the pool pair
    Currency public immutable currency1;

    /// @notice Scaling rate for currency0 to normalize to 1e18 precision
    /// @dev Calculated as 10^(36 - decimals) to handle tokens with different decimal places
    uint256 public immutable rate0;

    /// @notice Scaling rate for currency1 to normalize to 1e18 precision
    /// @dev Calculated as 10^(36 - decimals) to handle tokens with different decimal places
    uint256 public immutable rate1;

    /// @notice Current reserves of currency0 held by the pool
    uint256 public reserves0;

    /// @notice Current reserves of currency1 held by the pool
    uint256 public reserves1;

    /// @notice Initializes the base StableSwap hook configuration
    /// @dev Grants DEFAULT_ADMIN_ROLE to the deployer
    /// @param _poolManager The Uniswap v4 PoolManager contract
    /// @param _currency0 The first currency in the pair (must be < currency1)
    /// @param _currency1 The second currency in the pair
    /// @param _lpFeePercentage The LP fee percentage encoded in the pool key fee field
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

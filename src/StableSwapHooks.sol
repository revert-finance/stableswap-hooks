// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {BaseHooks} from "./BaseHooks.sol";

contract StableSwapHooks is BaseHooks {
    using SafeCast for int256;
    using SafeCast for uint256;

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        int128 dy = swap(sender, key, params);
        BeforeSwapDelta delta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), dy);

        return (StableSwapHooks.beforeSwap.selector, delta, 0);
    }

    function swap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata params)
        private
        returns (int128)
    {
        // rates
        uint256 rate0 = 10 ** 30; // 6 decimals
        uint256 rate1 = 10 ** 18; // 18 decimals

        // old balances
        uint256 balance0 = 70 * (10 ** 6);
        uint256 balance1 = 30 * (10 ** 18);

        // xp_mem
        uint256 xp0 = rate0 * balance0 / 1e18;
        uint256 xp1 = rate1 * balance1 / 1e18;

        // dx should be calculated?
        int256 dx = params.amountSpecified;
        if (dx >= 0) {
            // zeroForOne not used.
            revert();
        }

        uint256 x = xp0 + uint256(-dx) * rate0 / 1e18;

        uint256 amp = 1e3;

        uint256 D = getD(xp0, xp1, amp);
        uint256 y = getY(x, amp, D);
        uint256 dy = xp1 - y - 1;
        uint256 dy_fee = 0; // TODO

        // Convert all to real units
        dy = (dy - dy_fee) * 1e18 / rate1;

        // TODO
        // self.upkeep_oracles(xp, amp, D)

        // TODO
        // Check dy against amount * sqrtPrice => min to receive
        return dy.toInt128();
    }

    function getD(uint256 xp0, uint256 xp1, uint256 amp) private pure returns (uint256) {
        uint256 S = xp0 + xp1;

        uint256 D = S;
        uint256 Ann = amp * 2;

        for (uint256 i = 0; i < 255; ++i) {
            uint256 D_P = D;

            D_P = D_P * D / xp0;
            D_P = D_P * D / xp1;

            D_P = D_P / 4;

            uint256 D_prev = D;

            // (Ann * S / A_PRECISION + D_P * N_COINS) * D / ((Ann - A_PRECISION) * D / A_PRECISION + (N_COINS + 1) * D_P)
            D = (Ann * S / 100 + D_P * 2) * D / ((Ann - 100) * D / 100 + (2 + 1) * D_P);

            if (D > D_prev) {
                if (D - D_prev <= 1) {
                    return D;
                }
            } else {
                if (D - D_prev <= 1) {
                    return D;
                }
            }
        }

        revert("Convergence not reached");
    }

    function getY(uint256 x, uint256 amp, uint256 D) private pure returns (uint256) {
        uint256 S_ = x;
        uint256 y_prev = 0;
        uint256 c = D * (D / (x * 2));
        uint256 Ann = amp * 2;

        // c = c * D * A_PRECISION / (Ann * N_COINS)
        c = c * D * 100 / (Ann * 2);

        // b: uint256 = S_ + D * A_PRECISION / Ann  # - D
        uint256 b = S_ + D * 100 / Ann;

        // y: uint256 = D
        uint256 y = D;

        for (uint256 i = 0; i < 255; ++i) {
            y_prev = y;
            y = (y * y + c) / (2 * y + b - D);

            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                }
            } else {
                if (y - y_prev <= 1) {
                    return y;
                }
            }
        }

        revert("Convergence not reached (y)");
    }
}

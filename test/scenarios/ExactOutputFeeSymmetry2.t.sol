// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";
import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

/**
 * @title Regression: Skewed exact-output fee symmetry (STAB-21)
 * @notice Recreates the finding's skewed 2-token pool on the live swap path, then compares the input
 * required by exact-input and exact-output for the same net USDC output from the same pre-trade state.
 * Before the fix exact-output was ~25.9% cheaper (518,555 DAI gap on a 2,000,000 DAI trade) because it
 * solved the curve only to the net output and grossed up the input linearly. With the fee realized on
 * the output side in both modes, the gap must collapse to rounding dust.
 */
contract ExactOutputFeeSymmetry2Test is StableSwapHooksBaseTest {
    uint256 private constant LP_FEE = 3000; // 0.30%
    uint256 private constant EXACT_INPUT_AMOUNT = 2_000_000e18;

    function test_exactOutput_costsSameAsExactInputAfterReachableSkew() public {
        // Pool setup: 0.30% LP fee, protocol/hook splits zeroed so the full fee stays in reserves.
        // Seeded balanced: 1,000,000 DAI (18dp) / 1,000,000 USDC (6dp).
        StableSwapHooks customHooks = _deployHooksWithLpFee(LP_FEE);
        _setFeeSplits(customHooks, 0, 0);
        _seedHooks(customHooks);

        // Step 1 - skew the pool with one big exact-input trade: 500,000 DAI in.
        // Swapper receives 495,262.444390 USDC (net of fee).
        // Reserves move 1,000,000 / 1,000,000  ->  1,500,000 DAI / 504,737.555610 USDC.
        _exactInputSwap(customHooks, _toTokenWei(currency0, 500_000));

        uint256 reserve0 = customHooks.reserves(0);
        uint256 reserve1 = customHooks.reserves(1);

        console.log("skewed reserves after 500k DAI in");
        console.log("reserve0:", reserve0);
        console.log("reserve1:", reserve1);

        assertEq(reserve0, 1_500_000e18, "reachable skewed DAI reserve mismatch");
        assertEq(reserve1, 504_737_555_610, "reachable skewed USDC reserve mismatch");

        deal(Currency.unwrap(currency0), swapper, _toTokenWei(currency0, 10_000_000));

        // Both legs below start from this same skewed snapshot.
        uint256 snapshot = vm.snapshotState();

        // Step 2 - exact input: 2,000,000 DAI in  ->  501,333.100410 USDC out.
        // Fee is realized on the OUTPUT side: the curve must give up the gross output
        // ~502,841.62 USDC (net / 0.997), i.e. traverse down to ~1,895.93 USDC on-curve,
        // then the ~1,508.53 USDC fee is added back to reserves. Pool ends at 3,404.455200 USDC.
        // Those last gross units come from the near-empty tail where marginal price explodes.
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        _exactInputSwap(customHooks, EXACT_INPUT_AMOUNT);
        uint256 amountOut = IERC20(Currency.unwrap(currency1)).balanceOf(swapper) - balance1Before;
        console.log("exact input amountOut:", amountOut);
        assertEq(amountOut, 501_333_100_410, "candidate exact-input output mismatch");

        vm.revertToState(snapshot);

        // Step 3 - exact output for the SAME 501,333.100410 USDC.
        // Fee is now realized on the OUTPUT side here too: the requested output is grossed up to
        // ~502,841.62 USDC before the curve solve, so the curve traverses to the same ~1,895.93 USDC
        // depth as exact input and the required DAI matches step 2 up to rounding dust.
        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        _exactOutputSwap(customHooks, amountOut);
        uint256 amountInForSameOutput = balance0Before - IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        console.log("exact output amountIn for same output:", amountInForSameOutput);

        // Same output, same price up to dust (pre-fix the difference was 518,555.06 DAI):
        //   exact input:  2,000,000.000000... DAI
        //   exact output: 1,999,999.999610... DAI
        assertApproxEqAbs(
            amountInForSameOutput,
            EXACT_INPUT_AMOUNT,
            1e15,
            "exact output must cost the same input as exact input in the skewed state"
        );
    }

    function _deployHooksWithLpFee(uint256 _lpFeePercentage) private returns (StableSwapHooks) {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, _lpFeePercentage, BASE_AMP, code);

        return StableSwapHooks(factory.deploy(currencies, rateOracles, _lpFeePercentage, BASE_AMP, salt, code));
    }

    function _setFeeSplits(StableSwapHooks _hooks, uint256 _protocolFee, uint256 _hookFee) private {
        vm.startPrank(defaultAdmin);
        _hooks.setProtocolFeePercentage(_protocolFee);
        _hooks.setHookFeePercentage(_hookFee);
        vm.stopPrank();
    }

    function _seedHooks(StableSwapHooks _hooks) private {
        deal(Currency.unwrap(currency0), liquidityProvider, _toTokenWei(currency0, 2_000_000));
        deal(Currency.unwrap(currency1), liquidityProvider, _toTokenWei(currency1, 2_000_000));
        deal(Currency.unwrap(currency0), swapper, _toTokenWei(currency0, 2_000_000));

        vm.startPrank(liquidityProvider);
        IERC20(Currency.unwrap(currency0)).approve(address(_hooks), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(_hooks), type(uint256).max);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 1_000_000);
        amounts[1] = _toTokenWei(currency1, 1_000_000);
        _hooks.addLiquidity(amounts, new uint256[](2), 0);
        vm.stopPrank();
    }

    function _exactInputSwap(StableSwapHooks _hooks, uint256 _amountIn) private {
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: _tierPoolKey(_hooks),
                zeroForOne: true,
                amountIn: uint128(_amountIn),
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(currency0, _amountIn);
        params[2] = abi.encode(currency1, 0);

        _execute(actions, params);
    }

    function _exactOutputSwap(StableSwapHooks _hooks, uint256 _amountOut) private {
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: _tierPoolKey(_hooks),
                zeroForOne: true,
                amountOut: uint128(_amountOut),
                amountInMaximum: type(uint128).max,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(currency0, type(uint128).max);
        params[2] = abi.encode(currency1, _amountOut);

        _execute(actions, params);
    }

    function _execute(bytes memory _actions, bytes[] memory _params) private {
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(_actions, _params);

        vm.prank(swapper);
        universalRouter.execute(commands, inputs, block.timestamp + 100);
    }

    function _tierPoolKey(StableSwapHooks _hooks) private view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(_hooks.lpFeePercentage()),
            tickSpacing: _hooks.TICK_SPACING(),
            hooks: IHooks(address(_hooks))
        });
    }
}

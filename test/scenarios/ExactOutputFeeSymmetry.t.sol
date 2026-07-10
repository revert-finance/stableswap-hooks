// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Vm} from "forge-std/Vm.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";
import {StableSwapHooksBaseTest} from "test/testUtils/StableSwapHooksBaseTest.sol";

contract ExactOutputFeeSymmetryTest is StableSwapHooksBaseTest {
    bytes32 internal constant STABLE_SWAP_TOPIC =
        keccak256("StableSwap(address,address,address,uint256,uint256,uint256,uint256,uint256)");

    function setUp() public override {
        super.setUp();

        _addLiquidity(1_000_000, 1_000_000);
    }

    function test_exactOutput_collectsTheFullGrossLpFeeOnTotalInput() public {
        vm.recordLogs();
        _executeExactOutputSwap(true, _toTokenWei(currency1, 1000));

        (uint256 amountIn, uint256 totalFees) = _readSwapFees();

        uint256 grossLpFee = Math.mulDiv(amountIn, hooks.lpFeePercentage(), hooks.FEE_PRECISION(), Math.Rounding.Ceil);

        assertEq(totalFees, grossLpFee, "exact output must charge the full gross lp fee on the total input paid");
    }

    function test_exactOutput_minimumOutput_stillCollectsTheGrossLpFee() public {
        vm.recordLogs();
        _executeExactOutputSwap(true, 1);

        (uint256 amountIn, uint256 totalFees) = _readSwapFees();

        uint256 grossLpFee = Math.mulDiv(amountIn, hooks.lpFeePercentage(), hooks.FEE_PRECISION(), Math.Rounding.Ceil);

        assertEq(
            totalFees, grossLpFee, "minimum exact output must charge the full gross lp fee on the total input paid"
        );
    }

    function test_exactInputAndExactOutput_costGapIsNegligible_500() public {
        _assertCostGapForFeeTier(500);
    }

    function test_exactInputAndExactOutput_costGapIsNegligible_3000() public {
        _assertCostGapForFeeTier(3000);
    }

    function test_exactInputAndExactOutput_costGapIsNegligible_10000() public {
        _assertCostGapForFeeTier(10000);
    }

    function test_exactInputAndExactOutput_costGapIsNegligible_100000() public {
        _assertCostGapForFeeTier(100000);
    }

    function test_exactInputAndExactOutput_costGapIsNegligible_500000() public {
        _assertCostGapForFeeTier(500000);
    }

    // Both paths now charge the full fee, so the pool is not shortchanged. A tiny difference is left
    // because the fee sits on the input token one way and the output token the other, making exact
    // output a hair cheaper: about $0.005 on a $1M swap at 0.05% fee. That is too small to be worth
    // exploiting (a swap costs more in gas), and it grows with the fee, so the allowed difference is
    // sized per fee tier with 2x room to spare.
    function _assertCostGapForFeeTier(uint256 _feeTier) private {
        StableSwapHooks tierHooks = _deployHooksWithLpFee(_feeTier);
        _seedHooks(tierHooks);

        uint256 amountIn = _toTokenWei(currency0, 1000);

        uint256 snapshot = vm.snapshotState();
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(swapper);
        _exactInputSwap(tierHooks, amountIn);
        uint256 amountOut = IERC20(Currency.unwrap(currency1)).balanceOf(swapper) - balance1Before;
        vm.revertToState(snapshot);

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        _exactOutputSwap(tierHooks, amountOut);
        uint256 amountInForSameOutput = balance0Before - IERC20(Currency.unwrap(currency0)).balanceOf(swapper);

        assertApproxEqRel(
            amountInForSameOutput,
            amountIn,
            _feeTier * 2e7,
            "exact output cost must match exact input within rounding across fee tiers"
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

    function _readSwapFees() internal returns (uint256 amountIn, uint256 totalFees) {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == STABLE_SWAP_TOPIC && logs[i].emitter == address(hooks)) {
                (uint256 swapAmountIn,, uint256 lpFees, uint256 hookFees, uint256 protocolFees) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, uint256));
                return (swapAmountIn, lpFees + hookFees + protocolFees);
            }
        }

        revert("StableSwap event not found");
    }
}

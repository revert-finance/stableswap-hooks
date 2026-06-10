// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

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

contract ExactOutputMaxFeeTest is StableSwapHooksBaseTest {
    StableSwapHooks internal maxFeeHooks;

    function setUp() public override {
        super.setUp();

        maxFeeHooks = _deployMaxFeeHooks();
        _seedMaxFeeHooks();
    }

    function test_exactOutput_maxLpFee_revertsOnGrossUpDivisionByZero() public {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(maxFeeHooks.FEE_PRECISION()),
            tickSpacing: maxFeeHooks.TICK_SPACING(),
            hooks: IHooks(address(maxFeeHooks))
        });

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: poolKey,
                zeroForOne: true,
                amountOut: uint128(_toTokenWei(currency1, 1000)),
                amountInMaximum: type(uint128).max,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(currency0, type(uint128).max);
        params[2] = abi.encode(currency1, _toTokenWei(currency1, 1000));

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.prank(swapper);
        vm.expectRevert();
        universalRouter.execute(commands, inputs, block.timestamp + 100);
    }

    function _deployMaxFeeHooks() private returns (StableSwapHooks) {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        uint256 maxFee = hooks.FEE_PRECISION();

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, maxFee, BASE_AMP, code);

        return StableSwapHooks(factory.deploy(currencies, rateOracles, maxFee, BASE_AMP, salt, code));
    }

    function _seedMaxFeeHooks() private {
        vm.startPrank(liquidityProvider);
        IERC20(Currency.unwrap(currency0)).approve(address(maxFeeHooks), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(maxFeeHooks), type(uint256).max);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _toTokenWei(currency0, 1_000_000);
        amounts[1] = _toTokenWei(currency1, 1_000_000);
        maxFeeHooks.addLiquidity(amounts, new uint256[](2), 0);
        vm.stopPrank();
    }
}

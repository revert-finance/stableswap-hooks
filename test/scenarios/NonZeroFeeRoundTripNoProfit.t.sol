// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactoryHarness} from "test/testUtils/StableSwapHooksFactoryHarness.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {MockERC20} from "test/scenarios/mocks/MockERC20.sol";

contract NonZeroFeeRoundTripNoProfitTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 internal constant MIN_LP_FEE = 1;
    uint256 internal constant BASE_AMP = 10_000;
    uint256 internal constant RESERVE = 1 ether;
    uint256 internal constant ATTACK_AMOUNT = RESERVE * 5_000_000;

    StableSwapHooksFactoryHarness internal factory;
    StableSwapHooks internal hooks;
    MockERC20 internal token0;
    MockERC20 internal token1;
    Currency internal currencyA;
    Currency internal currencyB;

    address internal lp = makeAddr("lp");

    function setUp() public override {
        super.setUp();
        vm.warp(1731337000);

        MockERC20 a = new MockERC20("Token A", "TKNA", 18);
        MockERC20 b = new MockERC20("Token B", "TKNB", 18);

        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);

        currencyA = Currency.wrap(address(token0));
        currencyB = Currency.wrap(address(token1));

        factory = new StableSwapHooksFactoryHarness(
            IPoolManager(poolManager),
            makeAddr("admin"),
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );

        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currencyA;
        currencies[1] = currencyB;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, MIN_LP_FEE, BASE_AMP, code);
        hooks = StableSwapHooks(factory.deploy(currencies, rateOracles, MIN_LP_FEE, BASE_AMP, salt, code));

        token0.mint(lp, RESERVE);
        token1.mint(lp, RESERVE);

        vm.startPrank(lp);
        token0.approve(address(hooks), RESERVE);
        token1.approve(address(hooks), RESERVE);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = RESERVE;
        amounts[1] = RESERVE;
        hooks.addLiquidity(amounts, new uint256[](2), 0);
        vm.stopPrank();
    }

    function test_minNonZeroFeeRoundTripCannotExtractReserves() public {
        RoundTripSwapper attacker = new RoundTripSwapper(IPoolManager(poolManager), hooks, token0, token1);
        token1.mint(address(attacker), ATTACK_AMOUNT);

        uint256 attackerBefore = token1.balanceOf(address(attacker));
        uint256 reserve0Before = hooks.reserves(0);
        uint256 reserve1Before = hooks.reserves(1);

        attacker.swapOneForZeroThenBack(ATTACK_AMOUNT);

        uint256 attackerAfter = token1.balanceOf(address(attacker));
        uint256 reserve0After = hooks.reserves(0);
        uint256 reserve1After = hooks.reserves(1);

        assertLe(attackerAfter, attackerBefore, "round trip must not be profitable with a non-zero fee");
        assertGe(reserve0After, reserve0Before, "intermediate token reserve must not decrease");
        assertGe(reserve1After, reserve1Before, "starting token reserve must not be drained");
    }
}

contract RoundTripSwapper is IUnlockCallback {
    using SafeERC20 for IERC20;

    IPoolManager public immutable poolManager;
    StableSwapHooks public immutable hooks;
    MockERC20 public immutable token0;
    MockERC20 public immutable token1;
    Currency public immutable currency0;
    Currency public immutable currency1;

    constructor(IPoolManager _poolManager, StableSwapHooks _hooks, MockERC20 _token0, MockERC20 _token1) {
        poolManager = _poolManager;
        hooks = _hooks;
        token0 = _token0;
        token1 = _token1;
        currency0 = Currency.wrap(address(_token0));
        currency1 = Currency.wrap(address(_token1));
    }

    function swapOneForZeroThenBack(uint256 amountIn) external {
        poolManager.unlock(abi.encode(amountIn));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "not pool manager");

        uint256 amountIn = abi.decode(data, (uint256));
        uint256 token0Out = _swap(false, amountIn);
        _swap(true, token0Out);

        return "";
    }

    function _swap(bool zeroForOne, uint256 amountIn) internal returns (uint256 amountOut) {
        BalanceDelta delta = poolManager.swap(
            PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: uint24(hooks.lpFeePercentage()),
                tickSpacing: hooks.TICK_SPACING(),
                hooks: IHooks(address(hooks))
            }),
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            ""
        );

        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();

        if (delta0 < 0) {
            poolManager.sync(currency0);
            IERC20(address(token0)).safeTransfer(address(poolManager), uint128(-delta0));
            poolManager.settle();
        } else if (delta0 > 0) {
            amountOut = uint128(delta0);
            poolManager.take(currency0, address(this), amountOut);
        }

        if (delta1 < 0) {
            poolManager.sync(currency1);
            IERC20(address(token1)).safeTransfer(address(poolManager), uint128(-delta1));
            poolManager.settle();
        } else if (delta1 > 0) {
            amountOut = uint128(delta1);
            poolManager.take(currency1, address(this), amountOut);
        }
    }
}

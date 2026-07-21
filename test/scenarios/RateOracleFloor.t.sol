// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
import {StableSwapHooksFactoryHarness} from "test/testUtils/StableSwapHooksFactoryHarness.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {Commands} from "test/testUtils/external/libraries/Commands.sol";
import {MockERC20} from "test/scenarios/mocks/MockERC20.sol";
import {MockRateOracle} from "test/scenarios/mocks/MockRateOracle.sol";

/// @notice Regression tests for STAB-43: effective rate oracle floor at 1e18
contract RateOracleFloorTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 private constant LP_FEE_PERCENTAGE = 300;
    uint256 private constant AMP = 100;
    uint256 private constant SEED = 1_000_000e18;
    uint256 private constant SWAP_IN = 1_000e18;

    StableSwapHooksFactoryHarness private factory;

    MockERC20 private token0;
    MockERC20 private token1;
    MockRateOracle private oracle;

    Currency private currency0_;
    Currency private currency1_;
    uint256 private oracleIndex;

    address private owner;
    address private lp;
    address private swapper;

    function setUp() public override {
        super.setUp();

        owner = makeAddr("owner");
        lp = makeAddr("lp");
        swapper = makeAddr("swapper");

        factory = new StableSwapHooksFactoryHarness(
            IPoolManager(poolManager),
            owner,
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );

        MockERC20 tokenA = new MockERC20("Token A", "TKA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKB", 18);
        (token0, token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);
        currency0_ = Currency.wrap(address(token0));
        currency1_ = Currency.wrap(address(token1));

        oracle = new MockRateOracle(1e18);
        oracleIndex = 1; // oracle is attached to currency1

        token0.mint(lp, SEED * 10);
        token1.mint(lp, SEED * 10);
        token0.mint(swapper, SEED);
        token1.mint(swapper, SEED);

        vm.startPrank(lp);
        IERC20(address(token0)).forceApprove(address(this), type(uint256).max);
        IERC20(address(token1)).forceApprove(address(this), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper);
        IERC20(address(token0)).forceApprove(address(permit2), type(uint256).max);
        IERC20(address(token1)).forceApprove(address(permit2), type(uint256).max);
        permit2.approve(address(token0), address(universalRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function test_poolWithSubFloorOracleCannotBeSeeded() public {
        oracle.setRate(100); // effective rate 100 << 1e18

        StableSwapHooks hooks = _deployPool();

        vm.startPrank(lp);
        IERC20(address(token0)).forceApprove(address(hooks), type(uint256).max);
        IERC20(address(token1)).forceApprove(address(hooks), type(uint256).max);
        vm.expectRevert(Base.InvalidRateOracleRate.selector);
        hooks.addLiquidity(_amounts(SEED, SEED), new uint256[](2), 0);
        vm.stopPrank();
    }

    function test_swapsAndAddsRevertWhenOracleDegradesBelowFloor_removeStillWorks() public {
        StableSwapHooks hooks = _deployPool();
        _seed(hooks);

        // healthy: swap succeeds at the 1e18 boundary rate
        PoolKey memory poolKey = _poolKeyFor(hooks);
        _executeExactInputSwap(poolKey, true, SWAP_IN);

        // oracle honestly degrades below the floor after deployment
        oracle.setRate(9e17);

        // swaps fail closed (wrapped by v4 hook call)
        vm.expectRevert(_wrappedSwapRevert(hooks, abi.encodeWithSelector(Base.InvalidRateOracleRate.selector)));
        _executeExactInputSwap(poolKey, true, SWAP_IN);

        // further adds fail closed too (raw revert through unlock callback)
        vm.startPrank(lp);
        vm.expectRevert(Base.InvalidRateOracleRate.selector);
        hooks.addLiquidity(_amounts(SEED, SEED), new uint256[](2), 0);
        vm.stopPrank();

        // LPs can still exit proportionally: removeLiquidity never consults rates
        uint256 shares = hooks.balanceOf(lp);
        uint256 bal0Before = token0.balanceOf(lp);
        uint256 bal1Before = token1.balanceOf(lp);

        vm.prank(lp);
        hooks.removeLiquidity(shares, new uint256[](2));

        assertGt(token0.balanceOf(lp), bal0Before, "LP withdrew token0 despite tripped floor");
        assertGt(token1.balanceOf(lp), bal1Before, "LP withdrew token1 despite tripped floor");
    }

    function test_boundaryRateExactly1e18_staysHealthy() public {
        StableSwapHooks hooks = _deployPool();
        _seed(hooks);

        PoolKey memory poolKey = _poolKeyFor(hooks);

        oracle.setRate(1e18);
        _executeExactInputSwap(poolKey, true, SWAP_IN);

        oracle.setRate(1e18 + 1);
        _executeExactInputSwap(poolKey, false, SWAP_IN);
    }

    function _deployPool() private returns (StableSwapHooks hooks) {
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0_;
        currencies[1] = currency1_;

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(oracle), selector: MockRateOracle.getRate.selector});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, code);
        hooks = StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE_PERCENTAGE, AMP, salt, code));
    }

    function _seed(StableSwapHooks hooks) private {
        vm.startPrank(lp);
        IERC20(address(token0)).forceApprove(address(hooks), type(uint256).max);
        IERC20(address(token1)).forceApprove(address(hooks), type(uint256).max);
        hooks.addLiquidity(_amounts(SEED, SEED), new uint256[](2), 0);
        vm.stopPrank();
    }

    function _amounts(uint256 amount0, uint256 amount1) private pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;
    }

    function _poolKeyFor(StableSwapHooks hooks) private view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0_,
            currency1: currency1_,
            fee: uint24(LP_FEE_PERCENTAGE),
            tickSpacing: hooks.TICK_SPACING(),
            hooks: IHooks(address(hooks))
        });
    }

    function _executeExactInputSwap(PoolKey memory poolKey, bool zeroForOne, uint256 amountIn) private {
        Currency inputCurrency = zeroForOne ? currency0_ : currency1_;
        Currency outputCurrency = zeroForOne ? currency1_ : currency0_;

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountIn: uint128(amountIn),
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(inputCurrency, amountIn);
        params[2] = abi.encode(outputCurrency, 0);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.prank(swapper);
        universalRouter.execute(commands, inputs, block.timestamp + 100);
    }

    function _wrappedSwapRevert(StableSwapHooks hooks, bytes memory innerError) private pure returns (bytes memory) {
        return abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            address(hooks),
            IHooks.beforeSwap.selector,
            innerError,
            abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        );
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Base} from "src/Base.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapHooksFactoryHarness} from "test/testUtils/StableSwapHooksFactoryHarness.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";

contract AddLiquidityReentrancy is ExternalContractsDeployer {
    uint256 internal constant LP_FEE_PERCENTAGE = 300;
    uint256 internal constant AMP = 100;
    uint256 internal constant INITIAL_LIQUIDITY = 1_000_000 ether;
    uint256 internal constant ATTACKER_DEPOSIT = 100_000 ether;
    uint256 internal constant ATTACK_SWAP_IN = 100_000 ether;

    StableSwapHooksFactoryHarness internal factory;
    StableSwapHooks internal hooks;
    ReentrantAddLiquidityToken internal token;

    Currency internal nativeEth;
    Currency internal tokenCurrency;

    address internal honestLp;
    address internal attackerLp;

    function setUp() public override {
        super.setUp();

        nativeEth = Currency.wrap(address(0));
        honestLp = makeAddr("honestLp");
        attackerLp = makeAddr("attackerLp");

        token = new ReentrantAddLiquidityToken(IPoolManager(poolManager));
        tokenCurrency = Currency.wrap(address(token));

        factory = new StableSwapHooksFactoryHarness(
            IPoolManager(poolManager),
            makeAddr("admin"),
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );

        hooks = _deployHooks();
        token.configure(hooks, _poolKey());

        vm.deal(honestLp, INITIAL_LIQUIDITY);
        vm.deal(attackerLp, ATTACKER_DEPOSIT);

        token.mint(honestLp, INITIAL_LIQUIDITY);
        token.mint(attackerLp, ATTACKER_DEPOSIT);
        token.mint(address(token), ATTACK_SWAP_IN * 2);

        vm.startPrank(honestLp);
        token.approve(address(hooks), type(uint256).max);
        hooks.addLiquidity{value: INITIAL_LIQUIDITY}(
            _amounts(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY), new uint256[](2), 0
        );
        vm.stopPrank();

        vm.prank(attackerLp);
        token.approve(address(hooks), type(uint256).max);
    }

    function test_reentrantSwapDuringAddLiquiditySeesCommittedReservesAndGetsNoAdvantage() external {
        uint256 snapshot = vm.snapshotState();

        token.configureAttack(ATTACK_SWAP_IN, true);

        uint256 attackEthBefore = address(token).balance;

        vm.prank(attackerLp);
        hooks.addLiquidity{value: ATTACKER_DEPOSIT}(_amounts(ATTACKER_DEPOSIT, ATTACKER_DEPOSIT), new uint256[](2), 0);

        uint256 attackEthOut = address(token).balance - attackEthBefore;

        assertGt(hooks.balanceOf(attackerLp), 0, "outer addLiquidity should still complete");
        assertEq(
            token.observedEthReserve(),
            INITIAL_LIQUIDITY + ATTACKER_DEPOSIT,
            "reentrant swap must see committed ETH reserve"
        );
        assertEq(
            token.observedTokenReserve(),
            INITIAL_LIQUIDITY + ATTACKER_DEPOSIT,
            "reentrant swap must see committed token reserve, not a stale mid-deposit value"
        );

        vm.revertToState(snapshot);

        token.configureAttack(ATTACK_SWAP_IN, false);

        vm.prank(attackerLp);
        hooks.addLiquidity{value: ATTACKER_DEPOSIT}(_amounts(ATTACKER_DEPOSIT, ATTACKER_DEPOSIT), new uint256[](2), 0);

        uint256 controlEthBefore = address(token).balance;
        token.executeStandaloneSwap(ATTACK_SWAP_IN);
        uint256 controlEthOut = address(token).balance - controlEthBefore;

        console2.log("attackEthOut", attackEthOut);
        console2.log("controlEthOut", controlEthOut);

        assertEq(attackEthOut, controlEthOut, "reentrant swap must get the same price as the post-commit swap");
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

contract ReentrantAddLiquidityToken is ERC20, IUnlockCallback {
    IPoolManager internal immutable poolManager;
    StableSwapHooks internal hooks;
    PoolKey internal poolKey;
    Currency internal immutable tokenCurrency;
    Currency internal constant NATIVE_ETH = Currency.wrap(address(0));
    address internal immutable owner;

    bool internal attackEnabled;
    uint256 internal attackAmountIn;

    uint256 public observedEthReserve;
    uint256 public observedTokenReserve;
    uint256 public lastAmountIn;
    uint256 public lastAmountOut;

    constructor(IPoolManager _poolManager) ERC20("Reentrant Token", "RNT") {
        poolManager = _poolManager;
        tokenCurrency = Currency.wrap(address(this));
        owner = msg.sender;
    }

    function configure(StableSwapHooks _hooks, PoolKey memory _poolKey) external {
        hooks = _hooks;
        poolKey = _poolKey;
    }

    function configureAttack(uint256 _attackAmountIn, bool _attackEnabled) external {
        attackAmountIn = _attackAmountIn;
        attackEnabled = _attackEnabled;
    }

    function executeStandaloneSwap(uint256 amountIn) external {
        poolManager.unlock(abi.encode(amountIn));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "not pool manager");

        uint256 amountIn = abi.decode(data, (uint256));
        poolManager.sync(tokenCurrency);
        _performSwap(amountIn);

        return "";
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (!attackEnabled || msg.sender != address(hooks) || to != address(poolManager)) {
            return super.transferFrom(from, to, value);
        }

        attackEnabled = false;
        _spendAllowance(from, msg.sender, value);

        observedEthReserve = hooks.reserves(0);
        observedTokenReserve = hooks.reserves(1);

        _performSwap(attackAmountIn);

        poolManager.sync(tokenCurrency);
        _transfer(from, to, value);

        return true;
    }

    receive() external payable {}

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "not owner");
        _mint(to, amount);
    }

    function _performSwap(uint256 amountIn) internal {
        BalanceDelta delta = poolManager.swap(
            poolKey,
            SwapParams({
                zeroForOne: false, amountSpecified: -int256(amountIn), sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            ""
        );

        lastAmountIn = uint128(-delta.amount1());
        lastAmountOut = uint128(delta.amount0());

        _transfer(address(this), address(poolManager), lastAmountIn);
        poolManager.settleFor(address(this));
        poolManager.take(NATIVE_ETH, address(this), lastAmountOut);
    }
}

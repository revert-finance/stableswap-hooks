// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {Base} from "src/Base.sol";
import {Liquidity} from "src/Liquidity.sol";
import {StableSwapHooks} from "src/StableSwapHooks.sol";
import {StableSwapMath} from "src/libraries/StableSwapMath.sol";
import {StableSwapHooksFactoryHarness} from "test/testUtils/StableSwapHooksFactoryHarness.sol";
import {ExternalContractsDeployer} from "test/testUtils/ExternalContractsDeployer.sol";
import {MockERC20} from "test/scenarios/mocks/MockERC20.sol";

contract ThreeTokenGeometricMeanUnderMintTest is ExternalContractsDeployer {
    using SafeERC20 for IERC20;

    uint256 internal constant LP_FEE = 500;
    uint256 internal constant BASE_AMP = 100;
    uint256 internal constant DEPOSIT_AMOUNT = 2_000;

    StableSwapHooksFactoryHarness internal factory;
    StableSwapHooks internal hooks3;
    MockERC20 internal token0;
    MockERC20 internal token1;
    MockERC20 internal token2;

    address internal lp = makeAddr("lp");

    function setUp() public override {
        super.setUp();

        MockERC20[3] memory tokens = [
            new MockERC20("Token A", "TKNA", 18),
            new MockERC20("Token B", "TKNB", 18),
            new MockERC20("Token C", "TKNC", 18)
        ];

        for (uint256 i = 0; i < tokens.length; ++i) {
            for (uint256 j = i + 1; j < tokens.length; ++j) {
                if (address(tokens[j]) < address(tokens[i])) {
                    (tokens[i], tokens[j]) = (tokens[j], tokens[i]);
                }
            }
        }

        token0 = tokens[0];
        token1 = tokens[1];
        token2 = tokens[2];

        factory = new StableSwapHooksFactoryHarness(
            IPoolManager(poolManager),
            makeAddr("admin"),
            makeAddr("protocolFeeCollector"),
            makeAddr("hookFeeCollector"),
            keccak256(type(StableSwapHooks).creationCode)
        );

        Currency[] memory currencies = new Currency[](3);
        currencies[0] = Currency.wrap(address(token0));
        currencies[1] = Currency.wrap(address(token1));
        currencies[2] = Currency.wrap(address(token2));

        Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](3);
        rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
        rateOracles[2] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

        bytes memory code = type(StableSwapHooks).creationCode;
        (, bytes32 salt) = factory.mineSalt(currencies, rateOracles, LP_FEE, BASE_AMP, code);
        hooks3 = StableSwapHooks(factory.deploy(currencies, rateOracles, LP_FEE, BASE_AMP, salt, code));

        token0.mint(lp, 10_000);
        token1.mint(lp, 10_000);
        token2.mint(lp, 10_000);

        vm.startPrank(lp);
        IERC20(address(token0)).forceApprove(address(hooks3), type(uint256).max);
        IERC20(address(token1)).forceApprove(address(hooks3), type(uint256).max);
        IERC20(address(token2)).forceApprove(address(hooks3), type(uint256).max);
        vm.stopPrank();
    }

    function test_initialDeposit_UnderMintsSharesVersusProductCubeRoot() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = DEPOSIT_AMOUNT;
        amounts[1] = DEPOSIT_AMOUNT;
        amounts[2] = DEPOSIT_AMOUNT;

        uint256 productCubeRootShares =
            StableSwapMath.cbrt(DEPOSIT_AMOUNT * DEPOSIT_AMOUNT * DEPOSIT_AMOUNT) - hooks3.MINIMUM_LIQUIDITY();

        vm.prank(lp);
        hooks3.addLiquidity(amounts, new uint256[](3), 0);

        uint256 actualShares = hooks3.balanceOf(lp);

        assertEq(productCubeRootShares, 1_000, "product cube root entitles lp to 1000 shares");
        assertEq(actualShares, 728, "lp receives 728 shares from triple cbrt flooring");
        assertLt(actualShares, productCubeRootShares, "first lp is under-minted");
    }

    function test_initialDeposit_RevertsForValidAmountsAboveMinimumLiquidity() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 999;
        amounts[1] = 1_330;
        amounts[2] = 1_727;

        uint256 productCubeRoot = StableSwapMath.cbrt(amounts[0] * amounts[1] * amounts[2]);
        assertGt(productCubeRoot, hooks3.MINIMUM_LIQUIDITY(), "correct geometric mean exceeds minimum liquidity");

        vm.prank(lp);
        vm.expectRevert(Liquidity.InsufficientInitialLiquidity.selector);
        hooks3.addLiquidity(amounts, new uint256[](3), 0);
    }

    function test_geometricMean_TripleCbrtFlooringUnderestimatesProductCubeRoot() public pure {
        uint256[] memory values = new uint256[](3);
        values[0] = 7;
        values[1] = 7;
        values[2] = 7;

        assertEq(StableSwapMath.geometricMean(values), 1, "triple cbrt flooring collapses 7 to 1");
        assertEq(StableSwapMath.cbrt(7 * 7 * 7), 7, "product cube root is exact");
    }
}

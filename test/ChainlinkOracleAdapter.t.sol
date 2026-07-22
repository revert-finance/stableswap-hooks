// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {ChainlinkOracleAdapter, AggregatorV3Interface} from "src/oracles/ChainlinkOracleAdapter.sol";

contract MockAggregator is AggregatorV3Interface {
    uint8 public decimals;
    int256 internal answer;
    uint256 internal startedAt;
    uint256 internal updatedAt;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }

    function set(int256 _answer, uint256 _startedAt, uint256 _updatedAt) external {
        answer = _answer;
        startedAt = _startedAt;
        updatedAt = _updatedAt;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, answer, startedAt, updatedAt, 0);
    }
}

contract ChainlinkOracleAdapterTest is Test {
    uint256 internal constant GRACE_PERIOD = 3600;
    uint256 internal constant TOLERANCE = 86400;
    uint256 internal constant NOW = 1_000_000;

    MockAggregator internal priceFeed;
    MockAggregator internal sequencerFeed;
    ChainlinkOracleAdapter internal adapter;

    function setUp() public {
        vm.warp(NOW);

        priceFeed = new MockAggregator(8);
        sequencerFeed = new MockAggregator(0);
        adapter = new ChainlinkOracleAdapter(priceFeed, TOLERANCE, sequencerFeed, GRACE_PERIOD);

        sequencerFeed.set(0, NOW - GRACE_PERIOD - 1, 0);
        priceFeed.set(1e8, 0, NOW);
    }

    function test_constructor_ShouldSetImmutables() public view {
        assertEq(address(adapter.priceFeed()), address(priceFeed), "priceFeed");
        assertEq(adapter.priceFeedUpdatedAtTolerance(), TOLERANCE, "tolerance");
        assertEq(adapter.priceFeedDecimals(), 8, "decimals");
        assertEq(address(adapter.sequencerFeed()), address(sequencerFeed), "sequencerFeed");
        assertEq(adapter.sequencerFeedStartedAtGracePeriod(), GRACE_PERIOD, "gracePeriod");
    }

    function test_getRate_ShouldReturnScaledPriceFor8Decimals() public view {
        assertEq(adapter.getRate(), 1e18, "rate");
    }

    function test_getRate_ShouldReturnScaledPriceFor18Decimals() public {
        priceFeed = new MockAggregator(18);
        adapter = new ChainlinkOracleAdapter(priceFeed, TOLERANCE, sequencerFeed, GRACE_PERIOD);
        priceFeed.set(2e18, 0, NOW);

        assertEq(adapter.getRate(), 2e18, "rate");
    }

    function test_getRate_ShouldRevertWhenSequencerAnswerNotZero() public {
        sequencerFeed.set(1, NOW - GRACE_PERIOD - 1, 0);

        vm.expectRevert(ChainlinkOracleAdapter.SequencerFeedInvalidAnswer.selector);
        adapter.getRate();
    }

    function test_getRate_ShouldRevertWhenSequencerStartedAtZero() public {
        sequencerFeed.set(0, 0, 0);

        vm.expectRevert(ChainlinkOracleAdapter.SequencerFeedInvalidStartedAt.selector);
        adapter.getRate();
    }

    function test_getRate_ShouldRevertWhenWithinGracePeriodBoundary() public {
        sequencerFeed.set(0, NOW - GRACE_PERIOD, 0);

        vm.expectRevert(ChainlinkOracleAdapter.SequencerFeedInvalidStartedAt.selector);
        adapter.getRate();
    }

    function test_getRate_ShouldRevertWhenPriceAnswerZero() public {
        priceFeed.set(0, 0, NOW);

        vm.expectRevert(ChainlinkOracleAdapter.PriceFeedInvalidAnswer.selector);
        adapter.getRate();
    }

    function test_getRate_ShouldRevertWhenPriceAnswerNegative() public {
        priceFeed.set(-1, 0, NOW);

        vm.expectRevert(ChainlinkOracleAdapter.PriceFeedInvalidAnswer.selector);
        adapter.getRate();
    }

    function test_getRate_ShouldRevertWhenPriceTooOld() public {
        priceFeed.set(1e8, 0, NOW - TOLERANCE - 1);

        vm.expectRevert(ChainlinkOracleAdapter.PriceFeedInvalidUpdatedAt.selector);
        adapter.getRate();
    }

    function test_getRate_ShouldReturnAtStalenessBoundary() public {
        priceFeed.set(1e8, 0, NOW - TOLERANCE);

        assertEq(adapter.getRate(), 1e18, "rate");
    }
}

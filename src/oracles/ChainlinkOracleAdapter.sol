// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

contract ChainlinkOracleAdapter {
    AggregatorV3Interface public immutable priceFeed;

    uint256 public immutable priceFeedUpdatedAtTolerance;

    uint8 public immutable priceFeedDecimals;

    AggregatorV3Interface public immutable sequencerFeed;

    uint256 public immutable sequencerFeedStartedAtGracePeriod;

    error PriceFeedInvalidUpdatedAt();

    error PriceFeedInvalidAnswer();

    error SequencerFeedInvalidAnswer();

    error SequencerFeedInvalidStartedAt();

    constructor(
        AggregatorV3Interface _priceFeed,
        uint256 _priceFeedUpdatedAtTolerance,
        AggregatorV3Interface _sequencerFeed,
        uint256 _sequencerFeedStartedAtGracePeriod
    ) {
        priceFeed = _priceFeed;
        priceFeedUpdatedAtTolerance = _priceFeedUpdatedAtTolerance;
        priceFeedDecimals = _priceFeed.decimals();

        sequencerFeed = _sequencerFeed;
        sequencerFeedStartedAtGracePeriod = _sequencerFeedStartedAtGracePeriod;
    }

    function getRate() external view returns (uint256) {
        (, int256 sequencerFeedAnswer, uint256 sequencerFeedStartedAt,,) = sequencerFeed.latestRoundData();

        if (sequencerFeedAnswer != 0) {
            revert SequencerFeedInvalidAnswer();
        }

        if (sequencerFeedStartedAt == 0) {
            revert SequencerFeedInvalidStartedAt();
        }

        if (block.timestamp - sequencerFeedStartedAt <= sequencerFeedStartedAtGracePeriod) {
            revert SequencerFeedInvalidStartedAt();
        }

        (, int256 priceFeedAnswer,, uint256 priceFeedUpdatedAt,) = priceFeed.latestRoundData();

        if (priceFeedAnswer <= 0) {
            revert PriceFeedInvalidAnswer();
        }

        if (block.timestamp - priceFeedUpdatedAt > priceFeedUpdatedAtTolerance) {
            revert PriceFeedInvalidUpdatedAt();
        }

        return 1e18 * uint256(priceFeedAnswer) / (10 ** priceFeedDecimals);
    }
}

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

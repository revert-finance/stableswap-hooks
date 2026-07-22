// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/// @notice Adapter used for stable swap tokens that rely on chainlink feeds to obtain the rate.
/// On `getRate`, maps chainlink answer to uint256 and 18 decimal precision as required + performs required validations.
contract ChainlinkOracleAdapter {
    /// @notice The address of the token pair price feed.
    AggregatorV3Interface public immutable priceFeed;

    /// @notice The amount of seconds allowed to pass from the last price update before it is considered stale.
    /// For reference, use the heartbeat value of price feed.
    uint256 public immutable priceFeedUpdatedAtTolerance;

    /// @notice The decimals the chainlink answer will be represented in.
    /// @dev It is cached on deploy to avoid external calls on each `getRate` call.
    uint8 public immutable priceFeedDecimals;

    /// @notice The address of the sequencer uptime feed.
    /// @dev Used to validate that the L2 sequencer is running without issues to prevent stale values.
    AggregatorV3Interface public immutable sequencerFeed;

    /// @notice The amount of time the sequencer has had to be running to avoid invalid results.
    uint256 public immutable sequencerFeedStartedAtGracePeriod;

    /// @notice Thrown when the price feed's last update is older than `priceFeedUpdatedAtTolerance`
    error PriceFeedInvalidUpdatedAt();

    /// @notice Thrown when the price feed answer is zero or negative
    error PriceFeedInvalidAnswer();

    /// @notice Thrown when the sequencer feed answer is non-zero, meaning the sequencer is down
    error SequencerFeedInvalidAnswer();

    /// @notice Thrown when the sequencer feed `startedAt` is zero or the grace period has not yet elapsed
    error SequencerFeedInvalidStartedAt();

    /// @notice Configures the price and sequencer feeds and caches the price feed decimals
    /// @param _priceFeed The token pair price feed
    /// @param _priceFeedUpdatedAtTolerance Seconds allowed since the last price update before it is considered stale
    /// @param _sequencerFeed The L2 sequencer uptime feed
    /// @param _sequencerFeedStartedAtGracePeriod Seconds the sequencer must have been running before answers are trusted
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

    /// @notice Returns the price feed rate scaled to 18 decimal precision
    /// @dev Validates the sequencer is up and past its grace period, then that the price feed answer is positive and fresh
    /// @return The rate in 18 decimal precision
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

/// @notice Minimal Chainlink aggregator interface used to read feed decimals and the latest round data
interface AggregatorV3Interface {
    /// @notice Returns the number of decimals the aggregator answer is represented in
    function decimals() external view returns (uint8);

    /// @notice Returns data about the latest round
    /// @return roundId The round ID
    /// @return answer The answer for this round
    /// @return startedAt The timestamp when the round started
    /// @return updatedAt The timestamp when the round was updated
    /// @return answeredInRound The round ID in which the answer was computed
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

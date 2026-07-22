// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {ChainlinkOracleAdapter, AggregatorV3Interface} from "src/oracles/ChainlinkOracleAdapter.sol";

contract DeployCbETHETHBaseChainlinkOracleAdapter is Script {
    address public constant PRICE_FEED = 0x806b4Ac04501c29769051e42783cF04dCE41440b;

    address public constant SEQUENCER_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    uint256 public constant PRICE_FEED_UPDATED_AT_TOLERANCE = 86400;

    uint256 public constant SEQUENCER_FEED_STARTED_AT_GRACE_PERIOD = 3600;

    uint256 public constant BASE_CHAIN_ID = 8453;

    function run() external {
        require(block.chainid == BASE_CHAIN_ID, "feeds are Base-only");

        console2.log("Deploying cbETH/ETH ChainlinkOracleAdapter on Base");
        console2.log("Chain ID:                ", block.chainid);
        console2.log("Price Feed:              ", PRICE_FEED);
        console2.log("Price Feed Tolerance:    ", PRICE_FEED_UPDATED_AT_TOLERANCE);
        console2.log("Sequencer Feed:          ", SEQUENCER_FEED);
        console2.log("Sequencer Grace Period:  ", SEQUENCER_FEED_STARTED_AT_GRACE_PERIOD);

        vm.startBroadcast();
        ChainlinkOracleAdapter adapter = new ChainlinkOracleAdapter(
            AggregatorV3Interface(PRICE_FEED),
            PRICE_FEED_UPDATED_AT_TOLERANCE,
            AggregatorV3Interface(SEQUENCER_FEED),
            SEQUENCER_FEED_STARTED_AT_GRACE_PERIOD
        );
        vm.stopBroadcast();

        console2.log("ChainlinkOracleAdapter deployed at:", address(adapter));
    }
}

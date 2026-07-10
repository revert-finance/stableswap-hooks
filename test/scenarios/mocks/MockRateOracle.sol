// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

contract MockRateOracle {
    uint256 public rate;

    constructor(uint256 _rate) {
        rate = _rate;
    }

    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    function getRate() external view returns (uint256) {
        return rate;
    }
}

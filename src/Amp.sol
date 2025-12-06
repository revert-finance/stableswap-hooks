// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

abstract contract Amp is AccessControlEnumerable {
    uint256 public constant MAX_AMP = 1e6;
    uint256 public constant MAX_AMP_MULTIPLIER = 10;
    uint256 public constant MIN_AMP_RAMP_TIME = 1 days;
    uint256 public constant AMP_PRECISION = 100;

    uint256 public baseAmp;
    uint256 public nextAmp;
    uint256 public baseAmpTime;
    uint256 public nextAmpTime;

    event AmpRampStarted(
        address indexed _sender, uint256 _currentAmp, uint256 _nextAmp, uint256 _baseAmpTime, uint256 _nextAmpTime
    );
    event AmpRampStopped(address indexed _sender, uint256 _currentAmp, uint256 _currentTime);

    error InvalidAmp();
    error InsufficientTimeSinceLastAmpChange();
    error InsufficientRampTime();
    error ExcessiveAmpChange();

    constructor(uint256 _baseAmp) {
        if (_baseAmp >= MAX_AMP) {
            revert InvalidAmp();
        }

        uint256 scaledBaseAmp = _baseAmp * AMP_PRECISION;

        baseAmp = scaledBaseAmp;
        nextAmp = scaledBaseAmp;
    }

    function startAmpRamp(uint256 _nextAmp, uint256 _nextAmpTime) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_nextAmp == 0 || _nextAmp >= MAX_AMP) {
            revert InvalidAmp();
        }

        if (block.timestamp <= baseAmpTime + MIN_AMP_RAMP_TIME) {
            revert InsufficientTimeSinceLastAmpChange();
        }

        if (block.timestamp + MIN_AMP_RAMP_TIME >= _nextAmpTime) {
            revert InsufficientRampTime();
        }

        uint256 scaledNextAmp = _nextAmp * AMP_PRECISION;
        uint256 currentAmp = _currentAmp();

        if (scaledNextAmp < currentAmp) {
            if (scaledNextAmp * MAX_AMP_MULTIPLIER < currentAmp) {
                revert ExcessiveAmpChange();
            }
        } else {
            if (scaledNextAmp > currentAmp * MAX_AMP_MULTIPLIER) {
                revert ExcessiveAmpChange();
            }
        }

        baseAmp = currentAmp;
        nextAmp = scaledNextAmp;
        baseAmpTime = block.timestamp;
        nextAmpTime = _nextAmpTime;

        emit AmpRampStarted(_msgSender(), currentAmp, scaledNextAmp, block.timestamp, _nextAmpTime);
    }

    function stopAmpRamp() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 currentAmp = _currentAmp();

        baseAmp = currentAmp;
        nextAmp = currentAmp;
        baseAmpTime = block.timestamp;
        nextAmpTime = block.timestamp;

        emit AmpRampStopped(_msgSender(), currentAmp, block.timestamp);
    }

    function _currentAmp() internal view returns (uint256) {
        uint256 _nextAmp = nextAmp;

        if (block.timestamp < _nextAmpTime) {
            uint256 _baseAmp = baseAmp;
            uint256 _baseAmpTime = baseAmpTime;
            uint256 _nextAmpTime = nextAmpTime;

            return _nextAmp > _baseAmp
                ? _baseAmp + (_nextAmp - _baseAmp) * (block.timestamp - _baseAmpTime) / (_nextAmpTime - _baseAmpTime)
                : _baseAmp - (_baseAmp - _nextAmp) * (block.timestamp - _baseAmpTime) / (_nextAmpTime - _baseAmpTime);
        }

        return _nextAmp;
    }
}

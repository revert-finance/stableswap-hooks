// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Base} from "src/Base.sol";
import {StableSwapMath} from "src/libraries/StableSwapMath.sol";

/// @notice Abstract contract that manages the amplification coefficient (A) for StableSwap pools
abstract contract Amp is Base {
    /// @notice Maximum allowed amplification coefficient value
    uint256 public constant MAX_AMP = 1_000_000;

    /// @notice Maximum allowed change multiplier for amp adjustments (10x)
    uint256 public constant MAX_AMP_MULTIPLIER = 10;

    /// @notice Minimum time required between amp changes
    uint256 public constant MIN_AMP_RAMP_TIME = 1 days;

    /// @notice Initial amplification coefficient (scaled by AMP_PRECISION)
    uint256 public baseAmp;

    /// @notice Target amplification coefficient (scaled by AMP_PRECISION)
    uint256 public nextAmp;

    /// @notice Timestamp when the current ramp started
    uint256 public baseAmpTime;

    /// @notice Timestamp when the ramp should complete
    uint256 public nextAmpTime;

    /// @notice Emitted when an amplification coefficient ramp is started
    event AmpRampStarted(
        address indexed _sender, uint256 _currentAmp, uint256 _nextAmp, uint256 _currentTime, uint256 _nextAmpTime
    );

    /// @notice Emitted when an amplification coefficient ramp is stopped
    event AmpRampStopped(address indexed _sender, uint256 _currentAmp, uint256 _currentTime);

    /// @notice Error thrown when amp value is invalid (zero or exceeds maximum)
    error InvalidAmp();

    /// @notice Error thrown when attempting to change amp too soon after last change
    error InsufficientTimeSinceLastAmpChange();

    /// @notice Error thrown when ramp duration is less than minimum required time
    error InsufficientRampTime();

    /// @notice Error thrown when amp change exceeds maximum allowed multiplier
    error ExcessiveAmpChange();

    /// @notice Initializes the amplification coefficient
    /// @dev Scales the initial amp by AMP_PRECISION for internal calculations
    /// @param _baseAmp Initial amplification coefficient (unscaled)
    constructor(uint256 _baseAmp) {
        if (_baseAmp >= MAX_AMP) {
            revert InvalidAmp();
        }

        uint256 scaledBaseAmp = _baseAmp * StableSwapMath.AMP_PRECISION;

        baseAmp = scaledBaseAmp;
        nextAmp = scaledBaseAmp;
    }

    /// @notice Initiates a gradual ramp of the amplification coefficient to a new value
    /// @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
    /// @dev Validates time constraints and maximum change rate to ensure pool safety
    /// @param _nextAmp Target amplification coefficient (unscaled)
    /// @param _nextAmpTime Timestamp when the ramp should complete
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

        uint256 scaledNextAmp = _nextAmp * StableSwapMath.AMP_PRECISION;
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

    /// @notice Stops the current amplification coefficient ramp immediately
    /// @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
    /// @dev Sets both base and next amp to the current interpolated value
    function stopAmpRamp() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 currentAmp = _currentAmp();

        baseAmp = currentAmp;
        nextAmp = currentAmp;
        baseAmpTime = block.timestamp;
        nextAmpTime = block.timestamp;

        emit AmpRampStopped(_msgSender(), currentAmp, block.timestamp);
    }

    /// @dev Calculates the current amplification coefficient using linear interpolation
    function _currentAmp() internal view returns (uint256) {
        uint256 _nextAmp = nextAmp;
        uint256 _nextAmpTime = nextAmpTime;

        if (block.timestamp < _nextAmpTime) {
            uint256 _baseAmp = baseAmp;
            uint256 _baseAmpTime = baseAmpTime;

            return _nextAmp > _baseAmp
                ? _baseAmp + (_nextAmp - _baseAmp) * (block.timestamp - _baseAmpTime) / (_nextAmpTime - _baseAmpTime)
                : _baseAmp - (_baseAmp - _nextAmp) * (block.timestamp - _baseAmpTime) / (_nextAmpTime - _baseAmpTime);
        }

        return _nextAmp;
    }
}

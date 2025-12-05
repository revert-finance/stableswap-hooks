// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Actions} from "src/libraries/Actions.sol";
import {Base} from "src/Base.sol";

/// @title Fees
/// @notice Abstract contract that manages protocol, hook, and LP fee collection and distribution
abstract contract Fees is AccessControlEnumerable, Base {
    /// @notice Precision constant for fee calculations (1,000,000 = 100%)
    uint256 public constant FEE_PRECISION = 1e6;

    /// @notice Address that receives protocol fees
    address public protocolFeeCollector;

    /// @notice Protocol fee percentage (scaled by FEE_PRECISION)
    uint256 public protocolFeePercentage;

    /// @notice Accumulated protocol fees for currency0
    uint256 public protocolFees0;

    /// @notice Accumulated protocol fees for currency1
    uint256 public protocolFees1;

    /// @notice Hook fee percentage (scaled by FEE_PRECISION)
    uint256 public hookFeePercentage;

    /// @notice Accumulated hook fees for currency0
    uint256 public hookFees0;

    /// @notice Accumulated hook fees for currency1
    uint256 public hookFees1;

    /// @notice LP fee percentage (scaled by FEE_PRECISION)
    uint256 public lpFeePercentage;

    /// @notice Emitted when the protocol fee collector address is updated
    /// @param _sender Address that initiated the change
    /// @param _protocolFeeCollector New protocol fee collector address
    event ProtocolFeeCollectorSet(address indexed _sender, address _protocolFeeCollector);

    /// @notice Emitted when the protocol fee percentage is updated
    /// @param _sender Address that initiated the change
    /// @param _protocolFeePercentage New protocol fee percentage
    event ProtocolFeePercentageSet(address indexed _sender, uint256 _protocolFeePercentage);

    /// @notice Emitted when the hook fee percentage is updated
    /// @param _sender Address that initiated the change
    /// @param _hookFeePercentage New hook fee percentage
    event HookFeePercentageSet(address indexed _sender, uint256 _hookFeePercentage);

    /// @notice Emitted when the LP fee percentage is updated
    /// @param _sender Address that initiated the change
    /// @param _lpFeePercentage New LP fee percentage
    event LpFeePercentageSet(address indexed _sender, uint256 _lpFeePercentage);

    /// @notice Emitted when protocol fees are withdrawn
    /// @param _sender Address that initiated the withdrawal
    /// @param _protocolFeeCollector Address receiving the fees
    /// @param _protocolFees0 Amount of currency0 fees withdrawn
    /// @param _protocolFees1 Amount of currency1 fees withdrawn
    event ProtocolFeesWithdrawn(
        address indexed _sender, address indexed _protocolFeeCollector, uint256 _protocolFees0, uint256 _protocolFees1
    );

    /// @notice Emitted when hook fees are withdrawn
    /// @param _sender Address that initiated the withdrawal
    /// @param _beneficiary Address receiving the fees
    /// @param _hookFees0 Amount of currency0 fees withdrawn
    /// @param _hookFees1 Amount of currency1 fees withdrawn
    event HookFeesWithdrawn(
        address indexed _sender, address indexed _beneficiary, uint256 _hookFees0, uint256 _hookFees1
    );

    /// @notice Error thrown when an invalid address (zero address) is provided
    error InvalidAddress();

    /// @notice Error thrown when fee percentages sum exceeds FEE_PRECISION
    error InvalidFeePercentage();

    /// @notice Initializes the fee configuration
    /// @dev Validates that the sum of all fee percentages does not exceed FEE_PRECISION
    /// @param _protocolFeeCollector Address that will receive protocol fees
    /// @param _protocolFeePercentage Initial protocol fee percentage
    /// @param _hookFeePercentage Initial hook fee percentage
    /// @param _lpFeePercentage Initial LP fee percentage
    constructor(
        address _protocolFeeCollector,
        uint256 _protocolFeePercentage,
        uint256 _hookFeePercentage,
        uint256 _lpFeePercentage
    ) {
        _setProtocolFeeCollector(_protocolFeeCollector);
        _setProtocolFeePercentage(_protocolFeePercentage);
        _setHookFeePercentage(_hookFeePercentage);
        _setLpFeePercentage(_lpFeePercentage);
    }

    /// @notice Updates the protocol fee collector address
    /// @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
    /// @param _protocolFeeCollector New protocol fee collector address
    function setProtocolFeeCollector(address _protocolFeeCollector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setProtocolFeeCollector(_protocolFeeCollector);
    }

    /// @notice Updates the protocol fee percentage
    /// @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
    /// @dev Reverts if total fee percentages exceed FEE_PRECISION
    /// @param _protocolFeePercentage New protocol fee percentage
    function setProtocolFeePercentage(uint256 _protocolFeePercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setProtocolFeePercentage(_protocolFeePercentage);
    }

    /// @notice Updates the hook fee percentage
    /// @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
    /// @dev Reverts if total fee percentages exceed FEE_PRECISION
    /// @param _hookFeePercentage New hook fee percentage
    function setHookFeePercentage(uint256 _hookFeePercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setHookFeePercentage(_hookFeePercentage);
    }

    /// @notice Updates the LP fee percentage
    /// @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
    /// @dev Reverts if total fee percentages exceed FEE_PRECISION
    /// @param _lpFeePercentage New LP fee percentage
    function setLpFeePercentage(uint256 _lpFeePercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setLpFeePercentage(_lpFeePercentage);
    }

    /// @notice Withdraws accumulated protocol fees to the protocol fee collector
    /// @dev Triggers an unlock callback to handle the withdrawal through the pool manager
    function withdrawProtocolFees() external {
        bytes memory data = abi.encode(Actions.WITHDRAW_PROTOCOL_FEES);

        poolManager.unlock(data);
    }

    /// @notice Withdraws accumulated hook fees to a specified beneficiary
    /// @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
    /// @dev Triggers an unlock callback to handle the withdrawal through the pool manager
    /// @param _beneficiary Address that will receive the hook fees
    function withdrawHookFees(address _beneficiary) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes memory data = abi.encode(Actions.WITHDRAW_HOOK_FEES, _beneficiary);

        poolManager.unlock(data);
    }

    /// @notice Internal callback handler for protocol fee withdrawals
    /// @dev Called during unlock callback to process protocol fee withdrawal
    /// @dev Resets protocol fee counters to zero after withdrawal
    function _handleWithdrawProtocolFeesCallback() internal {
        address _protocolFeeCollector = protocolFeeCollector;
        uint256 _protocolFees0 = protocolFees0;
        uint256 _protocolFees1 = protocolFees1;

        _handleWithdrawFeesPoolManagerAccounting(_protocolFeeCollector, _protocolFees0, _protocolFees1);

        protocolFees0 = 0;
        protocolFees1 = 0;

        emit ProtocolFeesWithdrawn(_msgSender(), _protocolFeeCollector, _protocolFees0, _protocolFees1);
    }

    /// @notice Internal callback handler for hook fee withdrawals
    /// @dev Called during unlock callback to process hook fee withdrawal
    /// @dev Resets hook fee counters to zero after withdrawal
    /// @param data Encoded data containing the beneficiary address
    function _handleWithdrawHookFeesCallback(bytes memory data) internal {
        (, address _beneficiary) = abi.decode(data, (uint256, address));

        uint256 _hookFees0 = hookFees0;
        uint256 _hookFees1 = hookFees1;

        _handleWithdrawFeesPoolManagerAccounting(_beneficiary, _hookFees0, _hookFees1);

        hookFees0 = 0;
        hookFees1 = 0;

        emit HookFeesWithdrawn(_msgSender(), _beneficiary, _hookFees0, _hookFees1);
    }

    /// @notice Calculates LP, hook, and protocol fees from a given amount
    /// @dev Uses simple percentage calculation with FEE_PRECISION as denominator
    /// @param _amount Total amount to calculate fees from
    /// @return lpFees Calculated LP fee amount
    /// @return hookFees Calculated hook fee amount
    /// @return protocolFees Calculated protocol fee amount
    function _getFees(uint256 _amount) internal view returns (uint256 lpFees, uint256 hookFees, uint256 protocolFees) {
        lpFees = _amount * lpFeePercentage / FEE_PRECISION;
        hookFees = _amount * hookFeePercentage / FEE_PRECISION;
        protocolFees = _amount * protocolFeePercentage / FEE_PRECISION;
    }

    /// @notice Adds fees to the appropriate accumulators
    /// @param _isCurrency0 True if fees are for currency0, false for currency1
    /// @param _protocolFees Amount of protocol fees to add
    /// @param _hookFees Amount of hook fees to add
    function _addFees(bool _isCurrency0, uint256 _protocolFees, uint256 _hookFees) internal {
        if (_isCurrency0) {
            protocolFees0 += _protocolFees;
            hookFees0 += _hookFees;
        } else {
            protocolFees1 += _protocolFees;
            hookFees1 += _hookFees;
        }
    }

    /// @notice Internal setter for protocol fee collector address
    /// @param _protocolFeeCollector New protocol fee collector address
    function _setProtocolFeeCollector(address _protocolFeeCollector) private {
        protocolFeeCollector = _protocolFeeCollector;

        emit ProtocolFeeCollectorSet(_msgSender(), _protocolFeeCollector);
    }

    /// @notice Internal setter for protocol fee percentage with validation
    /// @dev Reverts if total fee percentages exceed FEE_PRECISION
    /// @param _protocolFeePercentage New protocol fee percentage
    function _setProtocolFeePercentage(uint256 _protocolFeePercentage) private {
        uint256 feePercentageSum = _protocolFeePercentage + hookFeePercentage + lpFeePercentage;

        if (feePercentageSum > FEE_PRECISION) {
            revert InvalidFeePercentage();
        }

        protocolFeePercentage = _protocolFeePercentage;

        emit ProtocolFeePercentageSet(_msgSender(), _protocolFeePercentage);
    }

    /// @notice Internal setter for hook fee percentage with validation
    /// @dev Reverts if total fee percentages exceed FEE_PRECISION
    /// @param _hookFeePercentage New hook fee percentage
    function _setHookFeePercentage(uint256 _hookFeePercentage) private {
        uint256 feePercentageSum = protocolFeePercentage + _hookFeePercentage + lpFeePercentage;

        if (feePercentageSum > FEE_PRECISION) {
            revert InvalidFeePercentage();
        }

        hookFeePercentage = _hookFeePercentage;

        emit HookFeePercentageSet(_msgSender(), _hookFeePercentage);
    }

    /// @notice Internal setter for LP fee percentage with validation
    /// @dev Reverts if total fee percentages exceed FEE_PRECISION
    /// @param _lpFeePercentage New LP fee percentage
    function _setLpFeePercentage(uint256 _lpFeePercentage) private {
        uint256 feePercentageSum = protocolFeePercentage + hookFeePercentage + _lpFeePercentage;

        if (feePercentageSum > FEE_PRECISION) {
            revert InvalidFeePercentage();
        }

        lpFeePercentage = _lpFeePercentage;

        emit LpFeePercentageSet(_msgSender(), _lpFeePercentage);
    }

    /// @notice Handles pool manager accounting for fee withdrawals
    /// @dev Burns fees from this contract and takes them to the beneficiary
    /// @dev Reverts if beneficiary is the zero address
    /// @param _beneficiary Address receiving the fees
    /// @param _fees0 Amount of currency0 fees to withdraw
    /// @param _fees1 Amount of currency1 fees to withdraw
    function _handleWithdrawFeesPoolManagerAccounting(address _beneficiary, uint256 _fees0, uint256 _fees1) private {
        if (_beneficiary == address(0)) {
            revert InvalidAddress();
        }

        Currency _currency0 = currency0;
        Currency _currency1 = currency1;

        if (_fees0 != 0) {
            poolManager.burn(address(this), _currency0.toId(), _fees0);
            poolManager.take(_currency0, _beneficiary, _fees0);
        }

        if (_fees1 != 0) {
            poolManager.burn(address(this), _currency1.toId(), _fees1);
            poolManager.take(_currency1, _beneficiary, _fees1);
        }
    }
}

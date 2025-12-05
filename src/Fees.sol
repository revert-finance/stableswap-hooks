// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Actions} from "src/libraries/Actions.sol";
import {Base} from "src/Base.sol";

abstract contract Fees is AccessControlEnumerable, Base {
    uint256 public constant FEE_PRECISION = 1e6;

    address public protocolFeeCollector;
    uint256 public protocolFeePercentage;
    uint256 public protocolFees0;
    uint256 public protocolFees1;
    uint256 public hookFeePercentage;
    uint256 public hookFees0;
    uint256 public hookFees1;
    uint256 public lpFeePercentage;

    event ProtocolFeeCollectorSet(address indexed _sender, address _protocolFeeCollector);
    event ProtocolFeePercentageSet(address indexed _sender, uint256 _protocolFeePercentage);
    event HookFeePercentageSet(address indexed _sender, uint256 _hookFeePercentage);
    event LpFeePercentageSet(address indexed _sender, uint256 _lpFeePercentage);
    event ProtocolFeesWithdrawn(
        address indexed _sender, address indexed _protocolFeeCollector, uint256 _protocolFees0, uint256 _protocolFees1
    );
    event HookFeesWithdrawn(
        address indexed _sender, address indexed _beneficiary, uint256 _hookFees0, uint256 _hookFees1
    );

    error InvalidAddress();
    error InvalidFeePercentage();

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

    function setProtocolFeeCollector(address _protocolFeeCollector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setProtocolFeeCollector(_protocolFeeCollector);
    }

    function setProtocolFeePercentage(uint256 _protocolFeePercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setProtocolFeePercentage(_protocolFeePercentage);
    }

    function setHookFeePercentage(uint256 _hookFeePercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setHookFeePercentage(_hookFeePercentage);
    }

    function setLpFeePercentage(uint256 _lpFeePercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setLpFeePercentage(_lpFeePercentage);
    }

    function withdrawProtocolFees() external {
        bytes memory data = abi.encode(Actions.WITHDRAW_PROTOCOL_FEES);

        poolManager.unlock(data);
    }

    function withdrawHookFees(address _beneficiary) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes memory data = abi.encode(Actions.WITHDRAW_HOOK_FEES, _beneficiary);

        poolManager.unlock(data);
    }

    function _handleWithdrawProtocolFeesCallback() internal {
        address _protocolFeeCollector = protocolFeeCollector;
        uint256 _protocolFees0 = protocolFees0;
        uint256 _protocolFees1 = protocolFees1;

        _handleFeesPoolManagerAccounting(_protocolFeeCollector, _protocolFees0, _protocolFees1);

        protocolFees0 = 0;
        protocolFees1 = 0;

        emit ProtocolFeesWithdrawn(_msgSender(), _protocolFeeCollector, _protocolFees0, _protocolFees1);
    }

    function _handleWithdrawHookFeesCallback(bytes memory data) internal {
        (, address _beneficiary) = abi.decode(data, (uint256, address));

        uint256 _hookFees0 = hookFees0;
        uint256 _hookFees1 = hookFees1;

        _handleFeesPoolManagerAccounting(_beneficiary, _hookFees0, _hookFees1);

        hookFees0 = 0;
        hookFees1 = 0;

        emit HookFeesWithdrawn(_msgSender(), _beneficiary, _hookFees0, _hookFees1);
    }

    function _getFees(uint256 _amount) internal returns (uint256 lpFees, uint256 hookFees, uint256 protocolFees) {
        lpFees = _amount * lpFeePercentage / FEE_PRECISION;
        hookFees = _amount * hookFeePercentage / FEE_PRECISION;
        protocolFees = _amount * protocolFeePercentage / FEE_PRECISION;
    }

    function _addFees(bool _isCurrency0, uint256 _protocolFees, uint256 _hookFees) internal {
        if (_isCurrency0) {
            protocolFees0 += _protocolFees;
            hookFees0 += _hookFees;
        } else {
            protocolFees1 += _protocolFees;
            hookFees1 += _hookFees;
        }
    }

    function _setProtocolFeeCollector(address _protocolFeeCollector) private {
        protocolFeeCollector = _protocolFeeCollector;

        emit ProtocolFeeCollectorSet(_msgSender(), _protocolFeeCollector);
    }

    function _setProtocolFeePercentage(uint256 _protocolFeePercentage) private {
        uint256 feePercentageSum = _protocolFeePercentage + hookFeePercentage + lpFeePercentage;

        if (feePercentageSum > FEE_PRECISION) {
            revert InvalidFeePercentage();
        }

        protocolFeePercentage = _protocolFeePercentage;

        emit ProtocolFeePercentageSet(_msgSender(), _protocolFeePercentage);
    }

    function _setHookFeePercentage(uint256 _hookFeePercentage) private {
        uint256 feePercentageSum = protocolFeePercentage + _hookFeePercentage + lpFeePercentage;

        if (feePercentageSum > FEE_PRECISION) {
            revert InvalidFeePercentage();
        }

        hookFeePercentage = _hookFeePercentage;

        emit HookFeePercentageSet(_msgSender(), _hookFeePercentage);
    }

    function _setLpFeePercentage(uint256 _lpFeePercentage) private {
        uint256 feePercentageSum = protocolFeePercentage + hookFeePercentage + _lpFeePercentage;

        if (feePercentageSum > FEE_PRECISION) {
            revert InvalidFeePercentage();
        }

        lpFeePercentage = _lpFeePercentage;

        emit LpFeePercentageSet(_msgSender(), _lpFeePercentage);
    }

    function _handleFeesPoolManagerAccounting(address _beneficiary, uint256 _fees0, uint256 _fees1) private {
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

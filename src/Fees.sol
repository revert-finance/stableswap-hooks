// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Actions} from "src/libraries/Actions.sol";

abstract contract Base {
    IPoolManager public poolManager;

    Currency public currency0;
    Currency public currency1;

    constructor(address _currency0, address _currency1) {
        currency0 = Currency.wrap(_currency0);
        currency1 = Currency.wrap(_currency1);
    }
}

abstract contract Fees is AccessControlEnumerable, Base {
    bytes32 public constant HOOK_FEE_COLLECTOR_ROLE = keccak256("HOOK_FEE_COLLECTOR_ROLE");

    address public protocolFeeCollector;
    uint256 public protocolFees0;
    uint256 public protocolFees1;
    uint256 public hookFees0;
    uint256 public hookFees1;

    event ProtocolFeeCollectorSet(address indexed _sender, address _protocolFeeCollector);

    error ProtocolFeeCollectorZeroAddress();

    constructor(address _protocolFeeCollector, address _hookFeeCollector) {
        _setProtocolFeeCollector(_protocolFeeCollector);

        _grantRole(HOOK_FEE_COLLECTOR_ROLE, _hookFeeCollector);
    }

    function setProtocolFeeCollector(address _protocolFeeCollector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setProtocolFeeCollector(_protocolFeeCollector);
    }

    function withdrawProtocolFees() external {
        address _protocolFeeCollector = protocolFeeCollector;

        if (_protocolFeeCollector == address(0)) {
            revert ProtocolFeeCollectorZeroAddress();
        }

        bytes memory data = abi.encode(Actions.WITHDRAW_PROTOCOL_FEES);

        poolManager.unlock(data);
    }

    function withdrawHookFees(address _beneficiary) external onlyRole(HOOK_FEE_COLLECTOR_ROLE) {
        bytes memory data = abi.encode(Actions.WITHDRAW_HOOK_FEES, _beneficiary);

        poolManager.unlock(data);
    }

    function _handleWithdrawProtocolFeesCallback() internal {
        _handleFeesPoolManagerAccounting(protocolFeeCollector, protocolFees0, protocolFees1);

        protocolFees0 = 0;
        protocolFees1 = 0;
    }

    function _handleWithdrawkHookFeesCallback(bytes memory data) internal {
        (, address _beneficiary) = abi.decode(data, (uint256, address));

        _handleFeesPoolManagerAccounting(_beneficiary, hookFees0, hookFees1);

        hookFees0 = 0;
        hookFees1 = 0;
    }

    function _handleFeesPoolManagerAccounting(address _beneficiary, uint256 _fees0, uint256 _fees1) private {
        Currency _currency0 = currency0;
        Currency _currency1 = currency1;

        poolManager.burn(address(this), _currency0.toId(), _fees0);
        poolManager.take(_currency0, _beneficiary, _fees0);

        poolManager.burn(address(this), _currency1.toId(), _fees1);
        poolManager.take(_currency1, _beneficiary, _fees1);
    }

    function _setProtocolFeeCollector(address _protocolFeeCollector) private {
        protocolFeeCollector = _protocolFeeCollector;

        emit ProtocolFeeCollectorSet(_msgSender(), _protocolFeeCollector);
    }
}

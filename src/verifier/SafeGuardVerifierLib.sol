// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {ISafeGuard} from "src/interfaces/external/ISafeGuard.sol";

library SafeGuardVerifierLib {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant PROCESSOR_MANAGER_ROLE = keccak256("PROCESSOR_MANAGER_ROLE");
    bytes32 internal constant GUARD_ADMIN_ROLE = keccak256("GUARD_ADMIN_ROLE");

    error VerificationFailed(string check);

    function verify(
        address factory,
        IVaultFactory.CreatedVault memory created,
        IVaultFactory.VaultParams memory vaultParams,
        IVaultFactory.FlexStrategyParams memory flexParams
    ) external view {
        ISafeGuardView safeGuard = ISafeGuardView(created.safeGuard);
        _verify(created.safeGuard.code.length != 0, "safeguard code");
        _verifyString(safeGuard.name(), string.concat(flexParams.strategyName, " Safeguard"), "safeguard name");
        _verifyRole(safeGuard, DEFAULT_ADMIN_ROLE, created.timelock, true, "safeguard admin");
        _verifyRole(safeGuard, PROCESSOR_MANAGER_ROLE, created.timelock, true, "safeguard processor manager");
        _verifyRole(safeGuard, GUARD_ADMIN_ROLE, created.timelock, true, "safeguard guard admin");
        _verifyRole(safeGuard, DEFAULT_ADMIN_ROLE, factory, false, "safeguard dangling admin");
        _verifyRole(safeGuard, PROCESSOR_MANAGER_ROLE, factory, false, "safeguard dangling processor manager");
        _verifyRole(safeGuard, GUARD_ADMIN_ROLE, factory, false, "safeguard dangling guard admin");

        ISafeGuard.FunctionRule memory rule =
            safeGuard.getProcessorRule(vaultParams.baseAsset, IERC20.transfer.selector);
        _verify(rule.isActive, "safeguard transfer inactive");
        _verify(rule.validator == address(0), "safeguard transfer validator");
        _verify(rule.paramRules.length == 2, "safeguard transfer params");
        _verifyAddressParam(rule.paramRules[0], flexParams.offRampAddress, "safeguard transfer recipient");
        _verifyUintParam(rule.paramRules[1], "safeguard transfer amount");
    }

    function _verifyAddressParam(ISafeGuard.ParamRule memory param, address allowed, string memory check)
        internal
        pure
    {
        _verify(uint256(param.paramType) == uint256(ISafeGuard.ParamType.ADDRESS), check);
        _verify(!param.isArray, check);
        _verify(param.allowList.length == 1, check);
        _verify(param.allowList[0] == allowed, check);
    }

    function _verifyUintParam(ISafeGuard.ParamRule memory param, string memory check) internal pure {
        _verify(uint256(param.paramType) == uint256(ISafeGuard.ParamType.UINT256), check);
        _verify(!param.isArray, check);
        _verify(param.allowList.length == 0, check);
    }

    function _verifyRole(IAccessControlView target, bytes32 role, address account, bool expected, string memory check)
        internal
        view
    {
        _verify(target.hasRole(role, account) == expected, check);
    }

    function _verifyString(string memory actual, string memory expected, string memory check) internal pure {
        _verify(keccak256(bytes(actual)) == keccak256(bytes(expected)), check);
    }

    function _verify(bool condition, string memory check) internal pure {
        if (!condition) revert VerificationFailed(check);
    }
}

interface IAccessControlView {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface ISafeGuardView is ISafeGuard, IAccessControlView {
    function name() external view returns (string memory);
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";

library AccountingModuleHookVerifierLib {
    error VerificationFailed(string check);

    function verify(IVaultFactory.CreatedVault memory created) external view {
        IAccountingModuleHookView hook = IAccountingModuleHookView(created.accountingModuleHook);

        _verify(created.accountingModuleHook.code.length != 0, "hook code");
        _verify(hook.VAULT() == created.flexStrategy, "hook vault");
        _verify(hook.flexStrategy() == created.flexStrategy, "hook strategy");
        _verify(hook.accountingModule() == created.accountingModule, "hook module");
    }

    function _verify(bool condition, string memory check) internal pure {
        if (!condition) revert VerificationFailed(check);
    }
}

interface IAccountingModuleHookView {
    function VAULT() external view returns (address);
    function flexStrategy() external view returns (address);
    function accountingModule() external view returns (address);
}

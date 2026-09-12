// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IERC20Metadata} from "src/interfaces/external/IERC20Metadata.sol";
import {IVault} from "src/interfaces/external/IVault.sol";
import {VaultVerifierLib, IAccessControlView, IVaultView} from "src/verifier/VaultVerifierLib.sol";

contract VaultVerifier {
    struct Verification {
        address factory;
        IVaultFactory.CreatedVault created;
        IVaultFactory.VaultParams vaultParams;
        IVaultFactory.FlexStrategyParams flexParams;
    }

    error VerificationFailed(string check);

    function verify(address vault, Verification calldata verification) external view returns (bool) {
        VaultVerifierLib.Verification memory libVerification = VaultVerifierLib.Verification({
            factory: verification.factory,
            created: verification.created,
            vaultParams: verification.vaultParams,
            flexParams: verification.flexParams
        });

        return VaultVerifierLib.verify(vault, libVerification);
    }

    function _verifyRole(IAccessControlView target, bytes32 role, address account, bool expected, string memory check)
        internal
        view
    {
        if (target.hasRole(role, account) != expected) revert VerificationFailed(check);
    }

    function _decimals(address target) internal view returns (uint8) {
        return IERC20Metadata(target).decimals();
    }

    function _getRule(address target, address asset, bytes4 selector)
        internal
        view
        returns (IVault.FunctionRule memory)
    {
        return IVaultView(target).getProcessorRule(asset, selector);
    }
}

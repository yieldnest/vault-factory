// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IVault} from "src/interfaces/external/IVault.sol";

library HooksVerifierLib {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 internal constant HOOK_MANAGER_ROLE = keccak256("HOOK_MANAGER_ROLE");

    error VerificationFailed(string check);

    function verify(
        address factory,
        IVaultFactory.CreatedVault memory created,
        IVaultFactory.VaultParams memory vaultParams,
        IVaultFactory.HooksConfig memory config
    ) external view {
        IVaultHookView vault = IVaultHookView(created.vault);
        uint256 hookCount;
        if (config.deployPauserHook) hookCount++;
        if (config.deployFeeHook) hookCount++;
        if (config.deployProcessAccountingGuardHook) hookCount++;

        if (hookCount == 0) {
            _verify(vault.hooks() == address(0), "unexpected vault hooks");
            _verify(created.metaHooks == address(0), "unexpected meta hooks");
            _verify(created.pauserHook == address(0), "unexpected pauser hook");
            _verify(created.feeHook == address(0), "unexpected fee hook");
            _verify(created.processAccountingGuardHook == address(0), "unexpected accounting guard hook");
            return;
        }

        IMetaHooksView metaHooks = IMetaHooksView(created.metaHooks);
        _verify(created.metaHooks.code.length != 0, "meta hooks code");
        _verify(vault.hooks() == created.metaHooks, "vault hooks");
        _verify(metaHooks.VAULT() == created.vault, "meta hooks vault");
        _verify(metaHooks.hooksLength() == hookCount, "meta hooks length");
        _verifyRole(metaHooks, DEFAULT_ADMIN_ROLE, created.timelock, true, "meta hooks admin");
        _verifyRole(metaHooks, HOOK_MANAGER_ROLE, created.timelock, true, "meta hooks manager");
        _verifyRole(metaHooks, DEFAULT_ADMIN_ROLE, factory, false, "meta hooks dangling admin");
        _verifyRole(metaHooks, HOOK_MANAGER_ROLE, factory, false, "meta hooks dangling manager");

        uint256 index;
        if (config.deployPauserHook) {
            _verify(address(metaHooks.hooks(index++)) == created.pauserHook, "pauser hook order");
            IPauserHookView pauserHook = IPauserHookView(created.pauserHook);
            _verify(created.pauserHook.code.length != 0, "pauser hook code");
            _verify(pauserHook.VAULT() == created.metaHooks, "pauser hook vault");
            _verifyRole(pauserHook, DEFAULT_ADMIN_ROLE, created.timelock, true, "pauser hook admin");
            _verifyRole(pauserHook, PAUSER_ROLE, vaultParams.pauser, true, "pauser hook pauser");
            _verifyRole(pauserHook, UNPAUSER_ROLE, vaultParams.unpauser, true, "pauser hook unpauser");
        } else {
            _verify(created.pauserHook == address(0), "unexpected pauser hook");
        }

        if (config.deployFeeHook) {
            _verify(address(metaHooks.hooks(index++)) == created.feeHook, "fee hook order");
            IFeeHookView feeHook = IFeeHookView(created.feeHook);
            _verify(created.feeHook.code.length != 0, "fee hook code");
            _verify(feeHook.VAULT() == created.metaHooks, "fee hook vault");
            _verify(feeHook.owner() == created.timelock, "fee hook owner");
            _verify(feeHook.performanceFee() == config.feeHook.performanceFee, "fee hook performance fee");
            _verify(feeHook.performanceFeeRecipient() == created.timelock, "fee hook recipient");
            _verifyFeeHookConfig(feeHook.getConfig());
        } else {
            _verify(created.feeHook == address(0), "unexpected fee hook");
        }

        if (config.deployProcessAccountingGuardHook) {
            _verify(address(metaHooks.hooks(index++)) == created.processAccountingGuardHook, "guard hook order");
            IProcessAccountingGuardHookView guard = IProcessAccountingGuardHookView(created.processAccountingGuardHook);
            _verify(created.processAccountingGuardHook.code.length != 0, "guard hook code");
            _verify(guard.VAULT() == created.metaHooks, "guard hook vault");
            _verify(guard.owner() == created.timelock, "guard hook owner");
            _verify(
                guard.maxTotalAssetsDecreaseRatio() == config.processAccountingGuardHook.maxTotalAssetsDecreaseRatio,
                "guard decrease"
            );
            _verify(
                guard.maxTotalAssetsIncreaseRatio() == config.processAccountingGuardHook.maxTotalAssetsIncreaseRatio,
                "guard increase"
            );
            _verify(
                guard.maxTotalSupplyIncreaseRatio() == config.processAccountingGuardHook.maxTotalSupplyIncreaseRatio,
                "guard supply"
            );
            _verify(
                guard.expectedPerformanceFee() == config.processAccountingGuardHook.expectedPerformanceFee, "guard fee"
            );
        } else {
            _verify(created.processAccountingGuardHook == address(0), "unexpected accounting guard hook");
        }
    }

    function _verifyFeeHookConfig(IHooks.Config memory config) internal pure {
        _verify(!config.beforeDeposit, "fee hook before deposit");
        _verify(!config.afterDeposit, "fee hook after deposit");
        _verify(!config.beforeMint, "fee hook before mint");
        _verify(!config.afterMint, "fee hook after mint");
        _verify(!config.beforeRedeem, "fee hook before redeem");
        _verify(!config.afterRedeem, "fee hook after redeem");
        _verify(!config.beforeWithdraw, "fee hook before withdraw");
        _verify(!config.afterWithdraw, "fee hook after withdraw");
        _verify(!config.beforeProcessAccounting, "fee hook before accounting");
        _verify(config.afterProcessAccounting, "fee hook after accounting");
    }

    function _verifyRole(IAccessControlView target, bytes32 role, address account, bool expected, string memory check)
        internal
        view
    {
        _verify(target.hasRole(role, account) == expected, check);
    }

    function _verify(bool condition, string memory check) internal pure {
        if (!condition) revert VerificationFailed(check);
    }
}

interface IVaultHookView is IVault {
    function hooks() external view returns (address);
}

interface IAccessControlView {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IMetaHooksView is IAccessControlView {
    function VAULT() external view returns (address);
    function hooks(uint256 index) external view returns (IHooks);
    function hooksLength() external view returns (uint256);
}

interface IPauserHookView is IAccessControlView {
    function VAULT() external view returns (address);
}

interface IFeeHookView {
    function VAULT() external view returns (address);
    function owner() external view returns (address);
    function performanceFee() external view returns (uint256);
    function performanceFeeRecipient() external view returns (address);
    function getConfig() external view returns (IHooks.Config memory);
}

interface IProcessAccountingGuardHookView {
    function VAULT() external view returns (address);
    function owner() external view returns (address);
    function maxTotalAssetsDecreaseRatio() external view returns (uint256);
    function maxTotalAssetsIncreaseRatio() external view returns (uint256);
    function maxTotalSupplyIncreaseRatio() external view returns (uint256);
    function expectedPerformanceFee() external view returns (uint256);
}

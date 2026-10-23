// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MetaHooks} from "lib/yieldnest-vault-periphery/src/hooks/MetaHooks.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {FeeHookDeployer} from "src/lib/FeeHookDeployer.sol";
import {PauserHookDeployer} from "src/lib/PauserHookDeployer.sol";
import {ProcessAccountingGuardHookDeployer} from "src/lib/ProcessAccountingGuardHookDeployer.sol";

library VaultHooksDeployer {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant HOOK_MANAGER_ROLE = keccak256("HOOK_MANAGER_ROLE");

    struct DeployedHooks {
        address metaHooks;
        address pauserHook;
        address feeHook;
        address processAccountingGuardHook;
    }

    function deploy(
        address vault,
        address timelock,
        address admin,
        address pauser,
        address unpauser,
        IVaultFactory.HooksConfig memory config
    ) external returns (DeployedHooks memory deployed) {
        uint256 hookCount = _hookCount(config);
        if (hookCount == 0) return deployed;

        MetaHooks metaHooks = new MetaHooks(vault, address(this), address(this));
        deployed.metaHooks = address(metaHooks);

        IHooks[] memory hooks = new IHooks[](hookCount);
        uint256 index;

        if (config.deployPauserHook) {
            deployed.pauserHook = PauserHookDeployer.deploy(deployed.metaHooks, address(this), pauser, unpauser);
            IAccessControl(deployed.pauserHook).grantRole(DEFAULT_ADMIN_ROLE, admin);
            IAccessControl(deployed.pauserHook).grantRole(DEFAULT_ADMIN_ROLE, timelock);
            IAccessControl(deployed.pauserHook).renounceRole(DEFAULT_ADMIN_ROLE, address(this));
            hooks[index++] = IHooks(deployed.pauserHook);
        }

        if (config.deployFeeHook) {
            deployed.feeHook = FeeHookDeployer.deploy(
                deployed.metaHooks, admin, config.feeHook.performanceFee, config.feeHook.feeRecipient
            );
            hooks[index++] = IHooks(deployed.feeHook);
        }

        if (config.deployProcessAccountingGuardHook) {
            deployed.processAccountingGuardHook = ProcessAccountingGuardHookDeployer.deploy(
                deployed.metaHooks, timelock, config.processAccountingGuardHook
            );
            hooks[index++] = IHooks(deployed.processAccountingGuardHook);
        }

        metaHooks.setHooks(hooks);
        metaHooks.grantRole(DEFAULT_ADMIN_ROLE, timelock);
        metaHooks.grantRole(DEFAULT_ADMIN_ROLE, admin);
        metaHooks.grantRole(HOOK_MANAGER_ROLE, timelock);
        metaHooks.renounceRole(HOOK_MANAGER_ROLE, address(this));
        metaHooks.renounceRole(DEFAULT_ADMIN_ROLE, address(this));
    }

    function _hookCount(IVaultFactory.HooksConfig memory config) internal pure returns (uint256 count) {
        if (config.deployPauserHook) count++;
        if (config.deployFeeHook) count++;
        if (config.deployProcessAccountingGuardHook) count++;
    }
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {RegistryImplementations} from "script/RegistryImplementations.sol";

abstract contract CreateVault is Script {
    bytes32 private constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function run() external returns (IVaultFactory.CreatedVault memory created) {
        address factory = vm.promptAddress("VaultFactory address");

        IVaultFactory.VaultParams memory params = _vaultParams();
        IVaultFactory.FlexStrategyParams memory flexParams = _flexParams();
        IVaultFactory.HooksConfig memory hooksConfig = _hooksConfig();

        vm.startBroadcast();
        (bytes32 deploymentId, IVaultFactory.CreatedVault memory started) =
            IVaultFactory(factory).startCreateVault(params, flexParams, hooksConfig);
        IERC20(params.baseAsset).approve(factory, params.bootstrapAmount * 2);
        created = IVaultFactory(factory).resumeCreateVault(deploymentId);
        vm.stopBroadcast();

        _logDeployment(deploymentId, started, created);
        _writeDeployment(deploymentId, created);
    }

    function _vaultParams() internal pure virtual returns (IVaultFactory.VaultParams memory);
    function _flexParams() internal pure virtual returns (IVaultFactory.FlexStrategyParams memory);
    function _hooksConfig() internal pure virtual returns (IVaultFactory.HooksConfig memory);

    function _deploymentName() internal pure virtual returns (string memory) {
        return "rwa-vault";
    }

    function _logDeployment(
        bytes32 deploymentId,
        IVaultFactory.CreatedVault memory started,
        IVaultFactory.CreatedVault memory created
    ) internal pure {
        console2.logBytes32(deploymentId);
        console2.log("Started vault:", started.vault);
        console2.log("Vault:", created.vault);
        console2.log("Timelock:", created.timelock);
        console2.log("Wrapped token:", created.wrappedToken);
        console2.log("Provider:", created.provider);
        console2.log("MetaHooks:", created.metaHooks);
        console2.log("PauserHook:", created.pauserHook);
        console2.log("FeeHook:", created.feeHook);
        console2.log("Process accounting guard hook:", created.processAccountingGuardHook);
        console2.log("Withdrawal request:", created.withdrawalRequest);
        console2.log("Withdrawer:", created.withdrawer);
        console2.log("Bag factory:", created.bagFactory);
        console2.log("Request policy:", created.requestPolicy);
        console2.log("SafeGuard:", created.safeGuard);
        console2.log("Accounting module hook:", created.accountingModuleHook);
        console2.log("Flex strategy:", created.flexStrategy);
        console2.log("Accounting token:", created.accountingToken);
        console2.log("Accounting module:", created.accountingModule);
        console2.log("Rewards sweeper:", created.rewardsSweeper);
    }

    function _writeDeployment(bytes32 deploymentId, IVaultFactory.CreatedVault memory created) internal {
        string memory obj = "deployment";
        vm.serializeBytes32(obj, "deploymentId", deploymentId);
        vm.serializeAddress(obj, "vault", created.vault);
        vm.serializeAddress(obj, "vaultProxyAdmin", _proxyAdmin(created.vault));
        vm.serializeAddress(obj, "timelock", created.timelock);
        vm.serializeAddress(obj, "wrappedToken", created.wrappedToken);
        vm.serializeAddress(obj, "wrappedTokenProxyAdmin", _proxyAdmin(created.wrappedToken));
        vm.serializeAddress(obj, "provider", created.provider);
        vm.serializeAddress(obj, "metaHooks", created.metaHooks);
        vm.serializeAddress(obj, "pauserHook", created.pauserHook);
        vm.serializeAddress(obj, "feeHook", created.feeHook);
        vm.serializeAddress(obj, "processAccountingGuardHook", created.processAccountingGuardHook);
        vm.serializeAddress(obj, "withdrawalRequest", created.withdrawalRequest);
        vm.serializeAddress(obj, "withdrawalRequestProxyAdmin", _proxyAdmin(created.withdrawalRequest));
        vm.serializeAddress(obj, "withdrawer", created.withdrawer);
        vm.serializeAddress(obj, "withdrawerProxyAdmin", _proxyAdmin(created.withdrawer));
        vm.serializeAddress(obj, "bagFactory", created.bagFactory);
        vm.serializeAddress(obj, "bagFactoryProxyAdmin", _proxyAdmin(created.bagFactory));
        vm.serializeAddress(obj, "withdrawalRequestViewer", RegistryImplementations.WITHDRAWAL_REQUEST_VIEWER);
        vm.serializeAddress(obj, "safeGuard", created.safeGuard);
        vm.serializeAddress(obj, "safeGuardProxyAdmin", _proxyAdmin(created.safeGuard));
        vm.serializeAddress(obj, "accountingModuleHook", created.accountingModuleHook);
        vm.serializeAddress(obj, "flexStrategy", created.flexStrategy);
        vm.serializeAddress(obj, "flexStrategyProxyAdmin", _proxyAdmin(created.flexStrategy));
        vm.serializeAddress(obj, "accountingToken", created.accountingToken);
        vm.serializeAddress(obj, "accountingTokenProxyAdmin", _proxyAdmin(created.accountingToken));
        vm.serializeAddress(obj, "accountingModule", created.accountingModule);
        vm.serializeAddress(obj, "accountingModuleProxyAdmin", _proxyAdmin(created.accountingModule));
        vm.serializeAddress(obj, "rewardsSweeper", created.rewardsSweeper);
        vm.serializeAddress(obj, "rewardsSweeperProxyAdmin", _proxyAdmin(created.rewardsSweeper));
        string memory json = vm.serializeAddress(obj, "requestPolicy", created.requestPolicy);

        vm.createDir("deployments", true);
        string memory path = string.concat("deployments/", _deploymentName(), "-", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console2.log("Deployment written to:", path);
    }

    function _proxyAdmin(address proxy) internal view returns (address) {
        if (proxy == address(0)) return address(0);
        return address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
    }
}

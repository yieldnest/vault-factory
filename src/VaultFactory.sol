// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IERC20} from "src/interfaces/external/IERC20.sol";
import {IERC20Metadata} from "src/interfaces/external/IERC20Metadata.sol";
import {IVault} from "src/interfaces/external/IVault.sol";
import {UninitializedTransparentUpgradeableProxy} from "src/proxy/UninitializedTransparentUpgradeableProxy.sol";

contract VaultFactory is IVaultFactory {
    string public constant VERSION = "0.1.0";
    uint8 public constant VAULT_DECIMALS = 18;
    uint64 public constant BASE_WITHDRAWAL_FEE = 0;

    IRegistry public immutable REGISTRY;

    constructor(IRegistry registry) {
        if (address(registry) == address(0)) revert ZeroAddress();
        REGISTRY = registry;
    }

    function createVault(
        VaultParams calldata params,
        RegistryKeys calldata keys,
        FlexStrategyParams calldata flexParams
    ) external returns (CreatedVault memory created) {
        _validateVaultParams(params);

        TimelockController timelock = _deployTimelock(params.admin, params.timelockDuration);
        address vaultLogic = _registryValue(keys.vault);
        uint256 defaultAssetIndex = params.baseAsset == params.defaultAsset ? 0 : 1;

        created.timelock = address(timelock);
        created.vault = address(new UninitializedTransparentUpgradeableProxy(vaultLogic, address(timelock)));

        IVault vault = IVault(created.vault);
        _initializeVault(vault, params, defaultAssetIndex);
        _configureVault(vault, params, address(timelock), defaultAssetIndex);

        if (flexParams.deployStrategy) {
            // TODO: Deploy and configure the flex strategy once its deployment API is finalized.
            // TODO: Deploy and configure the flex strategy SafeGuard once its deployment API is finalized.
        }

        _bootstrap(vault, params);
        _renounceTemporaryRoles(vault);

        emit VaultCreated(msg.sender, created.vault, created.timelock, created.safeGuard, created.flexStrategy);
    }

    function _initializeVault(IVault vault, VaultParams calldata params, uint256 defaultAssetIndex) internal {
        vault.initialize(
            address(this),
            params.tokenName,
            params.tokenSymbol,
            VAULT_DECIMALS,
            BASE_WITHDRAWAL_FEE,
            params.countNativeAsset,
            params.alwaysComputeTotalAssets,
            defaultAssetIndex
        );
    }

    function _validateVaultParams(VaultParams calldata params) internal view {
        if (
            params.admin == address(0) || params.processor == address(0) || params.pauser == address(0)
                || params.unpauser == address(0) || params.feeManager == address(0) || params.baseAsset == address(0)
                || params.defaultAsset == address(0) || params.provider == address(0)
                || params.bootstrapReceiver == address(0)
        ) {
            revert ZeroAddress();
        }

        if (params.bootstrapAmount == 0) revert ZeroAmount();
        if (IERC20Metadata(params.baseAsset).decimals() != VAULT_DECIMALS) {
            revert AssetDecimalsMismatch(IERC20Metadata(params.baseAsset).decimals());
        }
        if (params.baseAsset != params.defaultAsset && IERC20Metadata(params.defaultAsset).decimals() > VAULT_DECIMALS)
        {
            revert InvalidDefaultAsset();
        }
    }

    function _deployTimelock(address admin, uint256 timelockDuration) internal returns (TimelockController) {
        address[] memory proposers = new address[](1);
        proposers[0] = admin;

        address[] memory executors = new address[](1);
        executors[0] = admin;

        return new TimelockController(timelockDuration, proposers, executors, address(0));
    }

    function _configureVault(IVault vault, VaultParams calldata params, address timelock, uint256 defaultAssetIndex)
        internal
    {
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.UNPAUSER_ROLE(), address(this));

        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), timelock);
        vault.grantRole(vault.PROCESSOR_ROLE(), params.processor);
        vault.grantRole(vault.PAUSER_ROLE(), params.pauser);
        vault.grantRole(vault.UNPAUSER_ROLE(), params.unpauser);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), params.feeManager);

        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), timelock);

        vault.addAsset(params.baseAsset, true);
        if (defaultAssetIndex == 1) {
            vault.addAsset(params.defaultAsset, true);
        }
        vault.setProvider(params.provider);
        vault.setBuffer(address(0));
    }

    function _bootstrap(IVault vault, VaultParams calldata params) internal {
        IERC20 asset = IERC20(params.defaultAsset);
        _requireTrue(asset.transferFrom(msg.sender, address(this), params.bootstrapAmount));
        _requireTrue(asset.approve(address(vault), params.bootstrapAmount));
        vault.unpause();
        vault.deposit(params.bootstrapAmount, params.bootstrapReceiver);
        _requireTrue(asset.approve(address(vault), 0));
    }

    function _renounceTemporaryRoles(IVault vault) internal {
        vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), address(this));
        vault.renounceRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.BUFFER_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.PROCESSOR_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.HOOKS_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.UNPAUSER_ROLE(), address(this));
    }

    function _registryValue(bytes32 key) internal view returns (address value) {
        if (key == bytes32(0)) revert EmptyKey(key);
        value = REGISTRY.valueOf(key);
        if (value == address(0)) revert MissingRegistryValue(key);
    }

    function _requireTrue(bool success) internal pure {
        if (!success) revert TokenCallFailed();
    }
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IERC20Metadata} from "src/interfaces/external/IERC20Metadata.sol";
import {IBeaconProxyFactory} from "src/interfaces/external/IBeaconProxyFactory.sol";
import {IVault} from "src/interfaces/external/IVault.sol";
import {IWithdrawalRequest} from "src/interfaces/external/IWithdrawalRequest.sol";
import {IWithdrawer} from "src/interfaces/external/IWithdrawer.sol";
import {IWrappedToken} from "src/interfaces/external/IWrappedToken.sol";
import {MinAmountRequestPolicy} from "src/MinAmountRequestPolicy.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {TimelockDeployer} from "src/lib/TimelockDeployer.sol";
import {UninitializedTransparentUpgradeableProxy} from "src/proxy/UninitializedTransparentUpgradeableProxy.sol";

contract VaultFactory is IVaultFactory {
    using SafeERC20 for IERC20;

    string public constant VERSION = "0.1.0";
    uint8 public constant VAULT_DECIMALS = 18;
    uint64 public constant BASE_WITHDRAWAL_FEE = 0;

    struct Assets {
        address baseAsset;
        address defaultAsset;
        uint256 defaultAssetIndex;
        address wrappedToken;
    }

    struct WithdrawalSystem {
        address withdrawalRequest;
        address withdrawer;
        address bagFactory;
        address requestPolicy;
    }

    IRegistry public immutable REGISTRY;

    constructor(IRegistry registry) {
        if (address(registry) == address(0)) revert ZeroAddress();
        REGISTRY = registry;
    }

    function createVault(VaultParams calldata params, FlexStrategyParams calldata flexParams)
        external
        returns (CreatedVault memory created)
    {
        _validateVaultParams(params);

        TimelockController timelock = TimelockDeployer.deploy(params.admin, params.timelockDuration);
        address vaultLogic = _registryValue(RegistryKeys.VAULT);
        Assets memory assets = _prepareAssets(params, address(timelock));

        created.timelock = address(timelock);
        created.wrappedToken = assets.wrappedToken;
        created.vault = address(new UninitializedTransparentUpgradeableProxy(vaultLogic, address(timelock)));

        IVault vault = IVault(created.vault);
        _initializeVault(vault, params, assets);
        _configureVault(vault, params, assets, address(timelock));

        WithdrawalSystem memory withdrawals = _deployWithdrawalSystem(vault, params, address(timelock));
        created.withdrawalRequest = withdrawals.withdrawalRequest;
        created.withdrawer = withdrawals.withdrawer;
        created.bagFactory = withdrawals.bagFactory;
        created.requestPolicy = withdrawals.requestPolicy;

        if (flexParams.deployStrategy) {
            // TODO: Deploy and configure the flex strategy once its deployment API is finalized.
            // TODO: Deploy and configure the flex strategy SafeGuard once its deployment API is finalized.
            revert FunctionalityUnavailable();
        }

        _bootstrap(vault, params);
        _renounceTemporaryRoles(vault);

        emit VaultCreated(
            msg.sender,
            created.vault,
            created.timelock,
            created.wrappedToken,
            created.withdrawalRequest,
            created.withdrawer,
            created.bagFactory,
            created.requestPolicy,
            created.safeGuard,
            created.flexStrategy
        );
    }

    function _initializeVault(IVault vault, VaultParams calldata params, Assets memory assets) internal {
        vault.initialize(
            address(this),
            params.tokenName,
            params.tokenSymbol,
            VAULT_DECIMALS,
            BASE_WITHDRAWAL_FEE,
            params.countNativeAsset,
            params.alwaysComputeTotalAssets,
            assets.defaultAssetIndex
        );
    }

    function _validateVaultParams(VaultParams calldata params) internal view {
        if (
            params.admin == address(0) || params.processor == address(0) || params.pauser == address(0)
                || params.unpauser == address(0) || params.feeManager == address(0) || params.baseAsset == address(0)
                || params.resolver == address(0) || params.defaultAsset == address(0)
                || params.provider == address(0) || params.bootstrapReceiver == address(0)
        ) {
            revert ZeroAddress();
        }

        if (params.bootstrapAmount == 0) revert ZeroAmount();
        uint8 baseAssetDecimals = IERC20Metadata(params.baseAsset).decimals();
        if (baseAssetDecimals > VAULT_DECIMALS) revert AssetDecimalsTooHigh(baseAssetDecimals);
        if (baseAssetDecimals == VAULT_DECIMALS && params.baseAsset != params.defaultAsset) {
            revert InvalidDefaultAsset();
        }
        if (params.baseAsset != params.defaultAsset && IERC20Metadata(params.defaultAsset).decimals() > VAULT_DECIMALS)
        {
            revert InvalidDefaultAsset();
        }
    }

    function _prepareAssets(VaultParams calldata params, address timelock) internal returns (Assets memory assets) {
        uint8 baseAssetDecimals = IERC20Metadata(params.baseAsset).decimals();
        assets.defaultAsset = params.defaultAsset;

        if (baseAssetDecimals == VAULT_DECIMALS) {
            assets.baseAsset = params.baseAsset;
        } else {
            assets.wrappedToken = _deployWrappedToken(params.baseAsset, baseAssetDecimals, timelock);
            assets.baseAsset = assets.wrappedToken;
        }

        assets.defaultAssetIndex = assets.baseAsset == assets.defaultAsset ? 0 : 1;
    }

    function _deployWrappedToken(address underlying, uint8 underlyingDecimals, address timelock)
        internal
        returns (address wrappedToken)
    {
        wrappedToken = address(
            new UninitializedTransparentUpgradeableProxy(_registryValue(RegistryKeys.WRAPPED_TOKEN), timelock)
        );
        IWrappedToken(wrappedToken)
            .initialize(
                IERC20(underlying),
                _wrappedTokenName(underlying),
                _wrappedTokenSymbol(underlying),
                VAULT_DECIMALS,
                VAULT_DECIMALS - underlyingDecimals
            );
    }

    function _configureVault(IVault vault, VaultParams calldata params, Assets memory assets, address timelock)
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

        vault.addAsset(assets.baseAsset, true);
        if (assets.defaultAssetIndex == 1) {
            vault.addAsset(assets.defaultAsset, true);
        }
        vault.setProvider(params.provider);
        vault.setBuffer(address(0));
    }

    function _deployWithdrawalSystem(IVault vault, VaultParams calldata params, address timelock)
        internal
        returns (WithdrawalSystem memory withdrawals)
    {
        // The withdrawal request proxy is deployed uninitialized first because the withdrawer and
        // the bag factory both need its address during their own initialization.
        withdrawals.withdrawalRequest = address(
            new UninitializedTransparentUpgradeableProxy(_registryValue(RegistryKeys.WITHDRAWAL_REQUEST), timelock)
        );

        withdrawals.withdrawer =
            address(new UninitializedTransparentUpgradeableProxy(_registryValue(RegistryKeys.WITHDRAWER), timelock));
        IWithdrawer(withdrawals.withdrawer).initialize(address(vault), withdrawals.withdrawalRequest);

        withdrawals.bagFactory =
            address(new UninitializedTransparentUpgradeableProxy(_registryValue(RegistryKeys.BAG_FACTORY), timelock));
        IBeaconProxyFactory(withdrawals.bagFactory)
            .initialize(_registryValue(RegistryKeys.BAG), timelock, withdrawals.withdrawalRequest, timelock);

        withdrawals.requestPolicy = address(new MinAmountRequestPolicy(params.minWithdrawalAmount));

        IWithdrawalRequest(withdrawals.withdrawalRequest).initialize(
            address(vault),
            timelock,
            params.resolver,
            timelock,
            params.pauser,
            withdrawals.bagFactory,
            withdrawals.withdrawer,
            withdrawals.requestPolicy,
            params.maxDataLength
        );

        vault.grantRole(vault.ASSET_WITHDRAWER_ROLE(), withdrawals.withdrawer);
    }

    function _bootstrap(IVault vault, VaultParams calldata params) internal {
        IERC20 asset = IERC20(params.defaultAsset);
        asset.safeTransferFrom(msg.sender, address(this), params.bootstrapAmount);
        asset.forceApprove(address(vault), params.bootstrapAmount);
        vault.unpause();
        vault.deposit(params.bootstrapAmount, params.bootstrapReceiver);
        asset.forceApprove(address(vault), 0);
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
        value = REGISTRY.valueOf(key);
        if (value == address(0)) revert MissingRegistryValue(key);
    }

    function _wrappedTokenName(address underlying) internal view returns (string memory) {
        return string.concat("Wrapped ", IERC20Metadata(underlying).name());
    }

    function _wrappedTokenSymbol(address underlying) internal view returns (string memory) {
        return string.concat("W", IERC20Metadata(underlying).symbol());
    }
}

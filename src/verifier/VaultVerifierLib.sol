// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IRequestPolicy} from "lib/yieldnest-vault-withdrawals/src/interface/IRequestPolicy.sol";
import {IAccountingModule} from "src/interfaces/external/IAccountingModule.sol";
import {IAccountingToken} from "src/interfaces/external/IAccountingToken.sol";
import {IBeaconProxyFactory} from "src/interfaces/external/IBeaconProxyFactory.sol";
import {IERC20Metadata} from "src/interfaces/external/IERC20Metadata.sol";
import {IFlexStrategy} from "src/interfaces/external/IFlexStrategy.sol";
import {ISafeGuard} from "src/interfaces/external/ISafeGuard.sol";
import {IVault} from "src/interfaces/external/IVault.sol";
import {IWithdrawalRequest} from "src/interfaces/external/IWithdrawalRequest.sol";
import {IWithdrawer} from "src/interfaces/external/IWithdrawer.sol";
import {IWrappedToken} from "src/interfaces/external/IWrappedToken.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {BaseAssetProvider} from "src/provider/BaseAssetProvider.sol";
import {FlexProvider} from "src/provider/FlexProvider.sol";
import {TimelockVerifierLib} from "src/verifier/TimelockVerifierLib.sol";

library VaultVerifierLib {
    uint8 internal constant VAULT_DECIMALS = 18;
    uint16 internal constant ACCOUNTING_COOLDOWN_SECONDS = 1 hours;
    uint256 internal constant PROVIDER_RATE = 1e18;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 internal constant PROVIDER_MANAGER_ROLE = keccak256("PROVIDER_MANAGER_ROLE");
    bytes32 internal constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    bytes32 internal constant BUFFER_MANAGER_ROLE = keccak256("BUFFER_MANAGER_ROLE");
    bytes32 internal constant PROCESSOR_MANAGER_ROLE = keccak256("PROCESSOR_MANAGER_ROLE");
    bytes32 internal constant ALLOCATOR_MANAGER_ROLE = keccak256("ALLOCATOR_MANAGER_ROLE");
    bytes32 internal constant HOOKS_MANAGER_ROLE = keccak256("HOOKS_MANAGER_ROLE");
    bytes32 internal constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant ACCOUNTING_MODULE_MANAGER_ROLE = keccak256("ACCOUNTING_MODULE_MANAGER_ROLE");
    bytes32 internal constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 internal constant ASSET_WITHDRAWER_ROLE = keccak256("ASSET_WITHDRAWER_ROLE");
    bytes32 internal constant SAFE_MANAGER_ROLE = keccak256("SAFE_MANAGER_ROLE");
    bytes32 internal constant REWARDS_PROCESSOR_ROLE = keccak256("REWARDS_PROCESSOR_ROLE");
    bytes32 internal constant LOSS_PROCESSOR_ROLE = keccak256("LOSS_PROCESSOR_ROLE");
    bytes32 internal constant REWARDS_SWEEPER_ROLE = keccak256("REWARDS_SWEEPER_ROLE");
    bytes32 internal constant SNAPSHOT_REWARDS_SWEEPER_ROLE = keccak256("SNAPSHOT_REWARDS_SWEEPER_ROLE");
    bytes32 internal constant GUARD_ADMIN_ROLE = keccak256("GUARD_ADMIN_ROLE");
    bytes32 internal constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    bytes32 internal constant CONFIGURATION_MANAGER_ROLE = keccak256("CONFIGURATION_MANAGER_ROLE");
    bytes32 internal constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    bytes32 internal constant IMPLEMENTATION_MANAGER_ROLE = keccak256("IMPLEMENTATION_MANAGER_ROLE");

    struct Verification {
        address factory;
        IVaultFactory.CreatedVault created;
        IVaultFactory.VaultParams vaultParams;
        IVaultFactory.FlexStrategyParams flexParams;
    }

    error VerificationFailed(string check);

    function verify(address vault, Verification memory verification) external view returns (bool) {
        _verify(vault == verification.created.vault, "vault mismatch");
        _verify(vault != address(0) && vault.code.length != 0, "vault code");

        uint8 baseAssetDecimals = _decimals(verification.vaultParams.baseAsset);
        address effectiveBaseAsset =
            _effectiveBaseAsset(verification.created, verification.vaultParams, baseAssetDecimals);

        _verifyTimelockRoles(verification);
        _verifyVaultConfig(vault, verification, effectiveBaseAsset, baseAssetDecimals);
        _verifyProvider(verification, effectiveBaseAsset);
        _verifyWithdrawalSystem(verification);

        if (verification.flexParams.deployStrategy) {
            _verifyFlexStrategy(verification);
            _verifySafeGuard(verification);
            _verifyHooks(verification);
        } else {
            _verifyNoFlexComponents(verification.created);
        }

        return true;
    }

    function _verifyVaultConfig(
        address vaultAddress,
        Verification memory verification,
        address effectiveBaseAsset,
        uint8 baseAssetDecimals
    ) internal view {
        IVaultView vault = IVaultView(vaultAddress);
        IVaultFactory.CreatedVault memory created = verification.created;
        IVaultFactory.VaultParams memory params = verification.vaultParams;

        _verifyString(vault.name(), params.tokenName, "vault name");
        _verifyString(vault.symbol(), params.tokenSymbol, "vault symbol");
        _verify(_decimals(address(vault)) == VAULT_DECIMALS, "vault decimals");
        _verify(vault.asset() == params.baseAsset, "vault asset");
        _verify(vault.countNativeAsset() == params.countNativeAsset, "vault native asset");
        _verify(vault.alwaysComputeTotalAssets() == params.alwaysComputeTotalAssets, "vault accounting mode");
        _verify(vault.baseWithdrawalFee() == 0, "vault withdrawal fee");
        _verify(vault.defaultAssetIndex() == _defaultAssetIndex(baseAssetDecimals), "vault default index");
        _verify(vault.provider() == created.provider, "vault provider");
        _verify(vault.buffer() == address(0), "vault buffer");
        _verify(!vault.paused(), "vault paused");

        address[] memory assets = vault.getAssets();
        if (baseAssetDecimals == VAULT_DECIMALS) {
            _verify(assets.length == 1, "vault assets length");
            _verify(assets[0] == params.baseAsset, "vault base asset");
            _verify(created.wrappedToken == address(0), "unexpected wrapper");
        } else {
            _verify(assets.length >= 2, "vault wrapped assets length");
            _verify(assets[0] == effectiveBaseAsset, "vault wrapper asset");
            _verify(assets[1] == params.baseAsset, "vault default asset");
            _verifyWrappedToken(created.wrappedToken, params.baseAsset, baseAssetDecimals);
        }

        if (verification.flexParams.deployStrategy) {
            _verify(assets.length == (baseAssetDecimals == VAULT_DECIMALS ? 2 : 3), "vault flex assets length");
            _verify(assets[assets.length - 1] == created.flexStrategy, "vault strategy asset");
            _verifyVaultStrategyRules(vault, params.baseAsset, created.flexStrategy, vaultAddress);
        }

        _verifyVaultRoles(vault, verification);
    }

    function _verifyProvider(Verification memory verification, address effectiveBaseAsset) internal view {
        IVaultFactory.CreatedVault memory created = verification.created;
        IVaultFactory.VaultParams memory params = verification.vaultParams;

        _verify(created.provider != address(0) && created.provider.code.length != 0, "provider code");

        if (verification.flexParams.deployStrategy) {
            FlexProvider provider = FlexProvider(created.provider);
            _verify(provider.baseAsset() == effectiveBaseAsset, "flex provider base");
            _verify(provider.defaultAsset() == params.baseAsset, "flex provider default");
            _verify(provider.strategy() == created.flexStrategy, "flex provider strategy");
            _verify(provider.getRate(effectiveBaseAsset) == PROVIDER_RATE, "flex provider base rate");
            _verify(provider.getRate(params.baseAsset) == PROVIDER_RATE, "flex provider default rate");
        } else {
            BaseAssetProvider provider = BaseAssetProvider(created.provider);
            _verify(provider.baseAsset() == effectiveBaseAsset, "provider base");
            _verify(provider.defaultAsset() == params.baseAsset, "provider default");
            _verify(provider.rate() == PROVIDER_RATE, "provider rate");
            _verify(provider.getRate(effectiveBaseAsset) == PROVIDER_RATE, "provider base rate");
            _verify(provider.getRate(params.baseAsset) == PROVIDER_RATE, "provider default rate");
        }
    }

    function _verifyWithdrawalSystem(Verification memory verification) internal view {
        IVaultFactory.CreatedVault memory created = verification.created;
        IVaultFactory.VaultParams memory params = verification.vaultParams;
        IRegistry registry = IVaultFactoryView(verification.factory).REGISTRY();

        IWithdrawalRequestView request = IWithdrawalRequestView(created.withdrawalRequest);
        _verify(created.withdrawalRequest.code.length != 0, "request code");
        _verify(address(request.token()) == created.vault, "request token");
        _verify(address(request.bagFactory()) == created.bagFactory, "request bag factory");
        _verify(address(request.withdrawer()) == created.withdrawer, "request withdrawer");
        _verify(address(request.requestPolicy()) == created.requestPolicy, "request policy");
        _verify(request.maxDataLength() == params.maxDataLength, "request data length");
        _verifyRole(request, DEFAULT_ADMIN_ROLE, created.timelock, true, "request admin");
        _verifyRole(request, RESOLVER_ROLE, params.resolver, true, "request resolver");
        _verifyRole(request, CONFIGURATION_MANAGER_ROLE, created.timelock, true, "request config");
        _verifyRole(request, PAUSER_ROLE, params.pauser, true, "request pauser");
        _verifyRole(request, PAUSER_ROLE, params.admin, true, "request admin pauser");
        _verifyRole(request, DEFAULT_ADMIN_ROLE, verification.factory, false, "request dangling admin");
        _verifyRole(request, CONFIGURATION_MANAGER_ROLE, verification.factory, false, "request dangling config");

        IWithdrawerView withdrawer = IWithdrawerView(created.withdrawer);
        _verify(created.withdrawer.code.length != 0, "withdrawer code");
        _verify(address(withdrawer.token()) == created.vault, "withdrawer token");
        _verify(withdrawer.withdrawalRequest() == created.withdrawalRequest, "withdrawer request");

        IBeaconProxyFactoryView bagFactory = IBeaconProxyFactoryView(created.bagFactory);
        _verify(created.bagFactory.code.length != 0, "bag factory code");
        _verify(bagFactory.implementation() == registry.valueOf(RegistryKeys.BAG), "bag implementation");
        _verifyRole(bagFactory, DEFAULT_ADMIN_ROLE, created.timelock, true, "bag admin");
        _verifyRole(bagFactory, CREATOR_ROLE, created.withdrawalRequest, true, "bag creator");
        _verifyRole(bagFactory, IMPLEMENTATION_MANAGER_ROLE, created.timelock, true, "bag implementation manager");
        _verifyRole(bagFactory, DEFAULT_ADMIN_ROLE, verification.factory, false, "bag dangling admin");

        _verify(
            IRequestPolicyView(created.requestPolicy).minWithdrawalAmount() == params.minWithdrawalAmount,
            "request min amount"
        );
        _verifyRole(IVaultView(created.vault), ASSET_WITHDRAWER_ROLE, created.withdrawer, true, "vault withdrawer role");
    }

    function _verifyFlexStrategy(Verification memory verification) internal view {
        IVaultFactory.CreatedVault memory created = verification.created;
        IVaultFactory.VaultParams memory vaultParams = verification.vaultParams;
        IVaultFactory.FlexStrategyParams memory flexParams = verification.flexParams;

        IFlexStrategyView strategy = IFlexStrategyView(created.flexStrategy);
        _verify(created.flexStrategy.code.length != 0, "strategy code");
        _verifyString(strategy.name(), flexParams.strategyName, "strategy name");
        _verifyString(strategy.symbol(), flexParams.strategySymbol, "strategy symbol");
        _verify(_decimals(address(strategy)) == _decimals(vaultParams.baseAsset), "strategy decimals");
        _verify(strategy.asset() == vaultParams.baseAsset, "strategy asset");
        _verify(address(strategy.accountingModule()) == created.accountingModule, "strategy module");
        _verify(address(strategy.hooks()) == created.accountingModuleHook, "strategy hooks");
        _verify(strategy.alwaysComputeTotalAssets() == flexParams.alwaysComputeTotalAssets, "strategy accounting mode");
        _verify(!strategy.paused(), "strategy paused");
        _verify(strategy.getHasAllocator(), "strategy allocator flag");

        _verifyStrategyRoles(strategy, verification);
        _verifyStrategyRules(strategy, created.accountingModule, created.flexStrategy);
        _verifyAccountingSystem(verification);
    }

    function _verifyAccountingSystem(Verification memory verification) internal view {
        IVaultFactory.CreatedVault memory created = verification.created;
        IVaultFactory.VaultParams memory vaultParams = verification.vaultParams;
        IVaultFactory.FlexStrategyParams memory flexParams = verification.flexParams;

        IAccountingTokenView accountingToken = IAccountingTokenView(created.accountingToken);
        _verify(created.accountingToken.code.length != 0, "accounting token code");
        _verify(accountingToken.TRACKED_ASSET() == vaultParams.baseAsset, "accounting token asset");
        _verify(_decimals(address(accountingToken)) == _decimals(vaultParams.baseAsset), "accounting token decimals");
        _verify(accountingToken.accountingModule() == created.accountingModule, "accounting token module");
        _verifyRole(accountingToken, DEFAULT_ADMIN_ROLE, created.timelock, true, "accounting token admin");
        _verifyRole(accountingToken, ACCOUNTING_MODULE_MANAGER_ROLE, created.timelock, true, "accounting token manager");
        _verifyRole(accountingToken, DEFAULT_ADMIN_ROLE, verification.factory, false, "accounting token dangling admin");
        _verifyRole(
            accountingToken,
            ACCOUNTING_MODULE_MANAGER_ROLE,
            verification.factory,
            false,
            "accounting token dangling manager"
        );

        IAccountingModuleView accountingModule = IAccountingModuleView(created.accountingModule);
        _verify(created.accountingModule.code.length != 0, "accounting module code");
        _verify(accountingModule.strategy() == created.flexStrategy, "accounting module strategy");
        _verify(accountingModule.baseAsset() == vaultParams.baseAsset, "accounting module asset");
        _verify(address(accountingModule.accountingToken()) == created.accountingToken, "accounting module token");
        _verify(accountingModule.safe() == flexParams.multisig, "accounting module safe");
        _verify(accountingModule.targetApy() == flexParams.targetApy, "accounting target apy");
        _verify(accountingModule.lowerBound() == flexParams.lowerBound, "accounting lower bound");
        _verify(accountingModule.cooldownSeconds() == ACCOUNTING_COOLDOWN_SECONDS, "accounting cooldown");
        _verifyRole(accountingModule, DEFAULT_ADMIN_ROLE, created.timelock, true, "accounting module admin");
        _verifyRole(accountingModule, SAFE_MANAGER_ROLE, created.timelock, true, "accounting module safe manager");
        _verifyRole(
            accountingModule,
            REWARDS_PROCESSOR_ROLE,
            flexParams.accountingProcessor,
            true,
            "accounting rewards processor"
        );
        _verifyRole(accountingModule, LOSS_PROCESSOR_ROLE, flexParams.lossProcessor, true, "accounting loss processor");
        _verifyRole(
            accountingModule, DEFAULT_ADMIN_ROLE, verification.factory, false, "accounting module dangling admin"
        );

        if (created.rewardsSweeper != address(0)) {
            IRewardsSweeperView sweeper = IRewardsSweeperView(created.rewardsSweeper);
            _verify(sweeper.accountingModule() == created.accountingModule, "sweeper module");
            _verifyRole(sweeper, DEFAULT_ADMIN_ROLE, created.timelock, true, "sweeper admin");
            _verifyRole(sweeper, ACCOUNTING_MODULE_MANAGER_ROLE, created.timelock, true, "sweeper manager");
            _verifyRole(sweeper, REWARDS_SWEEPER_ROLE, vaultParams.processor, true, "sweeper role");
            _verifyRole(sweeper, SNAPSHOT_REWARDS_SWEEPER_ROLE, vaultParams.processor, true, "sweeper snapshot role");
            _verifyRole(
                accountingModule, REWARDS_PROCESSOR_ROLE, created.rewardsSweeper, true, "sweeper rewards processor"
            );
            _verifyRole(sweeper, DEFAULT_ADMIN_ROLE, verification.factory, false, "sweeper dangling admin");
            _verifyRole(
                sweeper, ACCOUNTING_MODULE_MANAGER_ROLE, verification.factory, false, "sweeper dangling manager"
            );
        } else {
            _verify(!flexParams.deployRewardsSweeper, "missing sweeper");
        }
    }

    function _verifySafeGuard(Verification memory verification) internal view {
        IVaultFactory.CreatedVault memory created = verification.created;
        IVaultFactory.VaultParams memory vaultParams = verification.vaultParams;
        IVaultFactory.FlexStrategyParams memory flexParams = verification.flexParams;

        ISafeGuardView safeGuard = ISafeGuardView(created.safeGuard);
        _verify(created.safeGuard.code.length != 0, "safeguard code");
        _verifyString(safeGuard.name(), string.concat(flexParams.strategyName, " Safeguard"), "safeguard name");
        _verifyRole(safeGuard, DEFAULT_ADMIN_ROLE, created.timelock, true, "safeguard admin");
        _verifyRole(safeGuard, PROCESSOR_MANAGER_ROLE, created.timelock, true, "safeguard processor manager");
        _verifyRole(safeGuard, GUARD_ADMIN_ROLE, created.timelock, true, "safeguard guard admin");
        _verifyRole(safeGuard, DEFAULT_ADMIN_ROLE, verification.factory, false, "safeguard dangling admin");
        _verifyRole(
            safeGuard, PROCESSOR_MANAGER_ROLE, verification.factory, false, "safeguard dangling processor manager"
        );
        _verifyRole(safeGuard, GUARD_ADMIN_ROLE, verification.factory, false, "safeguard dangling guard admin");

        ISafeGuard.FunctionRule memory rule =
            safeGuard.getProcessorRule(vaultParams.baseAsset, IERC20.transfer.selector);
        _verify(rule.isActive, "safeguard transfer inactive");
        _verify(rule.validator == address(0), "safeguard transfer validator");
        _verify(rule.paramRules.length == 2, "safeguard transfer params");
        _verifyAddressParam(rule.paramRules[0], flexParams.offRampAddress, "safeguard transfer recipient");
        _verifyUintParam(rule.paramRules[1], "safeguard transfer amount");
    }

    function _verifyHooks(Verification memory verification) internal view {
        IVaultFactory.CreatedVault memory created = verification.created;
        IAccountingModuleHookView hook = IAccountingModuleHookView(created.accountingModuleHook);

        _verify(created.accountingModuleHook.code.length != 0, "hook code");
        _verify(address(hook.VAULT()) == created.flexStrategy, "hook vault");
        _verify(address(hook.flexStrategy()) == created.flexStrategy, "hook strategy");
        _verify(address(hook.accountingModule()) == created.accountingModule, "hook module");
    }

    function _verifyNoFlexComponents(IVaultFactory.CreatedVault memory created) internal pure {
        _verify(created.safeGuard == address(0), "unexpected safeguard");
        _verify(created.accountingModuleHook == address(0), "unexpected hook");
        _verify(created.flexStrategy == address(0), "unexpected strategy");
        _verify(created.accountingToken == address(0), "unexpected accounting token");
        _verify(created.accountingModule == address(0), "unexpected accounting module");
        _verify(created.rewardsSweeper == address(0), "unexpected sweeper");
    }

    function _verifyVaultRoles(IVaultView vault, Verification memory verification) internal view {
        IVaultFactory.CreatedVault memory created = verification.created;
        IVaultFactory.VaultParams memory params = verification.vaultParams;
        address factory = verification.factory;

        _verifyRole(vault, DEFAULT_ADMIN_ROLE, created.timelock, true, "vault admin role");
        _verifyRole(vault, PROCESSOR_ROLE, params.processor, true, "vault processor role");
        _verifyRole(vault, PAUSER_ROLE, params.pauser, true, "vault pauser role");
        _verifyRole(vault, UNPAUSER_ROLE, params.unpauser, true, "vault unpauser role");
        _verifyRole(vault, PAUSER_ROLE, params.admin, true, "vault admin pauser role");
        _verifyRole(vault, UNPAUSER_ROLE, params.admin, true, "vault admin unpauser role");
        _verifyRole(vault, FEE_MANAGER_ROLE, params.feeManager, true, "vault fee role");
        _verifyRole(vault, PROVIDER_MANAGER_ROLE, created.timelock, true, "vault provider role");
        _verifyRole(vault, BUFFER_MANAGER_ROLE, created.timelock, true, "vault buffer role");
        _verifyRole(vault, ASSET_MANAGER_ROLE, created.timelock, true, "vault asset role");
        _verifyRole(vault, PROCESSOR_MANAGER_ROLE, created.timelock, true, "vault processor manager role");
        _verifyRole(vault, HOOKS_MANAGER_ROLE, created.timelock, true, "vault hooks role");

        _verifyRole(vault, DEFAULT_ADMIN_ROLE, factory, false, "vault dangling admin");
        _verifyRole(vault, PROVIDER_MANAGER_ROLE, factory, false, "vault dangling provider");
        _verifyRole(vault, BUFFER_MANAGER_ROLE, factory, false, "vault dangling buffer");
        _verifyRole(vault, ASSET_MANAGER_ROLE, factory, false, "vault dangling asset");
        _verifyRole(vault, PROCESSOR_MANAGER_ROLE, factory, false, "vault dangling processor manager");
        _verifyRole(vault, HOOKS_MANAGER_ROLE, factory, false, "vault dangling hooks");
        _verifyRole(vault, UNPAUSER_ROLE, factory, false, "vault dangling unpauser");
    }

    function _verifyTimelockRoles(Verification memory verification) internal view {
        IVaultFactory.CreatedVault memory created = verification.created;
        IVaultFactory.VaultParams memory params = verification.vaultParams;
        TimelockVerifierLib.verify(created.timelock, params.admin, params.proposer, verification.factory);
    }

    function _verifyStrategyRoles(IFlexStrategyView strategy, Verification memory verification) internal view {
        IVaultFactory.CreatedVault memory created = verification.created;
        IVaultFactory.VaultParams memory params = verification.vaultParams;
        address factory = verification.factory;

        _verifyRole(strategy, DEFAULT_ADMIN_ROLE, created.timelock, true, "strategy admin role");
        _verifyRole(strategy, PROCESSOR_ROLE, params.processor, true, "strategy processor role");
        _verifyRole(strategy, PAUSER_ROLE, params.pauser, true, "strategy pauser role");
        _verifyRole(strategy, UNPAUSER_ROLE, params.unpauser, true, "strategy unpauser role");
        _verifyRole(strategy, PAUSER_ROLE, params.admin, true, "strategy admin pauser role");
        _verifyRole(strategy, UNPAUSER_ROLE, params.admin, true, "strategy admin unpauser role");
        _verifyRole(strategy, PROVIDER_MANAGER_ROLE, created.timelock, true, "strategy provider role");
        _verifyRole(strategy, ASSET_MANAGER_ROLE, created.timelock, true, "strategy asset role");
        _verifyRole(strategy, BUFFER_MANAGER_ROLE, created.timelock, true, "strategy buffer role");
        _verifyRole(strategy, PROCESSOR_MANAGER_ROLE, created.timelock, true, "strategy processor manager role");
        _verifyRole(strategy, ALLOCATOR_MANAGER_ROLE, created.timelock, true, "strategy allocator manager role");
        _verifyRole(strategy, HOOKS_MANAGER_ROLE, created.timelock, true, "strategy hooks role");
        _verifyRole(strategy, ACCOUNTING_MODULE_MANAGER_ROLE, created.timelock, true, "strategy module manager role");
        _verifyRole(strategy, ALLOCATOR_ROLE, created.vault, true, "strategy allocator role");
        _verifyRole(strategy, PROCESSOR_ROLE, created.accountingModuleHook, true, "strategy hook processor role");

        _verifyRole(strategy, DEFAULT_ADMIN_ROLE, factory, false, "strategy dangling admin");
        _verifyRole(strategy, PROCESSOR_MANAGER_ROLE, factory, false, "strategy dangling processor manager");
        _verifyRole(strategy, ALLOCATOR_MANAGER_ROLE, factory, false, "strategy dangling allocator manager");
        _verifyRole(strategy, ALLOCATOR_ROLE, factory, false, "strategy dangling allocator");
        _verifyRole(strategy, HOOKS_MANAGER_ROLE, factory, false, "strategy dangling hooks");
        _verifyRole(strategy, UNPAUSER_ROLE, factory, false, "strategy dangling unpauser");
        _verifyRole(strategy, ACCOUNTING_MODULE_MANAGER_ROLE, factory, false, "strategy dangling module manager");
    }

    function _verifyVaultStrategyRules(IVaultView vault, address baseAsset, address strategy, address expectedVault)
        internal
        view
    {
        _verifyRule2(
            _getRule(address(vault), baseAsset, IERC20.approve.selector), strategy, address(0), "vault approve rule"
        );
        _verifyRule2(
            _getRule(address(vault), strategy, bytes4(keccak256("deposit(uint256,address)"))),
            address(0),
            expectedVault,
            "vault strategy deposit rule"
        );
        _verifyRule2(
            _getRule(address(vault), strategy, bytes4(keccak256("mint(uint256,address)"))),
            address(0),
            expectedVault,
            "vault strategy mint rule"
        );
        _verifyRule3(
            _getRule(address(vault), strategy, bytes4(keccak256("withdraw(uint256,address,address)"))),
            expectedVault,
            expectedVault,
            "vault strategy withdraw rule"
        );
        _verifyRule3(
            _getRule(address(vault), strategy, bytes4(keccak256("redeem(uint256,address,address)"))),
            expectedVault,
            expectedVault,
            "vault strategy redeem rule"
        );
    }

    function _verifyStrategyRules(IFlexStrategyView strategy, address accountingModule, address expectedStrategy)
        internal
        view
    {
        _verifyRule1(
            _getRule(address(strategy), accountingModule, bytes4(keccak256("deposit(uint256)"))),
            "strategy module deposit rule"
        );
        _verifyRule2(
            _getRule(address(strategy), accountingModule, bytes4(keccak256("withdraw(uint256,address)"))),
            address(0),
            expectedStrategy,
            "strategy module withdraw rule"
        );
    }

    function _getRule(address target, address asset, bytes4 selector)
        internal
        view
        returns (IVault.FunctionRule memory)
    {
        return IVaultView(target).getProcessorRule(asset, selector);
    }

    function _verifyRule1(IVault.FunctionRule memory rule, string memory check) internal pure {
        _verify(rule.isActive, check);
        _verify(rule.validator == address(0), check);
        _verify(rule.paramRules.length == 1, check);
        _verifyUintParam(rule.paramRules[0], check);
    }

    function _verifyRule2(IVault.FunctionRule memory rule, address p0Allowed, address p1Allowed, string memory check)
        internal
        pure
    {
        _verify(rule.isActive, check);
        _verify(rule.validator == address(0), check);
        _verify(rule.paramRules.length == 2, check);
        if (p0Allowed == address(0)) _verifyUintParam(rule.paramRules[0], check);
        else _verifyAddressParam(rule.paramRules[0], p0Allowed, check);
        if (p1Allowed == address(0)) _verifyUintParam(rule.paramRules[1], check);
        else _verifyAddressParam(rule.paramRules[1], p1Allowed, check);
    }

    function _verifyRule3(IVault.FunctionRule memory rule, address p1Allowed, address p2Allowed, string memory check)
        internal
        pure
    {
        _verify(rule.isActive, check);
        _verify(rule.validator == address(0), check);
        _verify(rule.paramRules.length == 3, check);
        _verifyUintParam(rule.paramRules[0], check);
        _verifyAddressParam(rule.paramRules[1], p1Allowed, check);
        _verifyAddressParam(rule.paramRules[2], p2Allowed, check);
    }

    function _verifyAddressParam(IVault.ParamRule memory param, address allowed, string memory check) internal pure {
        _verify(uint256(param.paramType) == uint256(IVault.ParamType.ADDRESS), check);
        _verify(!param.isArray, check);
        _verify(param.allowList.length == 1, check);
        _verify(param.allowList[0] == allowed, check);
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

    function _verifyUintParam(IVault.ParamRule memory param, string memory check) internal pure {
        _verify(uint256(param.paramType) == uint256(IVault.ParamType.UINT256), check);
        _verify(!param.isArray, check);
        _verify(param.allowList.length == 0, check);
    }

    function _verifyUintParam(ISafeGuard.ParamRule memory param, string memory check) internal pure {
        _verify(uint256(param.paramType) == uint256(ISafeGuard.ParamType.UINT256), check);
        _verify(!param.isArray, check);
        _verify(param.allowList.length == 0, check);
    }

    function _verifyWrappedToken(address wrappedToken, address underlying, uint8 underlyingDecimals) internal view {
        IWrappedTokenView wrapper = IWrappedTokenView(wrappedToken);
        _verify(wrappedToken != address(0) && wrappedToken.code.length != 0, "wrapper code");
        _verify(wrapper.asset() == underlying, "wrapper asset");
        _verify(_decimals(address(wrapper)) == VAULT_DECIMALS, "wrapper decimals");
        _verify(wrapper.decimalsOffset() == VAULT_DECIMALS - underlyingDecimals, "wrapper offset");
    }

    function _effectiveBaseAsset(
        IVaultFactory.CreatedVault memory created,
        IVaultFactory.VaultParams memory params,
        uint8 baseAssetDecimals
    ) internal pure returns (address) {
        return baseAssetDecimals == VAULT_DECIMALS ? params.baseAsset : created.wrappedToken;
    }

    function _defaultAssetIndex(uint8 baseAssetDecimals) internal pure returns (uint256) {
        return baseAssetDecimals == VAULT_DECIMALS ? 0 : 1;
    }

    function _decimals(address target) internal view returns (uint8) {
        return IERC20Metadata(target).decimals();
    }

    function _verifyString(string memory actual, string memory expected, string memory check) internal pure {
        _verify(keccak256(bytes(actual)) == keccak256(bytes(expected)), check);
    }

    // Share the external call and ABI decoding across all role checks.
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

interface IVaultFactoryView {
    function REGISTRY() external view returns (IRegistry);
}

interface IAccessControlView {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IVaultView is IVault, IAccessControlView {}

interface IFlexStrategyView is IFlexStrategy, IAccessControlView {}

interface IAccountingTokenView is IAccountingToken, IAccessControlView {}

interface IAccountingModuleView is IAccountingModule, IAccessControlView {}

interface IRewardsSweeperView is IAccessControlView {
    function accountingModule() external view returns (address);
}

interface ISafeGuardView is ISafeGuard, IAccessControlView {
    function name() external view returns (string memory);
}

interface IAccountingModuleHookView {
    function VAULT() external view returns (address);
    function flexStrategy() external view returns (address);
    function accountingModule() external view returns (address);
}

interface IWrappedTokenView is IWrappedToken {}

interface IWithdrawalRequestView is IWithdrawalRequest, IAccessControlView {}

interface IWithdrawerView is IWithdrawer {}

interface IBeaconProxyFactoryView is IBeaconProxyFactory, IAccessControlView {}

interface IRequestPolicyView is IRequestPolicy {}

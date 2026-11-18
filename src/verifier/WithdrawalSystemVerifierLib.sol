// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IVault} from "src/interfaces/external/IVault.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IRequestPolicy} from "lib/yieldnest-vault-withdrawals/src/interface/IRequestPolicy.sol";
import {IBeaconProxyFactory} from "src/interfaces/external/IBeaconProxyFactory.sol";
import {IWithdrawalRequest} from "src/interfaces/external/IWithdrawalRequest.sol";
import {IWithdrawer} from "src/interfaces/external/IWithdrawer.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";

library WithdrawalSystemVerifierLib {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant ASSET_WITHDRAWER_ROLE = keccak256("ASSET_WITHDRAWER_ROLE");
    bytes32 internal constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    bytes32 internal constant CONFIGURATION_MANAGER_ROLE = keccak256("CONFIGURATION_MANAGER_ROLE");
    bytes32 internal constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    bytes32 internal constant IMPLEMENTATION_MANAGER_ROLE = keccak256("IMPLEMENTATION_MANAGER_ROLE");

    error VerificationFailed(string check);

    function verify(address factory, IVaultFactory.CreatedVault memory created, IVaultFactory.VaultParams memory params)
        external
        view
    {
        IRegistry registry = IVaultFactoryView(factory).REGISTRY();

        IWithdrawalRequestView request = IWithdrawalRequestView(created.withdrawalRequest);
        _verify(created.withdrawalRequest.code.length != 0, "request code");
        _verify(address(request.token()) == created.vault, "request token");
        _verify(address(request.bagFactory()) == created.bagFactory, "request bag factory");
        _verify(address(request.withdrawer()) == created.withdrawer, "request withdrawer");
        _verify(address(request.requestPolicy()) == created.requestPolicy, "request policy");
        _verify(request.maxDataLength() == params.maxDataLength, "request data length");
        _verifyRole(request, DEFAULT_ADMIN_ROLE, created.timelock, true, "request admin");
        _verifyRole(request, DEFAULT_ADMIN_ROLE, params.admin, true, "request external admin");
        _verifyRole(request, RESOLVER_ROLE, params.resolver, true, "request resolver");
        _verifyRole(request, CONFIGURATION_MANAGER_ROLE, created.timelock, true, "request config");
        _verifyRole(request, PAUSER_ROLE, params.pauser, true, "request pauser");
        _verifyRole(request, PAUSER_ROLE, params.admin, true, "request admin pauser");
        _verifyRole(request, DEFAULT_ADMIN_ROLE, factory, false, "request dangling admin");
        _verifyRole(request, CONFIGURATION_MANAGER_ROLE, factory, false, "request dangling config");

        IWithdrawerView withdrawer = IWithdrawerView(created.withdrawer);
        _verify(created.withdrawer.code.length != 0, "withdrawer code");
        _verify(address(withdrawer.token()) == created.vault, "withdrawer token");
        _verify(withdrawer.withdrawalRequest() == created.withdrawalRequest, "withdrawer request");

        IBeaconProxyFactoryView bagFactory = IBeaconProxyFactoryView(created.bagFactory);
        _verify(created.bagFactory.code.length != 0, "bag factory code");
        _verify(bagFactory.implementation() == registry.valueOf(RegistryKeys.BAG), "bag implementation");
        _verifyRole(bagFactory, DEFAULT_ADMIN_ROLE, created.timelock, true, "bag admin");
        _verifyRole(bagFactory, DEFAULT_ADMIN_ROLE, params.admin, true, "bag external admin");
        _verifyRole(bagFactory, CREATOR_ROLE, created.withdrawalRequest, true, "bag creator");
        _verifyRole(bagFactory, IMPLEMENTATION_MANAGER_ROLE, created.timelock, true, "bag implementation manager");
        _verifyRole(bagFactory, DEFAULT_ADMIN_ROLE, factory, false, "bag dangling admin");

        _verify(
            IRequestPolicyView(created.requestPolicy).minWithdrawalAmount() == params.minWithdrawalAmount,
            "request min amount"
        );
        _verifyRole(IVaultView(created.vault), ASSET_WITHDRAWER_ROLE, created.withdrawer, true, "vault withdrawer role");
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

interface IWithdrawalRequestView is IWithdrawalRequest, IAccessControlView {}

interface IWithdrawerView is IWithdrawer {}

interface IBeaconProxyFactoryView is IBeaconProxyFactory, IAccessControlView {}

interface IRequestPolicyView is IRequestPolicy {}

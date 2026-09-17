// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {Registry} from "src/Registry.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {VaultFactory} from "src/VaultFactory.sol";
import {RegistryImplementations} from "script/RegistryImplementations.sol";
import {TestConstants} from "test/lib/TestConstants.sol";

interface IRoleAccessControl {
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

contract VaultFactoryRolesIntegrationTest is Test {
    uint256 private constant BOOTSTRAP_AMOUNT = 1e6;
    address private constant ADMIN_ROLE_RECIPIENT = 0x10000000000000000000000000000000000000A1;
    address private constant TIMELOCK_ROLE_RECIPIENT = 0x10000000000000000000000000000000000000A2;

    bytes32 private constant PROVIDER_MANAGER_ROLE = keccak256("PROVIDER_MANAGER_ROLE");
    bytes32 private constant HOOK_MANAGER_ROLE = keccak256("HOOK_MANAGER_ROLE");
    bytes32 private constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 private constant CONFIGURATION_MANAGER_ROLE = keccak256("CONFIGURATION_MANAGER_ROLE");
    bytes32 private constant IMPLEMENTATION_MANAGER_ROLE = keccak256("IMPLEMENTATION_MANAGER_ROLE");
    bytes32 private constant PROCESSOR_MANAGER_ROLE = keccak256("PROCESSOR_MANAGER_ROLE");
    bytes32 private constant ACCOUNTING_MODULE_MANAGER_ROLE = keccak256("ACCOUNTING_MODULE_MANAGER_ROLE");
    bytes32 private constant SAFE_MANAGER_ROLE = keccak256("SAFE_MANAGER_ROLE");
    bytes32 private constant GUARD_ADMIN_ROLE = keccak256("GUARD_ADMIN_ROLE");

    IRegistry private registry;
    VaultFactory private factory;
    IVaultFactory.CreatedVault private created;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("eth_mainnet"));

        registry = _deployRegistry();
        _populateRegistry();
        factory = new VaultFactory(registry);

        deal(TestConstants.USDC, TestConstants.CREATOR, BOOTSTRAP_AMOUNT * 2);

        vm.startPrank(TestConstants.CREATOR);
        IERC20(TestConstants.USDC).approve(address(factory), BOOTSTRAP_AMOUNT * 2);
        created = factory.createVault(_vaultParams(), _flexParams(), _hooksConfig());
        vm.stopPrank();
    }

    function test_Admin_And_Timelock_Can_Change_Roles_On_Deployed_Contracts() public {
        _assertAdminAndTimelockCanChangeRole(created.vault, PROVIDER_MANAGER_ROLE, "vault");
        _assertAdminAndTimelockCanChangeRole(created.metaHooks, HOOK_MANAGER_ROLE, "meta hooks");
        _assertAdminAndTimelockCanChangeRole(created.pauserHook, PAUSER_ROLE, "pauser hook");
        _assertAdminAndTimelockCanChangeRole(created.withdrawalRequest, CONFIGURATION_MANAGER_ROLE, "request");
        _assertAdminAndTimelockCanChangeRole(created.bagFactory, IMPLEMENTATION_MANAGER_ROLE, "bag factory");
        _assertAdminAndTimelockCanChangeRole(created.flexStrategy, PROCESSOR_MANAGER_ROLE, "strategy");
        _assertAdminAndTimelockCanChangeRole(
            created.accountingToken, ACCOUNTING_MODULE_MANAGER_ROLE, "accounting token"
        );
        _assertAdminAndTimelockCanChangeRole(created.accountingModule, SAFE_MANAGER_ROLE, "accounting module");
        _assertAdminAndTimelockCanChangeRole(created.rewardsSweeper, ACCOUNTING_MODULE_MANAGER_ROLE, "rewards sweeper");
        _assertAdminAndTimelockCanChangeRole(created.safeGuard, GUARD_ADMIN_ROLE, "safeguard");
    }

    function _assertAdminAndTimelockCanChangeRole(address target, bytes32 role, string memory label) internal {
        _assertAdminCanGrantAndRevoke(target, role, label);
        _assertTimelockCanGrantAndRevoke(target, role, label);
    }

    function _assertAdminCanGrantAndRevoke(address target, bytes32 role, string memory label) internal {
        IRoleAccessControl access = IRoleAccessControl(target);

        assertFalse(access.hasRole(role, ADMIN_ROLE_RECIPIENT), string.concat(label, " admin recipient pre"));

        vm.startPrank(TestConstants.ADMIN);
        access.grantRole(role, ADMIN_ROLE_RECIPIENT);
        assertTrue(access.hasRole(role, ADMIN_ROLE_RECIPIENT), string.concat(label, " admin grant"));
        access.revokeRole(role, ADMIN_ROLE_RECIPIENT);
        vm.stopPrank();

        assertFalse(access.hasRole(role, ADMIN_ROLE_RECIPIENT), string.concat(label, " admin revoke"));
    }

    function _assertTimelockCanGrantAndRevoke(address target, bytes32 role, string memory label) internal {
        IRoleAccessControl access = IRoleAccessControl(target);

        assertFalse(access.hasRole(role, TIMELOCK_ROLE_RECIPIENT), string.concat(label, " timelock recipient pre"));

        _executeTimelockCall(
            target,
            abi.encodeCall(IRoleAccessControl.grantRole, (role, TIMELOCK_ROLE_RECIPIENT)),
            keccak256(abi.encode(label, target, role, TIMELOCK_ROLE_RECIPIENT, "grant"))
        );
        assertTrue(access.hasRole(role, TIMELOCK_ROLE_RECIPIENT), string.concat(label, " timelock grant"));

        _executeTimelockCall(
            target,
            abi.encodeCall(IRoleAccessControl.revokeRole, (role, TIMELOCK_ROLE_RECIPIENT)),
            keccak256(abi.encode(label, target, role, TIMELOCK_ROLE_RECIPIENT, "revoke"))
        );
        assertFalse(access.hasRole(role, TIMELOCK_ROLE_RECIPIENT), string.concat(label, " timelock revoke"));
    }

    function _executeTimelockCall(address target, bytes memory data, bytes32 salt) internal {
        TimelockController timelock = TimelockController(payable(created.timelock));
        uint256 delay = timelock.getMinDelay();

        vm.prank(TestConstants.PROPOSER);
        timelock.schedule(target, 0, data, bytes32(0), salt, delay);

        skip(delay);

        vm.prank(TestConstants.PROPOSER);
        timelock.execute(target, 0, data, bytes32(0), salt);
    }

    function _deployRegistry() internal returns (IRegistry deployedRegistry) {
        Registry registryLogic = new Registry();
        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryLogic), address(this), abi.encodeCall(IRegistry.initialize, (address(this)))
        );
        deployedRegistry = IRegistry(address(registryProxy));
    }

    function _populateRegistry() internal {
        bytes32[] memory keys = new bytes32[](12);
        keys[0] = RegistryKeys.VAULT;
        keys[1] = RegistryKeys.WRAPPED_TOKEN;
        keys[2] = RegistryKeys.WITHDRAWAL_REQUEST;
        keys[3] = RegistryKeys.WITHDRAWER;
        keys[4] = RegistryKeys.BAG_FACTORY;
        keys[5] = RegistryKeys.BAG;
        keys[6] = RegistryKeys.FLEX_STRATEGY;
        keys[7] = RegistryKeys.ACCOUNTING_MODULE;
        keys[8] = RegistryKeys.ACCOUNTING_TOKEN_FACTORY;
        keys[9] = RegistryKeys.REWARDS_SWEEPER;
        keys[10] = RegistryKeys.SAFE_GUARD;
        keys[11] = RegistryKeys.HOOKS_DEPLOYER;

        address[] memory values = new address[](12);
        values[0] = RegistryImplementations.VAULT_IMPLEMENTATION;
        values[1] = RegistryImplementations.WRAPPED_TOKEN_IMPLEMENTATION;
        values[2] = RegistryImplementations.WITHDRAWAL_REQUEST_IMPLEMENTATION;
        values[3] = RegistryImplementations.WITHDRAWER_IMPLEMENTATION;
        values[4] = RegistryImplementations.BAG_FACTORY_IMPLEMENTATION;
        values[5] = RegistryImplementations.BAG_IMPLEMENTATION;
        values[6] = RegistryImplementations.FLEX_STRATEGY_IMPLEMENTATION;
        values[7] = RegistryImplementations.ACCOUNTING_MODULE_IMPLEMENTATION;
        values[8] = RegistryImplementations.ACCOUNTING_TOKEN_FACTORY_IMPLEMENTATION;
        values[9] = RegistryImplementations.REWARDS_SWEEPER_IMPLEMENTATION;
        values[10] = RegistryImplementations.SAFE_GUARD_IMPLEMENTATION;
        values[11] = RegistryImplementations.HOOKS_DEPLOYER;

        registry.setValues(keys, values);
    }

    function _vaultParams() internal pure returns (IVaultFactory.VaultParams memory) {
        return IVaultFactory.VaultParams({
            admin: TestConstants.ADMIN,
            proposer: TestConstants.PROPOSER,
            processor: TestConstants.PROCESSOR,
            pauser: TestConstants.PAUSER,
            unpauser: TestConstants.UNPAUSER,
            resolver: TestConstants.RESOLVER,
            baseAsset: TestConstants.USDC,
            tokenName: "Whitelabel Roles USDC",
            tokenSymbol: "WLRUSDC",
            countNativeAsset: false,
            alwaysComputeTotalAssets: true,
            timelockDuration: 30 seconds,
            minWithdrawalAmount: 0.1 ether,
            maxDataLength: 256,
            bootstrapAmount: BOOTSTRAP_AMOUNT,
            bootstrapReceiver: TestConstants.BOOTSTRAP_RECEIVER
        });
    }

    function _flexParams() internal pure returns (IVaultFactory.FlexStrategyParams memory) {
        return IVaultFactory.FlexStrategyParams({
            deployStrategy: true,
            deployRewardsSweeper: true,
            alwaysComputeTotalAssets: true,
            multisig: TestConstants.SAFE_OWNER,
            offRampAddress: TestConstants.OFF_RAMP,
            accountingProcessor: TestConstants.PROCESSOR,
            lossProcessor: TestConstants.LOSS_PROCESSOR,
            targetApy: 0.05e18,
            lowerBound: 0.01e18,
            minRewardableAssets: 100e6,
            strategyName: "Roles Flex Strategy",
            strategySymbol: "ROLES-FLEX",
            accountingTokenName: "Roles Flex Accounting",
            accountingTokenSymbol: "aROLES"
        });
    }

    function _hooksConfig() internal pure returns (IVaultFactory.HooksConfig memory hooksConfig) {
        hooksConfig.deployPauserHook = true;
    }
}

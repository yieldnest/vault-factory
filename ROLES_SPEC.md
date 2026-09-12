# Vault Factory Roles Specification

This document defines the role actors and final role ownership for a vault factory deployment.

## Actors

Each vault deployment has these role actors:

- **ADMIN:** governance address for the deployment.
- **Timelock:** the per-vault OpenZeppelin `TimelockController` deployed by the factory.
- **OPS multisig:** operational multisig for day-to-day processor and pause operations.
- **RESOLVER multisig:** withdrawal operations multisig for resolving async withdrawal requests.
- **Flex strategy multisig:** custody safe used by the FlexStrategy, when a flex strategy is deployed.

## ADMIN

The ADMIN is configured on the deployment timelock.

The ADMIN holds these roles on the `TimelockController`:

- `DEFAULT_ADMIN_ROLE`
- `PROPOSER_ROLE`
- `EXECUTOR_ROLE`

The ADMIN also receives `CANCELLER_ROLE` through the OpenZeppelin `TimelockController` proposer setup.

## Timelock

The timelock holds delayed control for critical protocol operations across the deployment.

### Main Vault

The timelock holds:

- `DEFAULT_ADMIN_ROLE`
- `PROVIDER_MANAGER_ROLE`
- `ASSET_MANAGER_ROLE`
- `BUFFER_MANAGER_ROLE`
- `PROCESSOR_MANAGER_ROLE`
- `HOOKS_MANAGER_ROLE`

The timelock does not hold the operational roles on the Main Vault.

### Main Vault ProxyAdmin

The timelock is the owner of the Main Vault `ProxyAdmin`.

### Wrapped Token

When a wrapped token is deployed, the timelock is the owner of the wrapped token `ProxyAdmin`.

### WithdrawalRequest

The timelock holds:

- `DEFAULT_ADMIN_ROLE`
- `CONFIGURATION_MANAGER_ROLE`

The timelock is the owner of the WithdrawalRequest `ProxyAdmin`.

### BaseWithdrawer

The timelock is the owner of the BaseWithdrawer `ProxyAdmin`.

### BeaconProxyFactory

The timelock holds:

- `DEFAULT_ADMIN_ROLE`
- `IMPLEMENTATION_MANAGER_ROLE`

The timelock is the owner of the BeaconProxyFactory `ProxyAdmin`.

### FlexStrategy

When a FlexStrategy is deployed, the timelock holds:

- `DEFAULT_ADMIN_ROLE`
- `PROVIDER_MANAGER_ROLE`
- `ASSET_MANAGER_ROLE`
- `BUFFER_MANAGER_ROLE`
- `PROCESSOR_MANAGER_ROLE`
- `ALLOCATOR_MANAGER_ROLE`
- `HOOKS_MANAGER_ROLE`
- `ACCOUNTING_MODULE_MANAGER_ROLE`

The timelock is the owner of the FlexStrategy `ProxyAdmin`.

### AccountingToken

When an AccountingToken is deployed, the timelock holds:

- `DEFAULT_ADMIN_ROLE`
- `ACCOUNTING_MODULE_MANAGER_ROLE`

The timelock is the owner of the AccountingToken `ProxyAdmin`.

### AccountingModule

When an AccountingModule is deployed, the timelock holds:

- `DEFAULT_ADMIN_ROLE`
- `SAFE_MANAGER_ROLE`

The timelock is the owner of the AccountingModule `ProxyAdmin`.

### RewardsSweeper

When a RewardsSweeper is deployed, the timelock holds:

- `DEFAULT_ADMIN_ROLE`
- `ACCOUNTING_MODULE_MANAGER_ROLE`

The timelock is the owner of the RewardsSweeper `ProxyAdmin`.

### SafeGuard

When a SafeGuard is deployed, the timelock holds:

- `DEFAULT_ADMIN_ROLE`
- `PROCESSOR_MANAGER_ROLE`
- `GUARD_ADMIN_ROLE`

The timelock is the owner of the SafeGuard `ProxyAdmin`.

## OPS multisig

The OPS multisig holds the operational roles on the Main Vault:

- `PROCESSOR_ROLE`
- `PAUSER_ROLE`
- `UNPAUSER_ROLE`

When a FlexStrategy is deployed, the OPS multisig also holds the equivalent operational roles on the FlexStrategy:

- `PROCESSOR_ROLE`
- `PAUSER_ROLE`
- `UNPAUSER_ROLE`

The OPS multisig also holds `PAUSER_ROLE` on the WithdrawalRequest. The WithdrawalRequest has a single `PAUSER_ROLE` covering both pause and unpause behavior.

## RESOLVER multisig

The RESOLVER multisig holds:

- `RESOLVER_ROLE` on the WithdrawalRequest

## Flex strategy multisig

When a FlexStrategy is deployed, the flex strategy multisig holds:

- `LOSS_PROCESSOR_ROLE` on the AccountingModule

The flex strategy multisig is also the safe configured in the AccountingModule.

## Accounting processor

When a FlexStrategy is deployed, the accounting processor holds:

- `REWARDS_PROCESSOR_ROLE` on the AccountingModule

When a RewardsSweeper is deployed, the RewardsSweeper also holds `REWARDS_PROCESSOR_ROLE` on the AccountingModule.

## Factory cleanup

The factory may temporarily hold roles required for construction and bootstrapping.

The completed deployment must not leave dangling factory privileges. In particular, the factory must not retain any:

- `DEFAULT_ADMIN_ROLE`
- manager role
- processor role
- allocator role
- pauser role
- unpauser role
- resolver role


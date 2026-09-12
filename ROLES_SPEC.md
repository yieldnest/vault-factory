# Vault Factory Roles Specification

This document defines the role actors and final role ownership for a vault factory deployment.

## Actors

Each vault deployment has these role actors:

- **ADMIN:** governance address for the deployment.
- **PROPOSER:** governance operations multisig for proposing and executing timelocked operations.
- **Timelock:** the per-vault OpenZeppelin `TimelockController` deployed by the factory.
- **OPS multisig:** operational multisig for day-to-day processor and pause operations.
- **RESOLVER multisig:** withdrawal operations multisig for resolving async withdrawal requests.
- **Flex strategy multisig:** custody safe used by the FlexStrategy, when a flex strategy is deployed.

## ADMIN

The ADMIN is configured on the deployment timelock.

The ADMIN holds these roles on the `TimelockController`:

- `DEFAULT_ADMIN_ROLE`
- `CANCELLER_ROLE`

The ADMIN is not the normal proposer or executor. It is the supervisory multisig that can intervene if the proposal flow needs to be stopped or reconfigured.

The ADMIN can cancel a pending proposal through `CANCELLER_ROLE`.

The ADMIN can also revoke the PROPOSER multisig's `PROPOSER_ROLE` or `EXECUTOR_ROLE` through `DEFAULT_ADMIN_ROLE`.

## PROPOSER

The PROPOSER multisig holds these roles on the `TimelockController`:

- `PROPOSER_ROLE`
- `EXECUTOR_ROLE`

The PROPOSER multisig does not hold `DEFAULT_ADMIN_ROLE`.

## Timelock

The timelock holds delayed control for critical protocol operations across the deployment.

The intended workflow is:

1. The PROPOSER multisig schedules critical operations on the timelock.
2. The configured timelock delay elapses.
3. The PROPOSER multisig executes the operation through the timelock.

```text
                schedule()                  execute()
+----------+  ------------>  +----------+  ----------->  +-------------------+
| PROPOSER |                 | Timelock |                | Controlled system |
+----------+  <------------  +----------+                +-------------------+
                delay elapses                    upgrades / config changes

+-------+  cancel() / revoke PROPOSER_ROLE or EXECUTOR_ROLE
| ADMIN |  ------------------------------------------------>
+-------+                    +----------+
                             | Timelock |
                             +----------+
```

Critical operations include, but are not limited to:

- proxy upgrades
- provider changes
- asset additions, removals, or status changes
- buffer changes
- processor rule changes
- hook changes
- manager role changes on controlled contracts

The ADMIN multisig can intervene before execution by cancelling the proposal. If the PROPOSER multisig should no longer control the normal governance flow, the ADMIN multisig can revoke its `PROPOSER_ROLE` and/or `EXECUTOR_ROLE`.

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

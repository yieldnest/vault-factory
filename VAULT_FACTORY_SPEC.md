# Vault factory

## Relevant repos

### Core vault contracts

git@github.com:yieldnest/yieldnest-vault.git


### Flex strategy contracts

git@github.com:yieldnest/yieldnest-flex-strategy.git

### Vault async withdrawals Contracts

git@github.com:yieldnest/yieldnest-vault-withdrawals.git

### Metahooks, hooks, and other periphery contracts

git@github.com:yieldnest/yieldnest-vault-periphery.git

### Safe multisig transaction safeguards

git@github.com:yieldnest/safeguard.git

## RWA Vault Factory

The RWA factory allows one-transaction creation of RWA vaults on demand using the yieldnest-vault logic.

Configure the parameters of the RWA vault and deploy a vault under your control.

What an RWA vault is composed of:

### Main Vault

The top-level vault that represents the ERC20 shares token of the RWA tokenized asset. This is an instance of https://github.com/yieldnest/yieldnest-vault/blob/eth-max-vault/src/Vault.sol

The following notions are defined in the BaseVault. https://github.com/yieldnest/yieldnest-vault/blob/eth-max-vault/src/BaseVault.sol

The Main Vault has 18 decimals.

### Default asset

This is the default asset of the ERC4626 interface of the Main Vault. 

Example: USDC, USDT, SUSD.

Once chosen this asset CANNOT BE CHANGED, without breaking all ERC4626 integrations. Updating the default asset is very high risk and should never be done unless all consequences are fully understood and all potential collateral damage is assessed.

### Base Asset

This is the Base Asset of the vault, in which all other assets in the vaults are denominated.

Eg. WETH, WBNB, SUDS. 

Number of decimals of Base Asset MUST be 18. 

So in case the vault needs to price the vault in terms of USDC, USDT or any token that does not have 18 decimals, a wrapper needs to be deployed to extend the decimals with an instance of Wrapped Token. 


If the base asset has 18 decimals, base asset and default asset must be the same.



### Vault Parameters

These are the key parameters that are used when deploying a new RWA vault via the factory:

- **admin:**  
  The address that will have admin privileges over the vault.

- **processor:**  
  The address that is authorized to process actions within the vault.

- **pauser:**  
  The address that is allowed to pause the vault functionality in the event of an emergency.

- **unpauser:**  
  The address allowed to unpause the vault after it has been paused.

- **feeManager:**  
  The address responsible for managing and collecting any fees associated with the vault.

- **tokenName:**  
  The display name of the vault’s share token.

- **tokenSymbol:**  
  The symbol for the vault's share token, set using the provided function or value.

- **countNativeAsset:**  
  A boolean parameter indicating whether the vault should count the native asset (e.g., ETH, BNB) as part of its total asset value.  
  - If `true`, the vault includes the native asset balance when calculating its total assets under management.
  - If `false`, only ERC20 and explicitly defined assets are considered in total asset calculations.

- **timelockDuration:**  
  The duration (in seconds) of the timelock applied specifically to sensitive operations such as upgrades, asset changes, rate provider changes, and modifications to critical parameters. This timelock enforces a mandatory waiting period between when such an action is proposed (queued) and when it can actually be executed, providing additional time and security for stakeholders to review and react to these potentially impactful changes.


Base Withdrawal fee is 0, as withdrawals don't happen through the buffer. The Buffer is 0.

### Proxy and Upgrade Ownership

Vaults and related upgradeable components are deployed behind OpenZeppelin Transparent Upgradeable Proxies.

Each vault deployment has one OpenZeppelin `ProxyAdmin`. The `ProxyAdmin` is owned by one `TimelockController`.

The same timelock is also assigned wherever the deployment has critical protocol operations. This includes, at minimum:

- upgrades through the `ProxyAdmin`
- provider changes
- asset changes
- buffer changes
- processor rule changes
- allocator manager operations
- hook manager operations
- other critical configuration changes introduced by optional modules

The factory must configure the timelock as the owner or role holder for these critical operations during deployment. Any temporary roles held by the factory or deployer for setup must be renounced or revoked before the deployment is considered complete.

### Hooks

Each Main Vault deployment includes one `MetaHooks` instance.

The `MetaHooks` instance is configured as the hooks contract for the Main Vault.

The initial `MetaHooks` hook set includes a `PauserHook` for the Main Vault.

The `PauserHook` allows the configured pauser path to pause the Main Vault when the hook's pause condition is triggered. The `MetaHooks` hook manager role is controlled by the deployment timelock, so hook changes are treated as critical protocol operations.

### Flex strategy - OPTIONAL

The flex strategy may be optionally included in the flex strategy or added manually later. 

Specify a boolean param for deployStrategy.

The additional parameters here are:

#### Parameters

The parameters are the ones specified here:

https://github.com/yieldnest/yieldnest-flex-strategy/blob/main/script/FlexStrategyDeployer.sol#L16

Additional factory parameter:

- **offRampAddress:**  
  The address that is allowed to receive the flex strategy asset from the flex strategy multisig through the SafeGuard module.


The rules here are that the base asset is the same base asset as the Main Vault.

paused is false.

The Allocators contains the Main Vault and the factory contract that will make the first boostrap deposit.

Once that boostrap action is done, the role is renounced.



#### Flex strategy deposit rules

The vault also preloads deposit/mint withdraw/redeem rules for the flex strategy if it exists.

#### Flex strategy multisig SafeGuard

The flex strategy multisig is expected to be configured with a SafeGuard module.

The factory deploys the SafeGuard instance and configures it with a rule that permits sending the asset of the flex strategy to `offRampAddress`.

The factory does not enable the SafeGuard module on the multisig. It is the user's responsibility to configure the deployed SafeGuard as a module for that multisig after creation.


### Bootstrapping

The Main Vault and Flex Strategy (if added) need to be boostrapped with one unit of the default asset.

Eg. 1 USDC (1e6 in wei), 1 USDT (1e6 in Wei), 1 SUSD, (1e18 in wei).

The factory create call transfers the asset or assets away from the users.

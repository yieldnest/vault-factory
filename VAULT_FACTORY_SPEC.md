# Vault factory

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

- **admin:** `ADMIN`  
  The address that will have admin privileges over the vault.

- **processor:** `ADMIN`  
  The address that is authorized to process actions within the vault.

- **pauser:** `ADMIN`  
  The address that is allowed to pause vault functionality in the event of an emergency.

- **unpauser:** `ADMIN`  
  The address allowed to unpause the vault after it has been paused.

- **feeManager:** `ADMIN`  
  The address responsible for managing and collecting any fees associated with the vault.

- **tokenName:** `"ASSET BACKED DERIVATIVE YIELD VAULT"`  
  The display name of the vault’s share token.

- **tokenSymbol:** `symbol()`  
  The symbol for the vault's share token, set using the provided `symbol()` function or value.





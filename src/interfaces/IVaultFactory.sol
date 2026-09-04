// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IVaultFactory {
    struct VaultParams {
        address admin;
        address processor;
        address pauser;
        address unpauser;
        address feeManager;
        address resolver;
        address baseAsset;
        address defaultAsset;
        string tokenName;
        string tokenSymbol;
        bool countNativeAsset;
        bool alwaysComputeTotalAssets;
        uint256 timelockDuration;
        uint256 minWithdrawalAmount;
        uint256 maxDataLength;
        uint256 bootstrapAmount;
        address bootstrapReceiver;
    }

    struct FlexStrategyParams {
        bool deployStrategy;
        address multisig;
        address offRampAddress;
        bytes deployData;
    }

    struct CreatedVault {
        address vault;
        address timelock;
        address wrappedToken;
        address provider;
        address withdrawalRequest;
        address withdrawer;
        address bagFactory;
        address requestPolicy;
        address safeGuard;
        address flexStrategy;
    }

    event VaultCreated(address indexed creator, address indexed vault, address indexed timelock, CreatedVault created);

    error AssetDecimalsTooHigh(uint8 decimals);
    error BootstrapAmountTooLow(uint256 amount, uint256 minimum);
    error FunctionalityUnavailable();
    error InvalidDefaultAsset();
    error MissingRegistryValue(bytes32 key);
    error ZeroAddress();

    function createVault(VaultParams calldata params, FlexStrategyParams calldata flexParams)
        external
        returns (CreatedVault memory created);
}

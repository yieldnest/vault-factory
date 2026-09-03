// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IVaultFactory {
    struct VaultParams {
        address admin;
        address processor;
        address pauser;
        address unpauser;
        address feeManager;
        address baseAsset;
        address defaultAsset;
        address provider;
        string tokenName;
        string tokenSymbol;
        bool countNativeAsset;
        bool alwaysComputeTotalAssets;
        uint256 timelockDuration;
        uint256 bootstrapAmount;
        address bootstrapReceiver;
    }

    struct RegistryKeys {
        bytes32 vault;
        bytes32 wrappedToken;
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
        address safeGuard;
        address flexStrategy;
    }

    event VaultCreated(
        address indexed creator,
        address indexed vault,
        address indexed timelock,
        address wrappedToken,
        address safeGuard,
        address flexStrategy
    );

    error AssetDecimalsTooHigh(uint8 decimals);
    error EmptyKey(bytes32 key);
    error FunctionalityUnavailable();
    error InvalidDefaultAsset();
    error MissingRegistryValue(bytes32 key);
    error ZeroAddress();
    error ZeroAmount();

    function createVault(
        VaultParams calldata params,
        RegistryKeys calldata keys,
        FlexStrategyParams calldata flexParams
    ) external returns (CreatedVault memory created);
}

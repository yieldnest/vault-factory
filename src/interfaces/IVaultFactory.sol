// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IVaultFactory {
    struct VaultParams {
        address admin;
        address proposer;
        address processor;
        address pauser;
        address unpauser;
        address resolver;
        address baseAsset;
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
        bool deployRewardsSweeper;
        bool alwaysComputeTotalAssets;
        address multisig;
        address offRampAddress;
        address accountingProcessor;
        address lossProcessor;
        uint256 targetApy;
        uint256 lowerBound;
        uint256 minRewardableAssets;
        string strategyName;
        string strategySymbol;
        string accountingTokenName;
        string accountingTokenSymbol;
    }

    struct ProcessAccountingGuardHookConfig {
        uint256 maxTotalAssetsDecreaseRatio;
        uint256 maxTotalAssetsIncreaseRatio;
        uint256 maxTotalSupplyIncreaseRatio;
        uint256 expectedPerformanceFee;
    }

    struct FeeHookConfig {
        uint256 performanceFee;
        address feeRecipient;
    }

    struct HooksConfig {
        bool deployPauserHook;
        bool deployFeeHook;
        bool deployProcessAccountingGuardHook;
        FeeHookConfig feeHook;
        ProcessAccountingGuardHookConfig processAccountingGuardHook;
    }

    struct CreatedVault {
        address vault;
        address timelock;
        address wrappedToken;
        address provider;
        address metaHooks;
        address pauserHook;
        address feeHook;
        address processAccountingGuardHook;
        address withdrawalRequest;
        address withdrawer;
        address bagFactory;
        address requestPolicy;
        address safeGuard;
        address accountingModuleHook;
        address flexStrategy;
        address accountingToken;
        address accountingModule;
        address rewardsSweeper;
    }

    struct WithdrawalSystem {
        address withdrawalRequest;
        address withdrawer;
        address bagFactory;
        address requestPolicy;
    }

    event VaultCreated(address indexed creator, address indexed vault, address indexed timelock, CreatedVault created);
    event VaultCreationStarted(
        address indexed creator, bytes32 indexed deploymentId, address indexed vault, CreatedVault created
    );
    event WithdrawalSystemDeployed(address indexed vault, address indexed timelock, WithdrawalSystem withdrawalSystem);
    event NonceAdvanced(address indexed caller, address marker);

    error AssetDecimalsTooHigh(uint8 decimals);
    error BootstrapSharesMismatch(uint256 actualShares, uint256 expectedShares);
    error BootstrapAmountTooLow(uint256 amount, uint256 minimum);
    error MissingRegistryValue(bytes32 key);
    error UnknownDeployment(bytes32 deploymentId);
    error Unauthorized();
    error ZeroAddress();
    error InvalidHooksConfig();

    function createVault(
        VaultParams calldata params,
        FlexStrategyParams calldata flexParams,
        HooksConfig calldata hooksConfig
    ) external returns (CreatedVault memory created);

    function startCreateVault(
        VaultParams calldata params,
        FlexStrategyParams calldata flexParams,
        HooksConfig calldata hooksConfig
    ) external returns (bytes32 deploymentId, CreatedVault memory created);

    function resumeCreateVault(bytes32 deploymentId) external returns (CreatedVault memory created);

    function deployWithdrawalSystem(
        address vault,
        address timelock,
        address resolver,
        address pauser,
        uint256 minWithdrawalAmount,
        uint256 maxDataLength
    ) external returns (WithdrawalSystem memory withdrawals);

    function advanceNonce() external returns (address marker);
}

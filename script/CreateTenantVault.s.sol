// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {CreateVault} from "script/CreateVault.s.sol";

contract CreateTenantVault is CreateVault {
    /// @notice Supervisory admin, operational actor, and bootstrap share receiver for this sample deployment.
    address internal constant ADMIN = 0xDDd7e1bb53Cf95465a3bc652F3ed534Abb915c74;
    address internal constant PROPOSER = 0xcD504Ae9bf07E79fadBB4eAF3f2887DC32Be2b2D;
    address internal constant FLEX_STRATEGY_MULTISIG = 0x9FbE4f05Ae82cf03EFc4C3d523c881A3a51A6ee0;
    address internal constant PAUSER = 0x52a7BA80b17E672a6BdE96dB357617A5C5e9c30A;
    address internal constant PROCESSOR = 0x322e2895b5Ac8ee1a5Fdc730554eD0b32e54a687;
    address internal constant LOSS_PROCESSOR = ADMIN;
    address internal constant UNPAUSER = ADMIN;

    /// @notice Ethereum mainnet USDC, used as both base and default asset.
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant OFF_RAMP = 0xB09B3D0F9a0105cCe9e63D3D7217CD1411Cc5BE9;
    address internal constant FEE_RECIPIENT = 0x684Fa1158D1f1430A5EeA429e3A81eB7a18813D5;

    uint256 internal constant TIMELOCK_DURATION = 1 days;
    // 0.1 USDC expressed in 18-decimal vault shares, the unit the request policy locks.
    uint256 internal constant MIN_WITHDRAWAL_AMOUNT = 1 ether;
    uint256 internal constant MAX_DATA_LENGTH = 256;
    uint256 internal constant BOOTSTRAP_AMOUNT = 1e6; // 1 USDC
    uint256 internal constant TARGET_APY = 0.11e18;
    uint256 internal constant LOWER_BOUND = 0.01e18;
    uint256 internal constant MIN_REWARDABLE_ASSETS = 1e6;
    bool internal constant DEPLOY_PAUSER_HOOK = true;
    bool internal constant DEPLOY_FEE_HOOK = true;
    bool internal constant DEPLOY_PROCESS_ACCOUNTING_GUARD_HOOK = true;
    uint256 internal constant PERFORMANCE_FEE = 0.1e18;
    uint256 internal constant MAX_TOTAL_ASSETS_DECREASE_RATIO = 0.003e18;
    uint256 internal constant MAX_TOTAL_ASSETS_INCREASE_RATIO = 0.003e18;
    uint256 internal constant MAX_TOTAL_SUPPLY_INCREASE_RATIO = 0.003e18;
    uint256 internal constant EXPECTED_PERFORMANCE_FEE = PERFORMANCE_FEE;

    function _vaultParams() internal pure override returns (IVaultFactory.VaultParams memory) {
        return IVaultFactory.VaultParams({
            admin: ADMIN,
            proposer: PROPOSER,
            processor: PROCESSOR,
            pauser: PAUSER,
            unpauser: UNPAUSER,
            resolver: PROCESSOR,
            baseAsset: USDC,
            tokenName: "ASSET BACKED DERIVATIVE YIELD VAULT",
            tokenSymbol: "ABDY",
            countNativeAsset: false,
            alwaysComputeTotalAssets: false,
            timelockDuration: TIMELOCK_DURATION,
            minWithdrawalAmount: MIN_WITHDRAWAL_AMOUNT,
            maxDataLength: MAX_DATA_LENGTH,
            bootstrapAmount: BOOTSTRAP_AMOUNT,
            bootstrapReceiver: ADMIN
        });
    }

    function _flexParams() internal pure override returns (IVaultFactory.FlexStrategyParams memory) {
        return IVaultFactory.FlexStrategyParams({
            deployStrategy: true,
            deployRewardsSweeper: false,
            alwaysComputeTotalAssets: true,
            multisig: FLEX_STRATEGY_MULTISIG,
            offRampAddress: OFF_RAMP,
            accountingProcessor: PROCESSOR,
            lossProcessor: LOSS_PROCESSOR,
            targetApy: TARGET_APY,
            lowerBound: LOWER_BOUND,
            minRewardableAssets: MIN_REWARDABLE_ASSETS,
            strategyName: "ASSET BACKED DERIVATIVE YIELD VAULT Strategy",
            strategySymbol: "WLFUSDC-FLEX",
            accountingTokenName: "Whitelabel USDC Flex Accounting",
            accountingTokenSymbol: "aWLFUSDC"
        });
    }

    function _hooksConfig() internal pure override returns (IVaultFactory.HooksConfig memory) {
        return IVaultFactory.HooksConfig({
            deployPauserHook: DEPLOY_PAUSER_HOOK,
            deployFeeHook: DEPLOY_FEE_HOOK,
            deployProcessAccountingGuardHook: DEPLOY_PROCESS_ACCOUNTING_GUARD_HOOK,
            feeHook: IVaultFactory.FeeHookConfig({performanceFee: PERFORMANCE_FEE, feeRecipient: FEE_RECIPIENT}),
            processAccountingGuardHook: IVaultFactory.ProcessAccountingGuardHookConfig({
                maxTotalAssetsDecreaseRatio: MAX_TOTAL_ASSETS_DECREASE_RATIO,
                maxTotalAssetsIncreaseRatio: MAX_TOTAL_ASSETS_INCREASE_RATIO,
                maxTotalSupplyIncreaseRatio: MAX_TOTAL_SUPPLY_INCREASE_RATIO,
                expectedPerformanceFee: EXPECTED_PERFORMANCE_FEE
            })
        });
    }

    function _deploymentName() internal pure override returns (string memory) {
        return "abdy-vault";
    }
}

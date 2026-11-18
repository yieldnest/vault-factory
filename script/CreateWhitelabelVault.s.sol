// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {CreateVault} from "script/CreateVault.s.sol";

contract CreateWhitelabelVault is CreateVault {
    /// @notice Supervisory admin, operational actor, and bootstrap share receiver for this sample deployment.
    address internal constant CONTROLLER = 0x0e46F77dbe0b6e9782bDe5596cdAb025C222cC5d;

    /// @notice Ethereum mainnet USDC, used as both base and default asset.
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant OFF_RAMP = 0x0e46F77dbe0b6e9782bDe5596cdAb025C222cC5d;
    address internal constant FEE_RECIPIENT = 0x0e46F77dbe0b6e9782bDe5596cdAb025C222cC5d;

    uint256 internal constant TIMELOCK_DURATION = 15 seconds;
    // 0.1 USDC expressed in 18-decimal vault shares, the unit the request policy locks.
    uint256 internal constant MIN_WITHDRAWAL_AMOUNT = 0.1 ether;
    uint256 internal constant MAX_DATA_LENGTH = 256;
    uint256 internal constant BOOTSTRAP_AMOUNT = 1e6; // 1 USDC
    uint256 internal constant TARGET_APY = 0.05e18;
    uint256 internal constant LOWER_BOUND = 0.01e18;
    uint256 internal constant MIN_REWARDABLE_ASSETS = 100e6;
    bool internal constant DEPLOY_PAUSER_HOOK = true;
    bool internal constant DEPLOY_FEE_HOOK = true;
    bool internal constant DEPLOY_PROCESS_ACCOUNTING_GUARD_HOOK = true;
    uint256 internal constant PERFORMANCE_FEE = 0.1e18;
    uint256 internal constant MAX_TOTAL_ASSETS_DECREASE_RATIO = 0.005e18;
    uint256 internal constant MAX_TOTAL_ASSETS_INCREASE_RATIO = 0.005e18;
    uint256 internal constant MAX_TOTAL_SUPPLY_INCREASE_RATIO = 0.005e18;
    uint256 internal constant EXPECTED_PERFORMANCE_FEE = PERFORMANCE_FEE;

    function _vaultParams() internal pure override returns (IVaultFactory.VaultParams memory) {
        return IVaultFactory.VaultParams({
            admin: CONTROLLER,
            proposer: CONTROLLER,
            processor: CONTROLLER,
            pauser: CONTROLLER,
            unpauser: CONTROLLER,
            resolver: CONTROLLER,
            baseAsset: USDC,
            tokenName: "Whitelabel USDC RWA",
            tokenSymbol: "WLRWA",
            countNativeAsset: false,
            alwaysComputeTotalAssets: false,
            timelockDuration: TIMELOCK_DURATION,
            minWithdrawalAmount: MIN_WITHDRAWAL_AMOUNT,
            maxDataLength: MAX_DATA_LENGTH,
            bootstrapAmount: BOOTSTRAP_AMOUNT,
            bootstrapReceiver: CONTROLLER
        });
    }

    function _flexParams() internal pure override returns (IVaultFactory.FlexStrategyParams memory) {
        return IVaultFactory.FlexStrategyParams({
            deployStrategy: true,
            deployRewardsSweeper: true,
            alwaysComputeTotalAssets: true,
            multisig: CONTROLLER,
            offRampAddress: OFF_RAMP,
            accountingProcessor: CONTROLLER,
            lossProcessor: CONTROLLER,
            targetApy: TARGET_APY,
            lowerBound: LOWER_BOUND,
            minRewardableAssets: MIN_REWARDABLE_ASSETS,
            strategyName: "Whitelabel USDC Flex Strategy",
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
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {VaultVerifier} from "src/VaultVerifier.sol";

contract VerifyVault is Script {
    /// @notice Supervisory admin, operational actor, and bootstrap share receiver for this sample deployment.
    address internal constant CONTROLLER = 0x0e46F77dbe0b6e9782bDe5596cdAb025C222cC5d;

    /// @notice Ethereum mainnet USDC, used as both base and default asset.
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant OFF_RAMP = 0x0e46F77dbe0b6e9782bDe5596cdAb025C222cC5d;

    uint256 internal constant TIMELOCK_DURATION = 30 seconds;
    uint256 internal constant MIN_WITHDRAWAL_AMOUNT = 0.1 ether;
    uint256 internal constant MAX_DATA_LENGTH = 256;
    uint256 internal constant BOOTSTRAP_AMOUNT = 1e6;
    uint256 internal constant TARGET_APY = 0.05e18;
    uint256 internal constant LOWER_BOUND = 0.01e18;
    uint256 internal constant MIN_REWARDABLE_ASSETS = 100e6;

    function run() external returns (bool ok) {
        string memory defaultPath = string.concat("deployments/rwa-vault-", vm.toString(block.chainid), ".json");
        string memory deploymentPath = vm.envOr("DEPLOYMENT_FILE", defaultPath);
        string memory json = vm.readFile(deploymentPath);

        address factory = vm.envOr("VAULT_FACTORY", address(0));
        if (factory == address(0)) {
            factory = vm.promptAddress("VaultFactory address");
        }

        IVaultFactory.CreatedVault memory created = _createdVault(json);
        address proposer = vm.envOr("TIMELOCK_PROPOSER", address(0));
        if (proposer == address(0)) {
            proposer = vm.promptAddress("Timelock proposer");
        }

        VaultVerifier.Verification memory verification = VaultVerifier.Verification({
            factory: factory, created: created, vaultParams: _vaultParams(proposer), flexParams: _flexParams()
        });

        VaultVerifier verifier = new VaultVerifier();
        ok = verifier.verify(created.vault, verification);

        console2.log("Deployment file:", deploymentPath);
        console2.log("VaultFactory:", factory);
        console2.log("Vault:", created.vault);
        console2.log("Verified:", ok);
    }

    function _createdVault(string memory json) internal pure returns (IVaultFactory.CreatedVault memory created) {
        created = IVaultFactory.CreatedVault({
            vault: vm.parseJsonAddress(json, ".vault"),
            timelock: vm.parseJsonAddress(json, ".timelock"),
            wrappedToken: vm.parseJsonAddress(json, ".wrappedToken"),
            provider: vm.parseJsonAddress(json, ".provider"),
            withdrawalRequest: vm.parseJsonAddress(json, ".withdrawalRequest"),
            withdrawer: vm.parseJsonAddress(json, ".withdrawer"),
            bagFactory: vm.parseJsonAddress(json, ".bagFactory"),
            requestPolicy: vm.parseJsonAddress(json, ".requestPolicy"),
            safeGuard: vm.parseJsonAddress(json, ".safeGuard"),
            accountingModuleHook: vm.parseJsonAddress(json, ".accountingModuleHook"),
            flexStrategy: vm.parseJsonAddress(json, ".flexStrategy"),
            accountingToken: vm.parseJsonAddress(json, ".accountingToken"),
            accountingModule: vm.parseJsonAddress(json, ".accountingModule"),
            rewardsSweeper: vm.parseJsonAddress(json, ".rewardsSweeper")
        });
    }

    function _vaultParams(address proposer) internal pure returns (IVaultFactory.VaultParams memory) {
        return IVaultFactory.VaultParams({
            admin: CONTROLLER,
            proposer: proposer,
            processor: CONTROLLER,
            pauser: CONTROLLER,
            unpauser: CONTROLLER,
            feeManager: CONTROLLER,
            resolver: CONTROLLER,
            baseAsset: USDC,
            tokenName: "Whitelabel USDC RWA",
            tokenSymbol: "WLRWA",
            countNativeAsset: false,
            alwaysComputeTotalAssets: true,
            timelockDuration: TIMELOCK_DURATION,
            minWithdrawalAmount: MIN_WITHDRAWAL_AMOUNT,
            maxDataLength: MAX_DATA_LENGTH,
            bootstrapAmount: BOOTSTRAP_AMOUNT,
            bootstrapReceiver: CONTROLLER
        });
    }

    function _flexParams() internal pure returns (IVaultFactory.FlexStrategyParams memory) {
        return IVaultFactory.FlexStrategyParams({
            deployStrategy: true,
            deployRewardsSweeper: true,
            alwaysComputeTotalAssets: true,
            multisig: CONTROLLER,
            offRampAddress: OFF_RAMP,
            accountingProcessor: CONTROLLER,
            targetApy: TARGET_APY,
            lowerBound: LOWER_BOUND,
            minRewardableAssets: MIN_REWARDABLE_ASSETS,
            strategyName: "Whitelabel USDC Flex Strategy",
            strategySymbol: "WLFUSDC-FLEX",
            accountingTokenName: "Whitelabel USDC Flex Accounting",
            accountingTokenSymbol: "aWLFUSDC"
        });
    }
}

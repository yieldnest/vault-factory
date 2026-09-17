// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {Registry} from "src/Registry.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {VaultFactory} from "src/VaultFactory.sol";
import {RegistryImplementations} from "script/RegistryImplementations.sol";
import {SafeTestLib} from "test/lib/SafeTestLib.sol";
import {TestConstants} from "test/lib/TestConstants.sol";
import {ISafe} from "lib/safeguard/lib/safe-smart-account/contracts/interfaces/ISafe.sol";
import {HooksLib} from "lib/yieldnest-vault/src/library/HooksLib.sol";
import {PauserHook} from "lib/yieldnest-vault-periphery/src/hooks/PauserHook.sol";

interface IVaultHooksFlow {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function convertToAssets(uint256 shares) external view returns (uint256 assets);
    function processAccounting() external;
    function processor(address[] calldata targets, uint256[] calldata values, bytes[] calldata data)
        external
        returns (bytes[] memory);
    function setBuffer(address buffer) external;
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);
    function totalAssets() external view returns (uint256 assets);
    function totalSupply() external view returns (uint256 supply);
    function hooks() external view returns (address);
}

interface IMetaHooksFlow {
    function hooks(uint256 index) external view returns (address);
    function hooksLength() external view returns (uint256);
}

interface IAccountingModuleHooksFlow {
    function cooldownSeconds() external view returns (uint16);
    function processRewards(uint256 amount) external;
}

interface IHookName {
    function name() external view returns (string memory);
}

contract VaultFactoryFlexFlowHooksIntegrationTest is Test {
    uint256 private constant BOOTSTRAP_AMOUNT = 1e6;
    uint256 private constant PERFORMANCE_FEE = 0.1e18;
    address private constant FEE_RECIPIENT = 0x1000000000000000000000000000000000000014;

    struct FeeAccountingSnapshot {
        address feeRecipient;
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 vaultStrategyShares;
        uint256 strategyAssets;
        uint256 vaultStrategyAssets;
        uint256 feeRecipientShares;
    }

    IRegistry private registry;
    VaultFactory private factory;
    ISafe private safe;
    IVaultFactory.CreatedVault private created;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("eth_mainnet"));

        registry = _deployRegistry();
        _populateRegistry();
        factory = new VaultFactory(registry);
        safe = SafeTestLib.deploySingleOwnerSafe(TestConstants.SAFE_OWNER);

        created = _createVault(_vaultParams(), _flexParams(address(safe)), _hooksConfig(1e18));
    }

    function test_Hooks_Are_Instantiated_And_Ordered() public view {
        assertEq(IHookName(created.metaHooks).name(), "MetaHooks", "meta hooks name");
        assertEq(IHookName(created.pauserHook).name(), "PauserHook", "pauser hook name");
        assertEq(IHookName(created.feeHook).name(), "PerformanceFeeHooks", "fee hook name");
        assertEq(
            IHookName(created.processAccountingGuardHook).name(),
            "ProcessAccountingGuardHook",
            "guard hook name"
        );
        assertEq(IVaultHooksFlow(created.vault).hooks(), created.metaHooks, "vault hooks");

        IMetaHooksFlow metaHooks = IMetaHooksFlow(created.metaHooks);
        assertEq(metaHooks.hooksLength(), 3, "hooks length");
        assertEq(metaHooks.hooks(0), created.pauserHook, "pauser first");
        assertEq(metaHooks.hooks(1), created.feeHook, "fee second");
        assertEq(metaHooks.hooks(2), created.processAccountingGuardHook, "guard third");
    }

    function test_PauserHook_Blocks_Each_Hook_Call_Type() public {
        _pause(PauserHook.HookCall.Deposit);
        _expectDepositRevert(TestConstants.DEPOSITOR, 1e6);
        _unpause(PauserHook.HookCall.Deposit);

        _pause(PauserHook.HookCall.Mint);
        _expectMintRevert(TestConstants.DEPOSITOR, 1e18);
        _unpause(PauserHook.HookCall.Mint);

        _pause(PauserHook.HookCall.ProcessAccounting);
        _expectPausedHookRevert(PauserHook.HookCall.ProcessAccounting);
        IVaultHooksFlow(created.vault).processAccounting();
        _unpause(PauserHook.HookCall.ProcessAccounting);

        uint256 userDeposit = 10e6;
        _depositToVault(TestConstants.DEPOSITOR, userDeposit);
        _moveVaultAssetsToFlexStrategy(userDeposit);
        _approveSafeAccountingModule();

        vm.prank(created.timelock);
        IVaultHooksFlow(created.vault).setBuffer(created.flexStrategy);

        _pause(PauserHook.HookCall.Withdraw);
        vm.prank(TestConstants.DEPOSITOR);
        _expectPausedHookRevert(PauserHook.HookCall.Withdraw);
        IVaultHooksFlow(created.vault).withdraw(1e6, TestConstants.DEPOSITOR, TestConstants.DEPOSITOR);
        _unpause(PauserHook.HookCall.Withdraw);

        uint256 redeemShares = IVaultHooksFlow(created.vault).previewWithdraw(1e6);
        _pause(PauserHook.HookCall.Redeem);
        vm.prank(TestConstants.DEPOSITOR);
        _expectPausedHookRevert(PauserHook.HookCall.Redeem);
        IVaultHooksFlow(created.vault).redeem(redeemShares, TestConstants.DEPOSITOR, TestConstants.DEPOSITOR);
        _unpause(PauserHook.HookCall.Redeem);
    }

    function test_FeeHook_Mints_TenPercent_Performance_Fee_On_ProcessAccounting() public {
        uint256 userDeposit = 1_000_000e6;
        uint256 rewards = 100_000e6;

        _depositToVault(TestConstants.DEPOSITOR, userDeposit);
        _moveVaultAssetsToFlexStrategy(userDeposit);

        FeeAccountingSnapshot memory beforeAccounting = _feeAccountingSnapshot();

        skip(365 days);
        vm.prank(TestConstants.PROCESSOR);
        IAccountingModuleHooksFlow(created.accountingModule).processRewards(rewards);

        IVaultHooksFlow(created.vault).processAccounting();

        uint256 totalAssetsAfter = IVaultHooksFlow(created.vault).totalAssets();
        uint256 strategyAssetsAdded = IVaultHooksFlow(created.flexStrategy).totalAssets() - beforeAccounting.strategyAssets;
        uint256 vaultStrategyAssetsAdded = IVaultHooksFlow(created.flexStrategy).convertToAssets(
            beforeAccounting.vaultStrategyShares
        ) - beforeAccounting.vaultStrategyAssets;
        uint256 mainVaultAssetsAdded = totalAssetsAfter - beforeAccounting.totalAssets;
        uint256 feeBaseAssets = mainVaultAssetsAdded * PERFORMANCE_FEE / 1e18;
        uint256 expectedFeeShares = feeBaseAssets * beforeAccounting.totalSupply / (totalAssetsAfter - feeBaseAssets);

        assertEq(strategyAssetsAdded, rewards, "strategy assets added");
        assertEq(mainVaultAssetsAdded, vaultStrategyAssetsAdded, "main vault assets added");
        assertEq(totalAssetsAfter, beforeAccounting.totalAssets + mainVaultAssetsAdded, "main vault total assets");
        assertLt(mainVaultAssetsAdded, rewards, "vault assets added excludes bootstrap holder rewards");
        assertGt(expectedFeeShares, 0, "expected fee shares");
        assertEq(
            IERC20(created.vault).balanceOf(beforeAccounting.feeRecipient) - beforeAccounting.feeRecipientShares,
            expectedFeeShares,
            "fee shares"
        );
    }

    function test_ProcessAccountingGuard_Reverts_When_Reward_Increase_Exceeds_Bounds() public {
        safe = SafeTestLib.deploySingleOwnerSafe(TestConstants.SAFE_OWNER);
        IVaultFactory.FlexStrategyParams memory flexParams = _flexParams(address(safe));
        flexParams.targetApy = 10e18;
        created = _createVault(_vaultParams(), flexParams, _hooksConfig(0.01e18));

        uint256 userDeposit = 1_000_000e6;
        uint256 rewards = 100_000e6;

        _depositToVault(TestConstants.DEPOSITOR, userDeposit);
        _moveVaultAssetsToFlexStrategy(userDeposit);

        uint256 totalAssetsBefore = IVaultHooksFlow(created.vault).totalAssets();
        uint256 feeRecipientSharesBefore = IERC20(created.vault).balanceOf(FEE_RECIPIENT);

        skip(365 days);
        vm.prank(TestConstants.PROCESSOR);
        IAccountingModuleHooksFlow(created.accountingModule).processRewards(rewards);

        vm.expectPartialRevert(HooksLib.HookCallFailed.selector);
        IVaultHooksFlow(created.vault).processAccounting();

        assertEq(IVaultHooksFlow(created.vault).totalAssets(), totalAssetsBefore, "assets rolled back");
        assertEq(IERC20(created.vault).balanceOf(FEE_RECIPIENT), feeRecipientSharesBefore, "fee rolled back");
    }

    function _createVault(
        IVaultFactory.VaultParams memory vaultParams,
        IVaultFactory.FlexStrategyParams memory flexParams,
        IVaultFactory.HooksConfig memory hooksConfig
    ) internal returns (IVaultFactory.CreatedVault memory deployed) {
        deal(TestConstants.USDC, TestConstants.CREATOR, BOOTSTRAP_AMOUNT * 2);

        vm.startPrank(TestConstants.CREATOR);
        IERC20(TestConstants.USDC).approve(address(factory), BOOTSTRAP_AMOUNT * 2);
        deployed = factory.createVault(vaultParams, flexParams, hooksConfig);
        vm.stopPrank();
    }

    function _feeAccountingSnapshot() internal view returns (FeeAccountingSnapshot memory snapshot) {
        snapshot.feeRecipient = FEE_RECIPIENT;
        snapshot.totalAssets = IVaultHooksFlow(created.vault).totalAssets();
        snapshot.totalSupply = IVaultHooksFlow(created.vault).totalSupply();
        snapshot.vaultStrategyShares = IERC20(created.flexStrategy).balanceOf(created.vault);
        snapshot.strategyAssets = IVaultHooksFlow(created.flexStrategy).totalAssets();
        snapshot.vaultStrategyAssets =
            IVaultHooksFlow(created.flexStrategy).convertToAssets(snapshot.vaultStrategyShares);
        snapshot.feeRecipientShares = IERC20(created.vault).balanceOf(snapshot.feeRecipient);
    }

    function _pause(PauserHook.HookCall hookCall) internal {
        vm.prank(TestConstants.PAUSER);
        PauserHook(created.pauserHook).pause(hookCall);
    }

    function _unpause(PauserHook.HookCall hookCall) internal {
        vm.prank(TestConstants.UNPAUSER);
        PauserHook(created.pauserHook).unpause(hookCall);
    }

    function _expectDepositRevert(address depositor, uint256 amount) internal {
        deal(TestConstants.USDC, depositor, amount);

        vm.startPrank(depositor);
        IERC20(TestConstants.USDC).approve(created.vault, amount);
        _expectPausedHookRevert(PauserHook.HookCall.Deposit);
        IVaultHooksFlow(created.vault).deposit(amount, depositor);
        vm.stopPrank();
    }

    function _expectMintRevert(address depositor, uint256 shares) internal {
        deal(TestConstants.USDC, depositor, 1e6);

        vm.startPrank(depositor);
        IERC20(TestConstants.USDC).approve(created.vault, 1e6);
        _expectPausedHookRevert(PauserHook.HookCall.Mint);
        IVaultHooksFlow(created.vault).mint(shares, depositor);
        vm.stopPrank();
    }

    function _expectPausedHookRevert(PauserHook.HookCall hookCall) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                HooksLib.HookCallFailed.selector, abi.encodeWithSelector(PauserHook.Paused.selector, hookCall)
            )
        );
    }

    function _depositToVault(address depositor, uint256 amount) internal returns (uint256 shares) {
        deal(TestConstants.USDC, depositor, amount);

        vm.startPrank(depositor);
        IERC20(TestConstants.USDC).approve(created.vault, amount);
        shares = IVaultHooksFlow(created.vault).deposit(amount, depositor);
        vm.stopPrank();
    }

    function _moveVaultAssetsToFlexStrategy(uint256 amount) internal {
        address[] memory targets = new address[](2);
        targets[0] = TestConstants.USDC;
        targets[1] = created.flexStrategy;

        uint256[] memory values = new uint256[](2);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IERC20.approve, (created.flexStrategy, amount));
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, created.vault);

        vm.prank(TestConstants.PROCESSOR);
        IVaultHooksFlow(created.vault).processor(targets, values, data);
    }

    function _approveSafeAccountingModule() internal {
        SafeTestLib.execSingleOwnerSafeTransaction(
            safe,
            TestConstants.SAFE_OWNER,
            TestConstants.USDC,
            abi.encodeCall(IERC20.approve, (created.accountingModule, type(uint256).max))
        );
    }

    function _deployRegistry() internal returns (IRegistry deployedRegistry) {
        Registry registryLogic = new Registry();
        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryLogic), address(this), abi.encodeCall(IRegistry.initialize, (address(this)))
        );
        deployedRegistry = IRegistry(address(registryProxy));
    }

    function _populateRegistry() internal {
        bytes32[] memory keys = new bytes32[](12);
        keys[0] = RegistryKeys.VAULT;
        keys[1] = RegistryKeys.WRAPPED_TOKEN;
        keys[2] = RegistryKeys.WITHDRAWAL_REQUEST;
        keys[3] = RegistryKeys.WITHDRAWER;
        keys[4] = RegistryKeys.BAG_FACTORY;
        keys[5] = RegistryKeys.BAG;
        keys[6] = RegistryKeys.FLEX_STRATEGY;
        keys[7] = RegistryKeys.ACCOUNTING_MODULE;
        keys[8] = RegistryKeys.ACCOUNTING_TOKEN_FACTORY;
        keys[9] = RegistryKeys.REWARDS_SWEEPER;
        keys[10] = RegistryKeys.SAFE_GUARD;
        keys[11] = RegistryKeys.HOOKS_DEPLOYER;

        address[] memory values = new address[](12);
        values[0] = RegistryImplementations.VAULT_IMPLEMENTATION;
        values[1] = RegistryImplementations.WRAPPED_TOKEN_IMPLEMENTATION;
        values[2] = RegistryImplementations.WITHDRAWAL_REQUEST_IMPLEMENTATION;
        values[3] = RegistryImplementations.WITHDRAWER_IMPLEMENTATION;
        values[4] = RegistryImplementations.BAG_FACTORY_IMPLEMENTATION;
        values[5] = RegistryImplementations.BAG_IMPLEMENTATION;
        values[6] = RegistryImplementations.FLEX_STRATEGY_IMPLEMENTATION;
        values[7] = RegistryImplementations.ACCOUNTING_MODULE_IMPLEMENTATION;
        values[8] = RegistryImplementations.ACCOUNTING_TOKEN_FACTORY_IMPLEMENTATION;
        values[9] = RegistryImplementations.REWARDS_SWEEPER_IMPLEMENTATION;
        values[10] = RegistryImplementations.SAFE_GUARD_IMPLEMENTATION;
        values[11] = RegistryImplementations.HOOKS_DEPLOYER;

        registry.setValues(keys, values);
    }

    function _vaultParams() internal pure returns (IVaultFactory.VaultParams memory) {
        return IVaultFactory.VaultParams({
            admin: TestConstants.ADMIN,
            proposer: TestConstants.PROPOSER,
            processor: TestConstants.PROCESSOR,
            pauser: TestConstants.PAUSER,
            unpauser: TestConstants.UNPAUSER,
            resolver: TestConstants.RESOLVER,
            baseAsset: TestConstants.USDC,
            tokenName: "Whitelabel Flex USDC",
            tokenSymbol: "WLFUSDC",
            countNativeAsset: false,
            alwaysComputeTotalAssets: false,
            timelockDuration: 30 seconds,
            minWithdrawalAmount: 0.1 ether,
            maxDataLength: 256,
            bootstrapAmount: BOOTSTRAP_AMOUNT,
            bootstrapReceiver: TestConstants.BOOTSTRAP_RECEIVER
        });
    }

    function _flexParams(address multisig) internal pure returns (IVaultFactory.FlexStrategyParams memory) {
        return IVaultFactory.FlexStrategyParams({
            deployStrategy: true,
            deployRewardsSweeper: true,
            alwaysComputeTotalAssets: true,
            multisig: multisig,
            offRampAddress: TestConstants.OFF_RAMP,
            accountingProcessor: TestConstants.PROCESSOR,
            lossProcessor: TestConstants.LOSS_PROCESSOR,
            targetApy: 10e18,
            lowerBound: 0.01e18,
            minRewardableAssets: 100e6,
            strategyName: "Flex Strategy",
            strategySymbol: "FLEX",
            accountingTokenName: "Flex Accounting",
            accountingTokenSymbol: "aFLEX"
        });
    }

    function _hooksConfig(uint256 maxTotalAssetsIncreaseRatio)
        internal
        pure
        returns (IVaultFactory.HooksConfig memory)
    {
        return IVaultFactory.HooksConfig({
            deployPauserHook: true,
            deployFeeHook: true,
            deployProcessAccountingGuardHook: true,
            feeHook: IVaultFactory.FeeHookConfig({performanceFee: PERFORMANCE_FEE, feeRecipient: FEE_RECIPIENT}),
            processAccountingGuardHook: IVaultFactory.ProcessAccountingGuardHookConfig({
                maxTotalAssetsDecreaseRatio: 1e18,
                maxTotalAssetsIncreaseRatio: maxTotalAssetsIncreaseRatio,
                maxTotalSupplyIncreaseRatio: 1e18,
                expectedPerformanceFee: PERFORMANCE_FEE
            })
        });
    }
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IERC20} from "src/interfaces/external/IERC20.sol";
import {Registry} from "src/Registry.sol";
import {VaultFactory} from "src/VaultFactory.sol";

interface IProxyAdminOwner {
    function owner() external view returns (address);
}

contract RegistryProxy {
    address public immutable logic;

    constructor(address logic_, bytes memory initData) {
        logic = logic_;

        if (initData.length != 0) {
            (bool success, bytes memory returnData) = logic_.delegatecall(initData);
            if (!success) {
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }
    }

    receive() external payable {}

    fallback() external payable {
        address logic_ = logic;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), logic_, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

contract MockToken {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint8 decimals_) {
        name = "Asset";
        symbol = "AST";
        decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        require(currentAllowance >= amount, "allowance");
        require(balanceOf[from] >= amount, "balance");

        allowance[from][msg.sender] = currentAllowance - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockVault {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant PROVIDER_MANAGER_ROLE = keccak256("PROVIDER_MANAGER_ROLE");
    bytes32 public constant BUFFER_MANAGER_ROLE = keccak256("BUFFER_MANAGER_ROLE");
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant PROCESSOR_MANAGER_ROLE = keccak256("PROCESSOR_MANAGER_ROLE");
    bytes32 public constant HOOKS_MANAGER_ROLE = keccak256("HOOKS_MANAGER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    mapping(bytes32 => mapping(address => bool)) public hasRole;
    mapping(address => bool) public activeAsset;
    address[] public assets;
    mapping(address => uint256) public shareBalance;

    address public provider;
    address public buffer;
    bool public paused;
    bool public initialized;
    string public tokenName;
    string public tokenSymbol;
    uint8 public tokenDecimals;
    bool public countNativeAsset;
    bool public alwaysComputeTotalAssets;
    uint256 public defaultAssetIndex;
    uint256 public totalSupply;

    modifier onlyRole(bytes32 role) {
        require(hasRole[role][msg.sender], "role");
        _;
    }

    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint64,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_,
        uint256 defaultAssetIndex_
    ) external {
        require(!initialized, "initialized");
        initialized = true;
        paused = true;
        tokenName = name;
        tokenSymbol = symbol;
        tokenDecimals = decimals_;
        countNativeAsset = countNativeAsset_;
        alwaysComputeTotalAssets = alwaysComputeTotalAssets_;
        defaultAssetIndex = defaultAssetIndex_;
        hasRole[DEFAULT_ADMIN_ROLE][admin] = true;
    }

    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        hasRole[role][account] = true;
    }

    function renounceRole(bytes32 role, address callerConfirmation) external {
        require(msg.sender == callerConfirmation, "confirmation");
        hasRole[role][callerConfirmation] = false;
    }

    function addAsset(address asset, bool active) external onlyRole(ASSET_MANAGER_ROLE) {
        assets.push(asset);
        activeAsset[asset] = active;
    }

    function setProvider(address provider_) external onlyRole(PROVIDER_MANAGER_ROLE) {
        provider = provider_;
    }

    function setBuffer(address buffer_) external onlyRole(BUFFER_MANAGER_ROLE) {
        buffer = buffer_;
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        require(provider != address(0), "provider");
        paused = false;
    }

    function deposit(uint256 amount, address receiver) external returns (uint256 shares) {
        require(!paused, "paused");
        address asset = assets[defaultAssetIndex];
        MockToken(asset).transferFrom(msg.sender, address(this), amount);
        shareBalance[receiver] += amount;
        totalSupply += amount;
        return amount;
    }
}

contract MockWrappedToken {
    IERC20 public underlyingToken;
    string public name;
    string public symbol;
    uint8 public decimals;
    uint8 public decimalsOffset;
    bool public initialized;

    function initialize(
        IERC20 underlyingToken_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint8 decimalsOffset_
    ) external {
        require(!initialized, "initialized");
        initialized = true;
        underlyingToken = underlyingToken_;
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        decimalsOffset = decimalsOffset_;
    }

    function asset() external view returns (address) {
        return address(underlyingToken);
    }
}

contract VaultFactoryTest is Test {
    bytes32 private constant VAULT_KEY = keccak256("VAULT");
    bytes32 private constant WRAPPED_TOKEN_KEY = keccak256("WRAPPED_TOKEN");
    bytes32 private constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address private admin = address(0xA11CE);
    address private processor = address(0xBEEF);
    address private pauser = address(0xCAFE);
    address private unpauser = address(0xD00D);
    address private feeManager = address(0xFEE);
    address private provider = address(0xF00D);
    address private bootstrapReceiver = address(0xB007);
    address private creator = address(0xC0DEC);

    IRegistry private registry;
    VaultFactory private factory;
    MockToken private asset;
    MockVault private vaultLogic;
    MockWrappedToken private wrappedTokenLogic;

    function setUp() public {
        Registry registryLogic = new Registry();
        RegistryProxy registryProxy =
            new RegistryProxy(address(registryLogic), abi.encodeCall(IRegistry.initialize, (address(this))));
        registry = IRegistry(address(registryProxy));

        factory = new VaultFactory(registry);
        asset = new MockToken(18);
        vaultLogic = new MockVault();
        wrappedTokenLogic = new MockWrappedToken();

        registry.setValue(VAULT_KEY, address(vaultLogic));
        registry.setValue(WRAPPED_TOKEN_KEY, address(wrappedTokenLogic));

        asset.mint(creator, 1 ether);
    }

    function testCreateVaultConfiguresMainVaultAndBootstraps() public {
        assertEq(factory.VERSION(), "0.1.0");

        vm.startPrank(creator);
        asset.approve(address(factory), 1 ether);
        IVaultFactory.CreatedVault memory created =
            factory.createVault(_vaultParams(1 ether), _registryKeys(), _emptyFlexParams());
        vm.stopPrank();

        assertEq(created.wrappedToken, address(0));
        MockVault vault = MockVault(created.vault);

        assertEq(vault.tokenName(), "RWA Vault");
        assertEq(vault.tokenSymbol(), "ynRWA");
        assertEq(vault.tokenDecimals(), 18);
        assertFalse(vault.countNativeAsset());
        assertTrue(vault.alwaysComputeTotalAssets());
        assertFalse(vault.paused());
        assertEq(vault.provider(), provider);
        assertEq(vault.buffer(), address(0));
        assertEq(vault.shareBalance(bootstrapReceiver), 1 ether);
        assertEq(asset.balanceOf(created.vault), 1 ether);

        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), created.timelock));
        assertTrue(vault.hasRole(vault.PROCESSOR_ROLE(), processor));
        assertTrue(vault.hasRole(vault.PAUSER_ROLE(), pauser));
        assertTrue(vault.hasRole(vault.UNPAUSER_ROLE(), unpauser));
        assertTrue(vault.hasRole(vault.FEE_MANAGER_ROLE(), feeManager));
        assertTrue(vault.hasRole(vault.PROVIDER_MANAGER_ROLE(), created.timelock));
        assertTrue(vault.hasRole(vault.BUFFER_MANAGER_ROLE(), created.timelock));
        assertTrue(vault.hasRole(vault.ASSET_MANAGER_ROLE(), created.timelock));
        assertTrue(vault.hasRole(vault.PROCESSOR_MANAGER_ROLE(), created.timelock));
        assertTrue(vault.hasRole(vault.HOOKS_MANAGER_ROLE(), created.timelock));

        assertFalse(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(factory)));
        assertFalse(vault.hasRole(vault.PROVIDER_MANAGER_ROLE(), address(factory)));
        assertFalse(vault.hasRole(vault.BUFFER_MANAGER_ROLE(), address(factory)));
        assertFalse(vault.hasRole(vault.ASSET_MANAGER_ROLE(), address(factory)));
        assertFalse(vault.hasRole(vault.PROCESSOR_MANAGER_ROLE(), address(factory)));
        assertFalse(vault.hasRole(vault.HOOKS_MANAGER_ROLE(), address(factory)));
        assertFalse(vault.hasRole(vault.UNPAUSER_ROLE(), address(factory)));

        address proxyAdmin = address(uint160(uint256(vm.load(created.vault, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(proxyAdmin).owner(), created.timelock);
    }

    function testCreateVaultWrapsNon18DecimalBaseAsset() public {
        MockToken usdc = new MockToken(6);
        usdc.mint(creator, 1e6);

        IVaultFactory.VaultParams memory params = _vaultParams(1e6);
        params.baseAsset = address(usdc);
        params.defaultAsset = address(usdc);

        vm.startPrank(creator);
        usdc.approve(address(factory), 1e6);
        IVaultFactory.CreatedVault memory created = factory.createVault(params, _registryKeys(), _emptyFlexParams());
        vm.stopPrank();

        assertTrue(created.wrappedToken != address(0));

        MockWrappedToken wrappedToken = MockWrappedToken(created.wrappedToken);
        assertEq(wrappedToken.asset(), address(usdc));
        assertEq(wrappedToken.name(), "Wrapped Asset");
        assertEq(wrappedToken.symbol(), "WAST");
        assertEq(wrappedToken.decimals(), 18);
        assertEq(wrappedToken.decimalsOffset(), 12);

        MockVault vault = MockVault(created.vault);
        assertEq(vault.assets(0), created.wrappedToken);
        assertTrue(vault.activeAsset(created.wrappedToken));
        assertEq(vault.assets(1), address(usdc));
        assertTrue(vault.activeAsset(address(usdc)));
        assertEq(vault.defaultAssetIndex(), 1);
        assertEq(vault.shareBalance(bootstrapReceiver), 1e6);
        assertEq(usdc.balanceOf(created.vault), 1e6);

        address wrapperProxyAdmin = address(uint160(uint256(vm.load(created.wrappedToken, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(wrapperProxyAdmin).owner(), created.timelock);
    }

    function testCreateVaultRevertsWhenFlexStrategyRequested() public {
        bytes memory deployData = abi.encode("flex config");
        IVaultFactory.FlexStrategyParams memory flexParams = IVaultFactory.FlexStrategyParams({
            deployStrategy: true, multisig: address(0x5AFE), offRampAddress: address(0x0FF), deployData: deployData
        });

        vm.startPrank(creator);
        asset.approve(address(factory), 1 ether);
        vm.expectRevert(IVaultFactory.FunctionalityUnavailable.selector);
        factory.createVault(_vaultParams(1 ether), _registryKeys(), flexParams);
        vm.stopPrank();
    }

    function testCreateVaultRevertsForMissingRegistryValue() public {
        IVaultFactory.RegistryKeys memory keys = _registryKeys();
        keys.vault = keccak256("MISSING");

        vm.startPrank(creator);
        asset.approve(address(factory), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IVaultFactory.MissingRegistryValue.selector, keys.vault));
        factory.createVault(_vaultParams(1 ether), keys, _emptyFlexParams());
        vm.stopPrank();
    }

    function testCreateVaultRevertsWhen18DecimalBaseDiffersFromDefaultAsset() public {
        MockToken defaultAsset = new MockToken(18);

        IVaultFactory.VaultParams memory params = _vaultParams(1 ether);
        params.defaultAsset = address(defaultAsset);

        vm.startPrank(creator);
        asset.approve(address(factory), 1 ether);
        vm.expectRevert(IVaultFactory.InvalidDefaultAsset.selector);
        factory.createVault(params, _registryKeys(), _emptyFlexParams());
        vm.stopPrank();
    }

    function _vaultParams(uint256 bootstrapAmount) internal view returns (IVaultFactory.VaultParams memory) {
        return IVaultFactory.VaultParams({
            admin: admin,
            processor: processor,
            pauser: pauser,
            unpauser: unpauser,
            feeManager: feeManager,
            baseAsset: address(asset),
            defaultAsset: address(asset),
            provider: provider,
            tokenName: "RWA Vault",
            tokenSymbol: "ynRWA",
            countNativeAsset: false,
            alwaysComputeTotalAssets: true,
            timelockDuration: 1 days,
            bootstrapAmount: bootstrapAmount,
            bootstrapReceiver: bootstrapReceiver
        });
    }

    function _registryKeys() internal pure returns (IVaultFactory.RegistryKeys memory) {
        return IVaultFactory.RegistryKeys({vault: VAULT_KEY, wrappedToken: WRAPPED_TOKEN_KEY});
    }

    function _emptyFlexParams() internal pure returns (IVaultFactory.FlexStrategyParams memory) {
        return IVaultFactory.FlexStrategyParams({
            deployStrategy: false, multisig: address(0), offRampAddress: address(0), deployData: ""
        });
    }
}

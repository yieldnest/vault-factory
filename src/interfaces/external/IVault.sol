// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IVault {
    enum ParamType {
        UINT256,
        ADDRESS
    }

    struct ParamRule {
        ParamType paramType;
        bool isArray;
        address[] allowList;
    }

    struct FunctionRule {
        bool isActive;
        ParamRule[] paramRules;
        address validator;
    }

    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint64 baseWithdrawalFee_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_,
        uint256 defaultAssetIndex_
    ) external;

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function PROCESSOR_ROLE() external view returns (bytes32);
    function PAUSER_ROLE() external view returns (bytes32);
    function UNPAUSER_ROLE() external view returns (bytes32);
    function PROVIDER_MANAGER_ROLE() external view returns (bytes32);
    function BUFFER_MANAGER_ROLE() external view returns (bytes32);
    function ASSET_MANAGER_ROLE() external view returns (bytes32);
    function PROCESSOR_MANAGER_ROLE() external view returns (bytes32);
    function HOOKS_MANAGER_ROLE() external view returns (bytes32);
    function FEE_MANAGER_ROLE() external view returns (bytes32);
    function ASSET_WITHDRAWER_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;

    function addAsset(address asset, bool active) external;
    function setProvider(address provider) external;
    function setBuffer(address buffer) external;
    function unpause() external;
    function setProcessorRule(address target, bytes4 functionSig, FunctionRule calldata rule) external;
    function processAccounting() external;
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function asset() external view returns (address);
    function countNativeAsset() external view returns (bool);
    function alwaysComputeTotalAssets() external view returns (bool);
    function baseWithdrawalFee() external view returns (uint64);
    function defaultAssetIndex() external view returns (uint256);
    function provider() external view returns (address);
    function buffer() external view returns (address);
    function paused() external view returns (bool);
    function hooks() external view returns (address);
    function getAssets() external view returns (address[] memory);
    function getProcessorRule(address contractAddress, bytes4 funcSig) external view returns (FunctionRule memory);
}

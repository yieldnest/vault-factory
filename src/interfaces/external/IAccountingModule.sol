// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IAccountingModule {
    function initialize(
        address strategy_,
        address admin,
        address safe_,
        address accountingToken_,
        uint256 targetApy_,
        uint256 lowerBound_,
        uint256 minRewardableAssets_,
        uint16 cooldownSeconds_
    ) external;

    function grantRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;

    function baseAsset() external view returns (address);
    function strategy() external view returns (address);
    function accountingToken() external view returns (address);
    function safe() external view returns (address);
    function targetApy() external view returns (uint256);
    function lowerBound() external view returns (uint256);
    function cooldownSeconds() external view returns (uint16);
}

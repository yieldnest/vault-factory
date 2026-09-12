// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interfaces/external/IVault.sol";

interface IFlexStrategy is IVault {
    function initialize(
        address admin,
        address accountingModuleManager,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        address baseAsset,
        address accountingToken,
        bool paused_,
        address provider,
        bool alwaysComputeTotalAssets
    ) external;

    function setHasAllocator(bool hasAllocators_) external;
    function setAccountingModule(address accountingModule_) external;
    function setHooks(address hooks_) external;

    function accountingModule() external view returns (address);
    function getHasAllocator() external view returns (bool);
}

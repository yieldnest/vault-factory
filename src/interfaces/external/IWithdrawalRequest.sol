// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IWithdrawalRequest {
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function PAUSER_ROLE() external view returns (bytes32);

    function initialize(
        address token_,
        address defaultAdmin,
        address resolver,
        address configurationManager,
        address pauser,
        address bagFactory_,
        address withdrawer_,
        address requestPolicy_,
        uint256 maxDataLength_
    ) external;

    function token() external view returns (address);
    function grantRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;
    function bagFactory() external view returns (address);
    function withdrawer() external view returns (address);
    function requestPolicy() external view returns (address);
    function maxDataLength() external view returns (uint256);
}

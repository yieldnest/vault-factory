// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IRequestPolicy {
    function validateRequest(address requester, address owner, uint256 amount, bytes calldata data) external view;
}

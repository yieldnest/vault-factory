// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IImplementationRegistry {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ImplementationUpdated(
        bytes32 indexed key, address indexed previousImplementation, address indexed implementation
    );

    error AlreadyInitialized();
    error EmptyKey();
    error InvalidArrayLength();
    error NotOwner(address caller);
    error ZeroAddress();

    function initialize(address owner_) external;

    function owner() external view returns (address);

    function transferOwnership(address newOwner) external;

    function implementationId(string calldata key) external pure returns (bytes32);

    function implementationOf(bytes32 key) external view returns (address);

    function implementationOf(string calldata key) external view returns (address);

    function setImplementation(bytes32 key, address implementation) external;

    function setImplementation(string calldata key, address implementation) external;

    function setImplementations(bytes32[] calldata keys, address[] calldata implementations) external;

    function setImplementations(string[] calldata keys, address[] calldata implementations) external;
}

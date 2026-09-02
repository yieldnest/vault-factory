// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IImplementationRegistry} from "src/interfaces/IImplementationRegistry.sol";

contract ImplementationRegistry is IImplementationRegistry {
    mapping(bytes32 key => address implementation) private _implementations;

    address private _owner;
    bool private _initialized;

    uint256[48] private __gap;

    constructor() {
        _initialized = true;
    }

    modifier initializer() {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert NotOwner(msg.sender);
        _;
    }

    function initialize(address owner_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        _owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();

        address previousOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function implementationId(string calldata key) external pure returns (bytes32) {
        return _implementationId(key);
    }

    function implementationOf(bytes32 key) external view returns (address) {
        return _implementations[key];
    }

    function implementationOf(string calldata key) external view returns (address) {
        return _implementations[_implementationId(key)];
    }

    function setImplementation(bytes32 key, address implementation) external onlyOwner {
        _setImplementation(key, implementation);
    }

    function setImplementation(string calldata key, address implementation) external onlyOwner {
        _setImplementation(_implementationId(key), implementation);
    }

    function setImplementations(bytes32[] calldata keys, address[] calldata implementations) external onlyOwner {
        _setImplementations(keys, implementations);
    }

    function setImplementations(string[] calldata keys, address[] calldata implementations) external onlyOwner {
        uint256 length = keys.length;
        if (length != implementations.length) revert InvalidArrayLength();

        for (uint256 i = 0; i < length; ++i) {
            _setImplementation(_implementationId(keys[i]), implementations[i]);
        }
    }

    function _setImplementations(bytes32[] calldata keys, address[] calldata implementations) internal {
        uint256 length = keys.length;
        if (length != implementations.length) revert InvalidArrayLength();

        for (uint256 i = 0; i < length; ++i) {
            _setImplementation(keys[i], implementations[i]);
        }
    }

    function _setImplementation(bytes32 key, address implementation) internal {
        if (key == bytes32(0)) revert EmptyKey();
        if (implementation == address(0)) revert ZeroAddress();

        address previousImplementation = _implementations[key];
        _implementations[key] = implementation;

        emit ImplementationUpdated(key, previousImplementation, implementation);
    }

    function _implementationId(string calldata key) internal pure returns (bytes32) {
        if (bytes(key).length == 0) revert EmptyKey();
        return keccak256(bytes(key));
    }
}

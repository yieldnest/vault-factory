// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IRegistry} from "src/interfaces/IRegistry.sol";

contract Registry is IRegistry {
    mapping(bytes32 key => address value) private _values;

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

    function keyOf(string calldata key) external pure returns (bytes32) {
        return _keyOf(key);
    }

    function valueOf(bytes32 key) external view returns (address) {
        return _values[key];
    }

    function valueOf(string calldata key) external view returns (address) {
        return _values[_keyOf(key)];
    }

    function setValue(bytes32 key, address value) external onlyOwner {
        _setValue(key, value);
    }

    function setValue(string calldata key, address value) external onlyOwner {
        _setValue(_keyOf(key), value);
    }

    function setValues(bytes32[] calldata keys, address[] calldata values) external onlyOwner {
        _setValues(keys, values);
    }

    function setValues(string[] calldata keys, address[] calldata values) external onlyOwner {
        uint256 length = keys.length;
        if (length != values.length) revert InvalidArrayLength();

        for (uint256 i = 0; i < length; ++i) {
            _setValue(_keyOf(keys[i]), values[i]);
        }
    }

    function _setValues(bytes32[] calldata keys, address[] calldata values) internal {
        uint256 length = keys.length;
        if (length != values.length) revert InvalidArrayLength();

        for (uint256 i = 0; i < length; ++i) {
            _setValue(keys[i], values[i]);
        }
    }

    function _setValue(bytes32 key, address value) internal {
        if (key == bytes32(0)) revert EmptyKey();
        if (value == address(0)) revert ZeroAddress();

        address previousValue = _values[key];
        _values[key] = value;

        emit ValueUpdated(key, previousValue, value);
    }

    function _keyOf(string calldata key) internal pure returns (bytes32) {
        if (bytes(key).length == 0) revert EmptyKey();
        return keccak256(bytes(key));
    }
}

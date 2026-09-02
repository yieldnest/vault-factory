// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ImplementationRegistry} from "src/ImplementationRegistry.sol";
import {IImplementationRegistry} from "src/interfaces/IImplementationRegistry.sol";

contract MinimalProxy {
    address public immutable implementation;

    constructor(address implementation_, bytes memory initData) {
        implementation = implementation_;

        if (initData.length != 0) {
            (bool success, bytes memory returnData) = implementation_.delegatecall(initData);
            if (!success) {
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }
    }

    receive() external payable {}

    fallback() external payable {
        address implementation_ = implementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

contract ImplementationRegistryTest is Test {
    address private owner = address(0xA11CE);
    address private other = address(0xB0B);

    IImplementationRegistry private registry;

    function setUp() public {
        ImplementationRegistry implementation = new ImplementationRegistry();
        MinimalProxy proxy =
            new MinimalProxy(address(implementation), abi.encodeCall(IImplementationRegistry.initialize, (owner)));
        registry = IImplementationRegistry(address(proxy));
    }

    function testInitializeSetsOwner() public view {
        assertEq(registry.owner(), owner);
    }

    function testImplementationCannotBeInitializedDirectly() public {
        ImplementationRegistry implementation = new ImplementationRegistry();

        vm.expectRevert(IImplementationRegistry.AlreadyInitialized.selector);
        implementation.initialize(owner);
    }

    function testSetImplementationWithBytes32Key() public {
        bytes32 key = keccak256("VAULT_V0_4_2");
        address implementation = address(0x1234);

        vm.prank(owner);
        registry.setImplementation(key, implementation);

        assertEq(registry.implementationOf(key), implementation);
    }

    function testSetImplementationWithStringKey() public {
        string memory key = "VAULT_V0_4_2";
        address implementation = address(0x1234);
        bytes32 expectedKey = keccak256(bytes(key));

        vm.prank(owner);
        registry.setImplementation(key, implementation);

        assertEq(registry.implementationId(key), expectedKey);
        assertEq(registry.implementationOf(expectedKey), implementation);
        assertEq(registry.implementationOf(key), implementation);
    }

    function testBulkSetImplementationsWithBytes32Keys() public {
        bytes32[] memory keys = new bytes32[](2);
        keys[0] = keccak256("VAULT_V0_4_2");
        keys[1] = keccak256("FLEX_STRATEGY_V0_1_0");

        address[] memory implementations = new address[](2);
        implementations[0] = address(0x1234);
        implementations[1] = address(0x5678);

        vm.prank(owner);
        registry.setImplementations(keys, implementations);

        assertEq(registry.implementationOf(keys[0]), implementations[0]);
        assertEq(registry.implementationOf(keys[1]), implementations[1]);
    }

    function testBulkSetImplementationsWithStringKeys() public {
        string[] memory keys = new string[](2);
        keys[0] = "VAULT_V0_4_2";
        keys[1] = "FLEX_STRATEGY_V0_1_0";

        address[] memory implementations = new address[](2);
        implementations[0] = address(0x1234);
        implementations[1] = address(0x5678);

        vm.prank(owner);
        registry.setImplementations(keys, implementations);

        assertEq(registry.implementationOf(keys[0]), implementations[0]);
        assertEq(registry.implementationOf(keys[1]), implementations[1]);
    }

    function testOnlyOwnerCanSetImplementations() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IImplementationRegistry.NotOwner.selector, other));
        registry.setImplementation(keccak256("VAULT_V0_4_2"), address(0x1234));
    }

    function testRejectsEmptyKey() public {
        vm.prank(owner);
        vm.expectRevert(IImplementationRegistry.EmptyKey.selector);
        registry.setImplementation(bytes32(0), address(0x1234));
    }

    function testRejectsZeroImplementation() public {
        vm.prank(owner);
        vm.expectRevert(IImplementationRegistry.ZeroAddress.selector);
        registry.setImplementation(keccak256("VAULT_V0_4_2"), address(0));
    }

    function testRejectsMismatchedBulkArrays() public {
        bytes32[] memory keys = new bytes32[](1);
        address[] memory implementations = new address[](2);

        vm.prank(owner);
        vm.expectRevert(IImplementationRegistry.InvalidArrayLength.selector);
        registry.setImplementations(keys, implementations);
    }

    function testOwnerCanTransferOwnership() public {
        vm.prank(owner);
        registry.transferOwnership(other);

        assertEq(registry.owner(), other);
    }
}

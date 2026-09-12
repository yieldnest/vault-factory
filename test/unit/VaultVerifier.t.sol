// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultVerifier, IAccessControlView, IVaultView} from "src/VaultVerifier.sol";
import {IERC20Metadata} from "src/interfaces/external/IERC20Metadata.sol";
import {IVault} from "src/interfaces/external/IVault.sol";

contract VaultVerifierHarness is VaultVerifier, Test {
    function verifyRole(address target, bytes32 role, address account, bool expected) external view {
        _verifyRole(IAccessControlView(target), role, account, expected, "role check");
    }

    function decimals(address target) external view returns (uint8) {
        return _decimals(target);
    }

    function getRule(address target, address asset, bytes4 selector)
        external
        view
        returns (IVault.FunctionRule memory)
    {
        return _getRule(target, asset, selector);
    }
}

contract VaultVerifierTest is Test {
    VaultVerifierHarness internal harness;
    address internal constant TARGET = address(0x1234);

    function setUp() public {
        harness = new VaultVerifierHarness();
    }

    function test_RuntimeFitsDeploymentLimit() public {
        VaultVerifier verifier = new VaultVerifier();
        assertLe(address(verifier).code.length, 24_576);
    }

    function testFuzz_RoleCheckPreservesExpectation(bytes32 role, address account, bool actual, bool expected) public {
        vm.mockCall(TARGET, abi.encodeCall(IAccessControlView.hasRole, (role, account)), abi.encode(actual));
        if (actual != expected) {
            vm.expectRevert(abi.encodeWithSelector(VaultVerifier.VerificationFailed.selector, "role check"));
        }
        harness.verifyRole(TARGET, role, account, expected);
    }

    function test_RoleCheckRejectsMalformedBool() public {
        vm.mockCall(TARGET, abi.encodeCall(IAccessControlView.hasRole, (bytes32(0), TARGET)), abi.encode(uint256(2)));
        vm.expectRevert();
        harness.verifyRole(TARGET, bytes32(0), TARGET, false);
    }

    function test_RoleCheckBubblesRevert() public {
        vm.mockCallRevert(TARGET, abi.encodeWithSelector(IAccessControlView.hasRole.selector), hex"deadbeef");
        vm.expectRevert(bytes(hex"deadbeef"));
        harness.verifyRole(TARGET, bytes32(0), TARGET, true);
    }

    function test_RoleCheckRejectsEmptyReturn() public {
        vm.mockCall(TARGET, abi.encodeWithSelector(IAccessControlView.hasRole.selector), bytes(""));
        vm.expectRevert();
        harness.verifyRole(TARGET, bytes32(0), TARGET, false);
    }

    function testFuzz_DecimalsPreservesUint8(uint8 value) public {
        vm.mockCall(TARGET, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(value));
        assertEq(harness.decimals(TARGET), value);
    }

    function test_DecimalsRejectsOverflow() public {
        vm.mockCall(TARGET, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(uint256(256)));
        vm.expectRevert();
        harness.decimals(TARGET);
    }

    function testFuzz_ProcessorRulePreservesDynamicReturn(address asset, bytes4 selector, address allowed) public {
        IVault.ParamRule[] memory params = new IVault.ParamRule[](2);
        params[0] = IVault.ParamRule(IVault.ParamType.UINT256, false, new address[](0));
        address[] memory allowList = new address[](1);
        allowList[0] = allowed;
        params[1] = IVault.ParamRule(IVault.ParamType.ADDRESS, false, allowList);
        IVault.FunctionRule memory rule = IVault.FunctionRule(true, params, address(0));
        vm.mockCall(TARGET, abi.encodeCall(IVault.getProcessorRule, (asset, selector)), abi.encode(rule));
        assertEq(abi.encode(harness.getRule(TARGET, asset, selector)), abi.encode(rule));
    }

    function test_ProcessorRuleRejectsEmptyReturn() public {
        vm.mockCall(TARGET, abi.encodeWithSelector(IVault.getProcessorRule.selector), bytes(""));
        vm.expectRevert();
        harness.getRule(TARGET, TARGET, bytes4(0));
    }

    function test_VerifyRejectsVaultMismatch() public {
        VaultVerifier.Verification memory verification;
        vm.expectRevert(abi.encodeWithSelector(VaultVerifier.VerificationFailed.selector, "vault mismatch"));
        harness.verify(TARGET, verification);
    }
}

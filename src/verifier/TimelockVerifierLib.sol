// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

library TimelockVerifierLib {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 internal constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    error VerificationFailed(string check);

    function verify(address timelock, address admin, address proposer, address factory) external view {
        IAccessControlView access = IAccessControlView(timelock);

        _verify(timelock != address(0) && timelock.code.length != 0, "tl0");
        _verify(admin != proposer, "tl1");

        _verifyRole(access, DEFAULT_ADMIN_ROLE, admin, true, "tl2");
        _verifyRole(access, CANCELLER_ROLE, admin, true, "tl3");
        _verifyRole(access, PROPOSER_ROLE, admin, false, "tl4");
        _verifyRole(access, EXECUTOR_ROLE, admin, false, "tl5");

        _verifyRole(access, PROPOSER_ROLE, proposer, true, "tl6");
        _verifyRole(access, EXECUTOR_ROLE, proposer, true, "tl7");
        _verifyRole(access, CANCELLER_ROLE, proposer, true, "tl8");
        _verifyRole(access, DEFAULT_ADMIN_ROLE, proposer, false, "tl9");

        _verifyRole(access, DEFAULT_ADMIN_ROLE, factory, false, "tl10");
        _verifyRole(access, PROPOSER_ROLE, factory, false, "tl11");
        _verifyRole(access, EXECUTOR_ROLE, factory, false, "tl12");
        _verifyRole(access, CANCELLER_ROLE, factory, false, "tl13");
    }

    function _verifyRole(IAccessControlView target, bytes32 role, address account, bool expected, string memory check)
        internal
        view
    {
        _verify(target.hasRole(role, account) == expected, check);
    }

    function _verify(bool condition, string memory check) internal pure {
        if (!condition) revert VerificationFailed(check);
    }
}

interface IAccessControlView {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

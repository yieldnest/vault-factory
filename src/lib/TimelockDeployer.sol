// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title TimelockDeployer
/// @notice Deploys the per-vault TimelockController.
/// @dev External library so the TimelockController creation code lives in the deployed library
/// instead of the factory bytecode, keeping the factory under the EIP-170 size limit. The
/// delegatecall runs CREATE in the factory's context, so the timelock's deployer is still the
/// factory.
library TimelockDeployer {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    function deploy(address admin, address proposer, uint256 timelockDuration) external returns (TimelockController) {
        return deployWithTemporaryAdmin(admin, proposer, timelockDuration, address(this));
    }

    /// @dev Script-friendly variant. It uses `admin` as the constructor admin directly because
    /// forge scripts do not execute follow-up role wiring from `address(this)` the same way the
    /// factory does through the external library delegatecall.
    function deployInline(address admin, address proposer, uint256 timelockDuration)
        internal
        returns (TimelockController)
    {
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;

        address[] memory executors = new address[](1);
        executors[0] = proposer;

        // The proposer receives PROPOSER_ROLE and EXECUTOR_ROLE. OpenZeppelin TimelockController
        // also auto-grants CANCELLER_ROLE to every proposer. The admin receives only
        // DEFAULT_ADMIN_ROLE in this script-friendly path.
        return new TimelockController(timelockDuration, proposers, executors, admin);
    }

    function deployWithTemporaryAdmin(address admin, address proposer, uint256 timelockDuration, address temporaryAdmin)
        internal
        returns (TimelockController timelock)
    {
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;

        address[] memory executors = new address[](1);
        executors[0] = proposer;

        // The proposer receives PROPOSER_ROLE, EXECUTOR_ROLE, and CANCELLER_ROLE through the
        // TimelockController constructor, but never DEFAULT_ADMIN_ROLE. The temporary admin is
        // removed after granting the supervisory admin DEFAULT_ADMIN_ROLE and CANCELLER_ROLE.
        timelock = new TimelockController(timelockDuration, proposers, executors, temporaryAdmin);
        timelock.grantRole(DEFAULT_ADMIN_ROLE, admin);
        timelock.grantRole(CANCELLER_ROLE, admin);
        timelock.renounceRole(DEFAULT_ADMIN_ROLE, temporaryAdmin);
    }
}

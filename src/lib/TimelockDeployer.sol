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
    function deploy(address admin, address proposer, uint256 timelockDuration) external returns (TimelockController) {
        return deployInline(admin, proposer, timelockDuration);
    }

    function deployInline(address admin, address proposer, uint256 timelockDuration)
        internal
        returns (TimelockController)
    {
        address[] memory proposers = new address[](2);
        proposers[0] = proposer;
        proposers[1] = admin;

        address[] memory executors = new address[](2);
        executors[0] = proposer;
        executors[1] = admin;

        // The proposer and admin receive PROPOSER_ROLE and EXECUTOR_ROLE. OpenZeppelin
        // TimelockController also auto-grants CANCELLER_ROLE to every proposer.
        // The admin additionally receives DEFAULT_ADMIN_ROLE through the constructor admin.
        return new TimelockController(timelockDuration, proposers, executors, admin);
    }
}

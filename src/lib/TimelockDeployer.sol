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
    function deploy(address admin, uint256 timelockDuration) external returns (TimelockController) {
        address[] memory proposers = new address[](1);
        proposers[0] = admin;

        address[] memory executors = new address[](1);
        executors[0] = admin;

        return new TimelockController(timelockDuration, proposers, executors, address(0));
    }
}

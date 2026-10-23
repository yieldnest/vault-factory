// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {PauserHook} from "lib/yieldnest-vault-periphery/src/hooks/PauserHook.sol";

library PauserHookDeployer {
    function deploy(address vault, address admin, address pauser, address unpauser) external returns (address) {
        return address(new PauserHook(vault, admin, pauser, unpauser));
    }
}

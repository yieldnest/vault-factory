// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {VaultFactory} from "src/VaultFactory.sol";

contract DeployVaultFactory is Script {
    function run(address registry) external returns (VaultFactory factory) {
        require(registry != address(0), "registry");

        vm.startBroadcast();
        factory = new VaultFactory(IRegistry(registry));
        vm.stopBroadcast();

        console2.log("VaultFactory:", address(factory));
        console2.log("Registry:", registry);
    }
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {Registry} from "src/Registry.sol";

contract DeployRegistry is Script {
    function run(address admin, uint256 minDelay)
        external
        returns (Registry implementation, TimelockController timelock, IRegistry registry)
    {
        require(admin != address(0), "admin");

        address[] memory proposers = new address[](1);
        proposers[0] = admin;

        address[] memory executors = new address[](1);
        executors[0] = admin;

        vm.startBroadcast();

        implementation = new Registry();
        timelock = new TimelockController(minDelay, proposers, executors, address(0));

        bytes memory initData = abi.encodeCall(IRegistry.initialize, (address(timelock)));
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(timelock), initData);
        registry = IRegistry(address(proxy));

        vm.stopBroadcast();

        console2.log("Registry implementation:", address(implementation));
        console2.log("Registry proxy:", address(registry));
        console2.log("Registry timelock:", address(timelock));
    }
}

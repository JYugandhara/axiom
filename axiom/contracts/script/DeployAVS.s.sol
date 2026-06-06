// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {OperatorRegistry}    from "../src/avs/OperatorRegistry.sol";
import {AxiomTaskManager}    from "../src/avs/AxiomTaskManager.sol";
import {AxiomServiceManager} from "../src/avs/AxiomServiceManager.sol";

/// @title DeployAVS
/// @notice Deploys the EigenLayer AVS contracts to Arbitrum One.
///
/// Usage:
///   forge script script/DeployAVS.s.sol \
///     --rpc-url $L2_RPC_URL \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast -vvvv
contract DeployAVS is Script {
    function run() external {
        uint256 pk  = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address dao = vm.envAddress("DAO_ADDRESS");

        vm.startBroadcast(pk);

        OperatorRegistry registry = new OperatorRegistry(dao);
        AxiomTaskManager taskManager = new AxiomTaskManager(dao, address(registry));
        AxiomServiceManager serviceManager = new AxiomServiceManager(
            dao,
            address(registry),
            address(taskManager),
            dao // slashing vault = DAO treasury initially
        );

        // Grant the registry's REGISTRAR_ROLE to the task manager
        // so it can record operator task completions.
        registry.grantRole(registry.REGISTRAR_ROLE(), address(taskManager));

        console.log("=================================================");
        console.log("AXIOM AVS — Deployed to Arbitrum");
        console.log("=================================================");
        console.log("OperatorRegistry    :", address(registry));
        console.log("AxiomTaskManager    :", address(taskManager));
        console.log("AxiomServiceManager :", address(serviceManager));

        vm.stopBroadcast();

        string memory json = string.concat(
            '{"taskManager":"',     vm.toString(address(taskManager)),
            '","serviceManager":"', vm.toString(address(serviceManager)),
            '","registry":"',       vm.toString(address(registry)), '"}'
        );
        vm.writeFile("./deployments/avs-addresses.json", json);
    }
}

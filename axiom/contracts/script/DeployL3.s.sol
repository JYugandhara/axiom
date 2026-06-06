// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {AxiomWorld} from "../src/mud/AxiomWorld.sol";

/// @title DeployL3
/// @notice Deploys the MUD world (tables + systems) to the AXIOM L3.
///
/// Usage:
///   forge script script/DeployL3.s.sol \
///     --rpc-url http://localhost:8545 \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast -vvvv
contract DeployL3 is Script {
    function run() external {
        uint256 pk  = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address dao = vm.envAddress("DAO_ADDRESS");

        address fogVerifier       = vm.envAddress("FOG_VERIFIER_ADDRESS");
        address territoryVerifier = vm.envAddress("TERRITORY_VERIFIER_ADDRESS");
        address aiVerifier        = vm.envAddress("AI_VERIFIER_ADDRESS");
        address energy            = vm.envAddress("ENERGY_TOKEN");
        address civNFT            = vm.envAddress("CIV_NFT");
        address taskManager       = vm.envAddress("TASK_MANAGER_ADDRESS");
        address automation        = vm.envAddress("CHAINLINK_AUTOMATION");

        vm.startBroadcast(pk);

        AxiomWorld world = new AxiomWorld(
            dao, fogVerifier, territoryVerifier, aiVerifier,
            energy, civNFT, taskManager, automation
        );

        console.log("=================================================");
        console.log("AXIOM L3 — MUD World Deployed");
        console.log("=================================================");
        console.log("AxiomWorld        :", address(world));
        console.log("  CivilizationState:", address(world.civState()));
        console.log("  TerritoryMap     :", address(world.territoryMap()));
        console.log("  AgentActions     :", address(world.agentActions()));
        console.log("  BattleHistory    :", address(world.battleHistory()));
        console.log("  GameConfig       :", address(world.gameConfig()));
        console.log("  MoveSystem       :", address(world.moveSystem()));
        console.log("  ClaimSystem      :", address(world.claimSystem()));
        console.log("  BattleSystem     :", address(world.battleSystem()));
        console.log("  AgentSystem      :", address(world.agentSystem()));
        console.log("  EnergySystem     :", address(world.energySystem()));

        vm.stopBroadcast();

        string memory json = string.concat(
            '{"world":"',        vm.toString(address(world)),
            '","moveSystem":"',  vm.toString(address(world.moveSystem())),
            '","claimSystem":"', vm.toString(address(world.claimSystem())),
            '","battleSystem":"',vm.toString(address(world.battleSystem())),
            '","agentSystem":"', vm.toString(address(world.agentSystem())),
            '","territoryMap":"',vm.toString(address(world.territoryMap())),
            '"}'
        );
        vm.writeFile("./deployments/l3-addresses.json", json);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {AXMToken}         from "../src/economy/AXMToken.sol";
import {EnergyToken}      from "../src/economy/EnergyToken.sol";
import {WorldTreasury}    from "../src/economy/WorldTreasury.sol";
import {Staking}          from "../src/economy/Staking.sol";
import {Marketplace}      from "../src/economy/Marketplace.sol";
import {PredictionMarket} from "../src/economy/PredictionMarket.sol";

/// @title DeployEconomy
/// @notice Deploys all token + DeFi contracts.
///         $AXM on mainnet/L2; $ENERGY, Staking, Market on L3.
///
/// Usage:
///   forge script script/DeployEconomy.s.sol \
///     --rpc-url $L2_RPC_URL \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast -vvvv
contract DeployEconomy is Script {
    function run() external {
        uint256 pk  = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address dao = vm.envAddress("DAO_ADDRESS");

        vm.startBroadcast(pk);

        // 1. Governance token
        AXMToken axm = new AXMToken(dao);

        // 2. Treasury vault
        WorldTreasury treasury = new WorldTreasury(dao);

        // 3. In-game energy token (world set as minter later)
        EnergyToken energy = new EnergyToken(dao);

        // 4. Staking — lock AXM → energy boost
        Staking staking = new Staking(address(axm), address(energy), address(treasury));
        // Staking needs MINTER_ROLE on energy to pay rewards
        energy.grantMinter(address(staking));

        // 5. Marketplace
        Marketplace market = new Marketplace(address(axm), address(treasury));

        // 6. Prediction market
        PredictionMarket prediction = new PredictionMarket(address(axm), address(treasury), dao);

        console.log("=================================================");
        console.log("AXIOM Economy — Deployed");
        console.log("=================================================");
        console.log("AXMToken        :", address(axm));
        console.log("EnergyToken     :", address(energy));
        console.log("WorldTreasury   :", address(treasury));
        console.log("Staking         :", address(staking));
        console.log("Marketplace     :", address(market));
        console.log("PredictionMarket:", address(prediction));

        vm.stopBroadcast();

        string memory json = string.concat(
            '{"axm":"',               vm.toString(address(axm)),
            '","energy":"',           vm.toString(address(energy)),
            '","treasury":"',         vm.toString(address(treasury)),
            '","staking":"',          vm.toString(address(staking)),
            '","marketplace":"',      vm.toString(address(market)),
            '","predictionMarket":"', vm.toString(address(prediction)), '"}'
        );
        vm.writeFile("./deployments/economy-addresses.json", json);
    }
}

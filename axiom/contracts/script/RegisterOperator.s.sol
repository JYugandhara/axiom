// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/avs/AxiomTaskManager.sol";

/// @title RegisterOperator
/// @notice Run by each AVS operator on first startup to register
///         with EigenLayer and stake the minimum required amount.
///
/// Usage (from contracts/ in WSL):
///   forge script script/RegisterOperator.s.sol \
///     --rpc-url $L2_RPC_URL \
///     --private-key $OPERATOR_PRIVATE_KEY \
///     --broadcast -vvvv
contract RegisterOperator is Script {
    function run() external {
        uint256  operatorKey     = vm.envUint("OPERATOR_PRIVATE_KEY");
        address  registryAddr    = vm.envAddress("OPERATOR_REGISTRY_ADDRESS");
        address  serviceManager  = vm.envAddress("SERVICE_MANAGER_ADDRESS");
        uint256  stakeAmount     = vm.envOr("STAKE_AMOUNT", uint256(1000e18));

        address operator = vm.addr(operatorKey);
        console.log("=================================================");
        console.log("AXIOM AVS — Operator Registration");
        console.log("=================================================");
        console.log("Operator address :", operator);
        console.log("Registry         :", registryAddr);
        console.log("Service Manager  :", serviceManager);
        console.log("Stake amount     :", stakeAmount / 1e18, "AXM");

        OperatorRegistry registry = OperatorRegistry(registryAddr);

        // Check if already registered
        if (registry.isRegistered(operator)) {
            console.log("[SKIP] Operator already registered");
            return;
        }

        vm.startBroadcast(operatorKey);

        // Approve AXM spend for staking (if using token stake)
        // In production: approve before calling register
        // IERC20(axmToken).approve(registryAddr, stakeAmount);

        // Register with EigenLayer AVS
        AxiomServiceManager(serviceManager).registerOperatorToAVS(operator, stakeAmount);

        vm.stopBroadcast();

        console.log("");
        console.log("[OK] Operator registered successfully");
        console.log("     You can now start the avs-operator node:");
        console.log("     cd avs-operator && cargo run -- --env testnet");
        console.log("=================================================");

        // Verify registration
        bool isReg = registry.isRegistered(operator);
        require(isReg, "Registration verification failed");
        console.log("[OK] Registration verified on-chain");
    }
}

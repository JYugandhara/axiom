// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import {CivilizationStateStore} from "./tables/CivilizationState.sol";
import {TerritoryMapStore}      from "./tables/TerritoryMap.sol";
import {AgentActionsStore}      from "./tables/AgentActions.sol";
import {BattleHistoryStore}     from "./tables/BattleHistory.sol";
import {GameConfigStore}        from "./tables/GameConfig.sol";
import {MoveSystem}             from "./systems/MoveSystem.sol";
import {ClaimSystem}            from "./systems/ClaimSystem.sol";
import {BattleSystem}           from "./systems/BattleSystem.sol";
import {AgentSystem}            from "./systems/AgentSystem.sol";
import {EnergySystem}           from "./systems/EnergySystem.sol";

/// @title AxiomWorld
/// @notice MUD v2 World entry point. Deploys and wires all tables and systems.
///         Single deploy target — the entire game state lives here.
contract AxiomWorld is AccessControl, Pausable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ── Tables ─────────────────────────────────────────────────
    CivilizationStateStore public civState;
    TerritoryMapStore      public territoryMap;
    AgentActionsStore      public agentActions;
    BattleHistoryStore     public battleHistory;
    GameConfigStore        public gameConfig;

    // ── Systems ────────────────────────────────────────────────
    MoveSystem   public moveSystem;
    ClaimSystem  public claimSystem;
    BattleSystem public battleSystem;
    AgentSystem  public agentSystem;
    EnergySystem public energySystem;

    event WorldDeployed(address indexed deployer, uint256 chainId);

    constructor(
        address dao,
        address fogVerifier,
        address territoryVerifier,
        address aiVerifier,
        address energy,
        address civNFT,
        address taskManager,
        address automation
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, dao);
        _grantRole(OPERATOR_ROLE, dao);

        // Deploy tables (this contract is the authorized "world")
        civState      = new CivilizationStateStore(address(this));
        territoryMap  = new TerritoryMapStore(address(this));
        agentActions  = new AgentActionsStore(address(this));
        battleHistory = new BattleHistoryStore(address(this));
        gameConfig    = new GameConfigStore(address(this), dao);

        // Deploy systems
        moveSystem = new MoveSystem(
            fogVerifier, address(territoryMap), address(civState), address(gameConfig)
        );
        claimSystem = new ClaimSystem(
            territoryVerifier, address(territoryMap), address(civState), address(gameConfig)
        );
        battleSystem = new BattleSystem(
            address(civState), address(territoryMap), address(battleHistory),
            address(gameConfig), taskManager
        );
        agentSystem = new AgentSystem(
            aiVerifier, address(agentActions), address(civState), taskManager
        );
        energySystem = new EnergySystem(
            energy, address(civState), civNFT, automation
        );

        emit WorldDeployed(msg.sender, block.chainid);
    }

    function pause()   external onlyRole(OPERATOR_ROLE) { _pause(); }
    function unpause() external onlyRole(OPERATOR_ROLE) { _unpause(); }
}

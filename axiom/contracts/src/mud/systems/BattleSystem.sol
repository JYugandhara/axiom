// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICivStateBattle {
    struct Data {
        uint256 territory; uint256 energyBalance; uint256 energyPerBlock;
        bytes32 agentModelHash; bool isAutonomous; uint64 moveNonce; uint64 claimNonce;
        uint32 attackPower; uint32 defensePower; uint32 season; address owner;
    }
    function get(uint256 civId) external view returns (Data memory);
    function addTerritory(uint256 civId, uint256 amount) external;
    function removeTerritory(uint256 civId, uint256 amount) external;
}
interface ITerritoryMapBattle {
    function transfer(bytes32 commitment, uint256 fromCiv, uint256 toCiv) external;
}
interface IBattleHistory {
    function record(uint256 a, uint256 d, bool won, uint32 terr, uint32 dmg, bytes32 vrf) external returns (uint256);
}
interface IGameConfigBattle {
    struct Config { uint32 s; uint32 sl; uint32 mr; uint32 fee; uint256 epb; bool paused; }
    function get() external view returns (Config memory);
}
interface IBattleTaskManager {
    function createTask(uint8 taskType, bytes calldata payload, uint256 civId) external returns (uint256);
}

/// @title BattleSystem
/// @notice Resolves combat between civilizations via EigenLayer AVS.
///         Dispatches a compute task, then applies the AVS-computed result.
contract BattleSystem {
    ICivStateBattle      public immutable civState;
    ITerritoryMapBattle  public immutable territoryMap;
    IBattleHistory       public immutable battleHistory;
    IGameConfigBattle    public immutable gameConfig;
    address              public immutable taskManager;

    uint256 public constant BATTLE_ENERGY_COST = 100e18; // 100 $ENERGY

    event BattleInitiated(uint256 indexed attackerId, uint256 indexed defenderId, uint256 taskId);
    event BattleResolved(uint256 indexed attackerId, uint256 indexed defenderId, bool attackerWon);

    error GamePaused();
    error NotCivOwner();
    error SameCiv();
    error InsufficientEnergy();
    error NotTaskManager();

    constructor(address _civ, address _map, address _history, address _cfg, address _tm) {
        civState      = ICivStateBattle(_civ);
        territoryMap  = ITerritoryMapBattle(_map);
        battleHistory = IBattleHistory(_history);
        gameConfig    = IGameConfigBattle(_cfg);
        taskManager   = _tm;
    }

    /// @notice Initiate an attack — sends a compute task to the AVS.
    function attack(uint256 attackerId, uint256 defenderId) external returns (uint256 taskId) {
        if (gameConfig.get().paused) revert GamePaused();

        ICivStateBattle.Data memory atk = civState.get(attackerId);
        if (atk.owner != msg.sender)              revert NotCivOwner();
        if (attackerId == defenderId)             revert SameCiv();
        if (atk.energyBalance < BATTLE_ENERGY_COST) revert InsufficientEnergy();

        ICivStateBattle.Data memory def = civState.get(defenderId);

        bytes memory payload = abi.encode(
            attackerId, defenderId,
            atk.attackPower, atk.defensePower,
            def.attackPower, def.defensePower
        );

        // TaskType.BattleResolution = 2
        taskId = IBattleTaskManager(taskManager).createTask(2, payload, attackerId);
        emit BattleInitiated(attackerId, defenderId, taskId);
    }

    /// @notice Apply battle result computed by the AVS. Only callable by TaskManager.
    function resolveBattle(
        uint256 attackerId,
        uint256 defenderId,
        bool    attackerWon,
        uint32  territory,
        uint32  damage,
        bytes32 vrfSeed,
        bytes32[] calldata tilesToTransfer
    ) external {
        if (msg.sender != taskManager) revert NotTaskManager();

        if (attackerWon && tilesToTransfer.length > 0) {
            for (uint256 i = 0; i < tilesToTransfer.length; i++) {
                territoryMap.transfer(tilesToTransfer[i], defenderId, attackerId);
            }
            civState.addTerritory(attackerId, tilesToTransfer.length);
            civState.removeTerritory(defenderId, tilesToTransfer.length);
        }

        battleHistory.record(attackerId, defenderId, attackerWon, territory, damage, vrfSeed);
        emit BattleResolved(attackerId, defenderId, attackerWon);
    }
}

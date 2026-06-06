// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title BattleHistoryStore
/// @notice MUD v2 table — immutable record of all resolved battles.
///         Indexed by The Graph for leaderboard and battle-feed queries.
contract BattleHistoryStore {
    struct Battle {
        uint256 attackerId;
        uint256 defenderId;
        bool    attackerWon;
        uint32  territoryTransferred;
        uint32  damageDealt;
        uint256 blockNumber;
        bytes32 vrfSeed;
    }

    uint256 public battleCount;
    mapping(uint256 => Battle) private _battles;

    address public world;
    modifier onlyWorld() { require(msg.sender == world, "BattleHistory: not world"); _; }

    event BattleRecorded(
        uint256 indexed battleId,
        uint256 indexed attackerId,
        uint256 indexed defenderId,
        bool attackerWon
    );

    constructor(address _world) { world = _world; }

    function record(
        uint256 attackerId,
        uint256 defenderId,
        bool    attackerWon,
        uint32  territory,
        uint32  damage,
        bytes32 vrf
    ) external onlyWorld returns (uint256 battleId) {
        battleId = ++battleCount;
        _battles[battleId] = Battle(
            attackerId, defenderId, attackerWon,
            territory, damage, block.number, vrf
        );
        emit BattleRecorded(battleId, attackerId, defenderId, attackerWon);
    }

    function get(uint256 battleId) external view returns (Battle memory) {
        return _battles[battleId];
    }
}

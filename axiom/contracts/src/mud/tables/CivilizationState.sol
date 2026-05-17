// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title CivilizationState
/// @notice MUD v2 table storing per-civilization game state.
///         Each civ is identified by its ERC-721 token ID (civId).
library CivilizationState {
    // ── Storage layout ─────────────────────────────────────────
    bytes32 constant TABLE_ID = keccak256("axiom.CivilizationState");

    struct Data {
        uint256 territory;        // Number of tiles owned
        uint256 energyBalance;    // Current $ENERGY balance (18 decimals)
        uint256 energyPerBlock;   // $ENERGY minted per block
        bytes32 agentModelHash;   // EZKL model hash (0x0 = not autonomous)
        bool    isAutonomous;     // True if ERC-6551 agent is active
        uint64  moveNonce;        // Anti-replay nonce for MoveSystem
        uint64  claimNonce;       // Anti-replay nonce for ClaimSystem
        uint32  attackPower;      // Combat attack stat (0-1000)
        uint32  defensePower;     // Combat defense stat (0-1000)
        uint32  season;           // Season when this civ was created
        address owner;            // Current NFT owner address
    }

    // ── Internal storage mapping: civId → Data ─────────────────
    mapping(uint256 => Data) private _store;

    // Only the World contract can mutate state
    address private _world;

    // ── Events ─────────────────────────────────────────────────
    event CivilizationCreated(uint256 indexed civId, address indexed owner, uint32 season);
    event TerritoryChanged(uint256 indexed civId, uint256 oldTerritory, uint256 newTerritory);
    event AgentModelUpdated(uint256 indexed civId, bytes32 modelHash);
    event AutonomyToggled(uint256 indexed civId, bool isAutonomous);

    // ── Errors ─────────────────────────────────────────────────
    error CivilizationNotFound(uint256 civId);
    error CivilizationAlreadyExists(uint256 civId);
    error NotWorld();

    function _onlyWorld(address world) internal view {
        if (msg.sender != world) revert NotWorld();
    }
}

/// @title CivilizationStateStore
/// @notice Deployed storage contract for CivilizationState table.
contract CivilizationStateStore {
    mapping(uint256 => CivilizationState.Data) private _data;
    address public world;

    modifier onlyWorld() {
        require(msg.sender == world, "CivilizationStateStore: not world");
        _;
    }

    constructor(address _world) {
        world = _world;
    }

    function get(uint256 civId) external view returns (CivilizationState.Data memory) {
        return _data[civId];
    }

    function set(uint256 civId, CivilizationState.Data memory data) external onlyWorld {
        _data[civId] = data;
    }

    function exists(uint256 civId) external view returns (bool) {
        return _data[civId].owner != address(0);
    }

    function incrementMoveNonce(uint256 civId) external onlyWorld returns (uint64) {
        return ++_data[civId].moveNonce;
    }

    function incrementClaimNonce(uint256 civId) external onlyWorld returns (uint64) {
        return ++_data[civId].claimNonce;
    }

    function addTerritory(uint256 civId, uint256 amount) external onlyWorld {
        _data[civId].territory += amount;
        _data[civId].energyPerBlock = _calcEnergyRate(_data[civId].territory);
    }

    function removeTerritory(uint256 civId, uint256 amount) external onlyWorld {
        _data[civId].territory = _data[civId].territory > amount
            ? _data[civId].territory - amount : 0;
        _data[civId].energyPerBlock = _calcEnergyRate(_data[civId].territory);
    }

    function setAgentModel(uint256 civId, bytes32 modelHash) external onlyWorld {
        _data[civId].agentModelHash = modelHash;
        emit AgentModelUpdated(civId, modelHash);
    }

    function setAutonomous(uint256 civId, bool autonomous) external onlyWorld {
        _data[civId].isAutonomous = autonomous;
    }

    // 1 $ENERGY per block per tile (base rate)
    function _calcEnergyRate(uint256 territory) internal pure returns (uint256) {
        return territory * 1e18;
    }

    event AgentModelUpdated(uint256 indexed civId, bytes32 modelHash);
}

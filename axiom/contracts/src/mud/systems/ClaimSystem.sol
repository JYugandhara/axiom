// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TerritoryMapStore} from "../tables/TerritoryMap.sol";
import {CivilizationStateStore} from "../tables/CivilizationState.sol";
import {AgentActionsStore, BattleHistoryStore, GameConfigStore} from "../tables/AgentActions.sol";

interface ITerritoryVerifier {
    function verify(bytes calldata proof, bytes32[] calldata publicInputs) external view returns (bool);
}
interface IAIVerifier {
    function verify(bytes calldata proof, bytes32[] calldata publicInputs) external view returns (bool);
}
interface IEnergyToken {
    function mint(address to, uint256 amount) external;
}
interface ICivilizationNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

// ─────────────────────────────────────────────────────────────
//  ClaimSystem — territory expansion with ZK proof
// ─────────────────────────────────────────────────────────────

contract ClaimSystem {
    ITerritoryVerifier     public immutable territoryVerifier;
    TerritoryMapStore      public immutable territoryMap;
    CivilizationStateStore public immutable civState;
    GameConfigStore        public immutable gameConfig;

    event TileClaimed(uint256 indexed civId, bytes32 claimCommitment, bytes32 anchorCommitment);
    error GamePaused();
    error InvalidProof();
    error InvalidNonce();
    error NotCivOwner();
    error AnchorNotOwned();

    constructor(address _verifier, address _map, address _civ, address _cfg) {
        territoryVerifier = ITerritoryVerifier(_verifier);
        territoryMap      = TerritoryMapStore(_map);
        civState          = CivilizationStateStore(_civ);
        gameConfig        = GameConfigStore(_cfg);
    }

    /// @notice Claim a tile adjacent to an already-owned tile, with ZK proof.
    function claim(
        uint256 civId,
        bytes32 claimCommitment,
        bytes32 anchorCommitment,
        bytes32 civIdHash,
        uint64  nonce,
        bytes calldata proof
    ) external {
        GameConfigStore.Config memory cfg = gameConfig.get();
        if (cfg.paused) revert GamePaused();

        CivilizationStateStore.Data memory civ = civState.get(civId);
        if (civ.owner != msg.sender)                      revert NotCivOwner();
        if (civ.claimNonce != nonce)                      revert InvalidNonce();
        if (!territoryMap.isOwnedBy(anchorCommitment, civId)) revert AnchorNotOwned();

        // Public inputs: [claimCommitment, anchorCommitment, civIdHash, civId, season, nonce]
        bytes32[] memory pub = new bytes32[](6);
        pub[0] = claimCommitment;
        pub[1] = anchorCommitment;
        pub[2] = civIdHash;
        pub[3] = bytes32(civId);
        pub[4] = bytes32(uint256(cfg.currentSeason));
        pub[5] = bytes32(uint256(nonce));

        if (!territoryVerifier.verify(proof, pub)) revert InvalidProof();

        territoryMap.claim(claimCommitment, civId);
        civState.addTerritory(civId, 1);
        civState.incrementClaimNonce(civId);

        emit TileClaimed(civId, claimCommitment, anchorCommitment);
    }
}

// ─────────────────────────────────────────────────────────────
//  BattleSystem — combat resolution via EigenLayer AVS
// ─────────────────────────────────────────────────────────────

contract BattleSystem {
    CivilizationStateStore public immutable civState;
    TerritoryMapStore      public immutable territoryMap;
    BattleHistoryStore     public immutable battleHistory;
    GameConfigStore        public immutable gameConfig;
    address                public immutable taskManager; // AxiomTaskManager

    event BattleInitiated(uint256 indexed attackerId, uint256 indexed defenderId, uint256 taskId);
    error GamePaused();
    error NotCivOwner();
    error SameCiv();
    error InsufficientEnergy();

    uint256 public constant BATTLE_ENERGY_COST = 100e18; // 100 $ENERGY

    constructor(address _civ, address _map, address _history, address _cfg, address _tm) {
        civState      = CivilizationStateStore(_civ);
        territoryMap  = TerritoryMapStore(_map);
        battleHistory = BattleHistoryStore(_history);
        gameConfig    = GameConfigStore(_cfg);
        taskManager   = _tm;
    }

    /// @notice Initiate a battle — sends compute task to EigenLayer AVS.
    function attack(uint256 attackerId, uint256 defenderId) external returns (uint256 taskId) {
        if (gameConfig.get().paused) revert GamePaused();
        CivilizationStateStore.Data memory atk = civState.get(attackerId);
        if (atk.owner != msg.sender) revert NotCivOwner();
        if (attackerId == defenderId) revert SameCiv();
        if (atk.energyBalance < BATTLE_ENERGY_COST) revert InsufficientEnergy();

        // Encode task payload for AVS operator
        bytes memory payload = abi.encode(
            attackerId, defenderId,
            atk.attackPower, atk.defensePower,
            civState.get(defenderId).attackPower,
            civState.get(defenderId).defensePower
        );

        // Submit to AxiomTaskManager (emits NewTask event picked up by avs-operator)
        taskId = ITaskManager(taskManager).createTask(1 /* TaskType.BattleResolution */, payload, attackerId);

        emit BattleInitiated(attackerId, defenderId, taskId);
    }

    /// @notice Called by AxiomTaskManager when AVS resolves the battle.
    function resolveBattle(
        uint256 attackerId, uint256 defenderId,
        bool attackerWon, uint32 territory, uint32 damage,
        bytes32 vrfSeed, bytes32[] calldata tilesToTransfer
    ) external {
        require(msg.sender == taskManager, "BattleSystem: not taskManager");

        if (attackerWon && tilesToTransfer.length > 0) {
            for (uint256 i = 0; i < tilesToTransfer.length; i++) {
                territoryMap.transfer(tilesToTransfer[i], defenderId, attackerId);
            }
            civState.addTerritory(attackerId, tilesToTransfer.length);
            civState.removeTerritory(defenderId, tilesToTransfer.length);
        }

        battleHistory.record(attackerId, defenderId, attackerWon, territory, damage, vrfSeed);
    }
}

interface ITaskManager {
    function createTask(uint8 taskType, bytes calldata payload, uint256 civId) external returns (uint256);
}

// ─────────────────────────────────────────────────────────────
//  AgentSystem — executes autonomous AI agent actions
// ─────────────────────────────────────────────────────────────

contract AgentSystem {
    IAIVerifier            public immutable aiVerifier;
    AgentActionsStore      public immutable agentActions;
    CivilizationStateStore public immutable civState;
    address                public immutable taskManager;

    event AgentActionExecuted(uint256 indexed taskId, uint256 indexed civId, uint8 action);
    error NotTaskManager();
    error AlreadyExecuted();
    error InvalidAIProof();
    error NotAutonomous(uint256 civId);

    constructor(address _verifier, address _actions, address _civ, address _tm) {
        aiVerifier   = IAIVerifier(_verifier);
        agentActions = AgentActionsStore(_actions);
        civState     = CivilizationStateStore(_civ);
        taskManager  = _tm;
    }

    /// @notice Called by AxiomTaskManager when AVS submits an agent action with ZK proof.
    function executeAgentAction(
        uint256 taskId,
        uint256 civId,
        uint8   action,
        bytes calldata proof,
        bytes32[] calldata publicInputs
    ) external {
        if (msg.sender != taskManager) revert NotTaskManager();

        AgentActionsStore.AgentAction memory a = agentActions.get(taskId);
        if (a.executed) revert AlreadyExecuted();

        CivilizationStateStore.Data memory civ = civState.get(civId);
        if (!civ.isAutonomous) revert NotAutonomous(civId);

        // Verify EZKL ZK proof of ML inference
        if (!aiVerifier.verify(proof, publicInputs)) revert InvalidAIProof();

        agentActions.markExecuted(taskId);
        emit AgentActionExecuted(taskId, civId, action);
        // Actual action effects are applied by downstream systems based on action type
    }
}

// ─────────────────────────────────────────────────────────────
//  EnergySystem — mints $ENERGY per block per tile
//  Called by Chainlink Automation on each block
// ─────────────────────────────────────────────────────────────

contract EnergySystem {
    IEnergyToken           public immutable energyToken;
    CivilizationStateStore public immutable civState;
    ICivilizationNFT       public immutable civNFT;

    uint256 public lastProcessedBlock;
    uint256[] public activeCivIds; // maintained off-chain, passed in

    event EnergyDistributed(uint256 blocks, uint256 totalMinted);
    error NotAutomation();

    address public automation; // Chainlink Automation forwarder

    constructor(address _energy, address _civ, address _nft, address _automation) {
        energyToken        = IEnergyToken(_energy);
        civState           = CivilizationStateStore(_civ);
        civNFT             = ICivilizationNFT(_nft);
        automation         = _automation;
        lastProcessedBlock = block.number;
    }

    /// @notice Distribute $ENERGY to all civilizations.
    ///         Called by Chainlink Automation every N blocks.
    function distributeEnergy(uint256[] calldata civIds) external {
        if (msg.sender != automation) revert NotAutomation();

        uint256 blocksDelta = block.number - lastProcessedBlock;
        if (blocksDelta == 0) return;

        uint256 totalMinted;
        for (uint256 i = 0; i < civIds.length; i++) {
            uint256 id = civIds[i];
            CivilizationStateStore.Data memory civ = civState.get(id);
            if (civ.territory == 0) continue;

            uint256 toMint = civ.energyPerBlock * blocksDelta;
            energyToken.mint(civ.owner, toMint);
            totalMinted += toMint;
        }

        lastProcessedBlock = block.number;
        emit EnergyDistributed(blocksDelta, totalMinted);
    }
}

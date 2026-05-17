// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TerritoryMapStore} from "../tables/TerritoryMap.sol";
import {CivilizationStateStore} from "../tables/CivilizationState.sol";
import {GameConfigStore} from "../tables/AgentActions.sol";

interface IFogVerifier {
    function verify(bytes calldata proof, bytes32[] calldata publicInputs) external view returns (bool);
}

/// @title MoveSystem
/// @notice Verifies a fog-of-war ZK proof and updates the territory map.
///         Players submit a Noir proof that they moved from A→B
///         without revealing the actual coordinates.
contract MoveSystem {
    // ── Immutable references ────────────────────────────────────
    IFogVerifier            public immutable fogVerifier;
    TerritoryMapStore       public immutable territoryMap;
    CivilizationStateStore  public immutable civState;
    GameConfigStore         public immutable gameConfig;

    // ── Events ─────────────────────────────────────────────────
    event Moved(
        uint256 indexed civId,
        bytes32 fromCommitment,
        bytes32 toCommitment,
        uint64  nonce
    );

    // ── Errors ─────────────────────────────────────────────────
    error GamePaused();
    error InvalidProof();
    error InvalidNonce(uint64 expected, uint64 got);
    error WrongSeason(uint32 expected, uint32 got);
    error NotCivOwner(uint256 civId, address caller);
    error MoveRangeExceeded();
    error TileNotOwned(bytes32 commitment);

    constructor(
        address _fogVerifier,
        address _territoryMap,
        address _civState,
        address _gameConfig
    ) {
        fogVerifier   = IFogVerifier(_fogVerifier);
        territoryMap  = TerritoryMapStore(_territoryMap);
        civState      = CivilizationStateStore(_civState);
        gameConfig    = GameConfigStore(_gameConfig);
    }

    /// @notice Execute a fog-of-war move with a ZK proof.
    /// @param civId            Civilization NFT token ID
    /// @param fromCommitment   Poseidon2(from_x, from_y, player_secret) — current position
    /// @param toCommitment     Poseidon2(to_x, to_y, player_secret)   — destination
    /// @param movementRange    Max distance this move covers
    /// @param nonce            Anti-replay nonce (must match civState.moveNonce)
    /// @param proof            Noir ZK proof bytes
    function move(
        uint256 civId,
        bytes32 fromCommitment,
        bytes32 toCommitment,
        uint32  movementRange,
        uint64  nonce,
        bytes calldata proof
    ) external {
        // ── Pre-flight checks ─────────────────────────────────
        GameConfigStore.Config memory cfg = gameConfig.get();
        if (cfg.paused) revert GamePaused();

        CivilizationStateStore.Data memory civ = civState.get(civId);
        if (civ.owner != msg.sender) revert NotCivOwner(civId, msg.sender);
        if (civ.moveNonce != nonce)  revert InvalidNonce(civ.moveNonce, nonce);
        if (civ.season != cfg.currentSeason) revert WrongSeason(cfg.currentSeason, civ.season);
        if (!territoryMap.isOwnedBy(fromCommitment, civId)) revert TileNotOwned(fromCommitment);
        if (movementRange > cfg.baseMovementRange) revert MoveRangeExceeded();

        // ── Verify ZK proof ───────────────────────────────────
        // Public inputs: [fromCommitment, toCommitment, movementRange, nonce, season]
        bytes32[] memory publicInputs = new bytes32[](5);
        publicInputs[0] = fromCommitment;
        publicInputs[1] = toCommitment;
        publicInputs[2] = bytes32(uint256(movementRange));
        publicInputs[3] = bytes32(uint256(nonce));
        publicInputs[4] = bytes32(uint256(cfg.currentSeason));

        if (!fogVerifier.verify(proof, publicInputs)) revert InvalidProof();

        // ── Apply state changes ───────────────────────────────
        // Release old position
        territoryMap.transfer(fromCommitment, civId, 0); // transfer to "unclaimed" (0)
        // Claim new position (will revert if already owned by someone else)
        territoryMap.claim(toCommitment, civId);

        // Increment nonce
        civState.incrementMoveNonce(civId);

        emit Moved(civId, fromCommitment, toCommitment, nonce);
    }
}

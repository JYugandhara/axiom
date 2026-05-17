// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title TerritoryMap
/// @notice MUD v2 table mapping Poseidon2 tile commitments to civilization owners.
///         This is the fog-of-war territory ledger.
///         commitmentHash = Poseidon2(x, y, civ_secret) — coordinates stay private.
contract TerritoryMapStore {
    // commitment → civId (0 = unclaimed)
    mapping(bytes32 => uint256) private _owner;
    // civId → array of owned commitments (for territory count verification)
    mapping(uint256 => bytes32[]) private _civTiles;
    // commitment → index in civTiles (for O(1) removal)
    mapping(bytes32 => uint256) private _tileIndex;

    address public world;

    modifier onlyWorld() {
        require(msg.sender == world, "TerritoryMap: not world");
        _;
    }

    // ── Events ─────────────────────────────────────────────────
    event TileClaimed(bytes32 indexed commitment, uint256 indexed civId);
    event TileLost(bytes32 indexed commitment, uint256 indexed fromCiv, uint256 indexed toCiv);

    // ── Errors ─────────────────────────────────────────────────
    error TileAlreadyClaimed(bytes32 commitment, uint256 currentOwner);
    error TileNotOwned(bytes32 commitment, uint256 expectedOwner);

    constructor(address _world) { world = _world; }

    /// @notice Claim a tile for a civilization.
    function claim(bytes32 commitment, uint256 civId) external onlyWorld {
        uint256 current = _owner[commitment];
        if (current != 0) revert TileAlreadyClaimed(commitment, current);

        _owner[commitment] = civId;
        _tileIndex[commitment] = _civTiles[civId].length;
        _civTiles[civId].push(commitment);

        emit TileClaimed(commitment, civId);
    }

    /// @notice Transfer a tile from one civ to another (battle conquest).
    function transfer(bytes32 commitment, uint256 fromCiv, uint256 toCiv) external onlyWorld {
        if (_owner[commitment] != fromCiv) revert TileNotOwned(commitment, fromCiv);

        // Remove from loser's array (swap with last)
        uint256 idx = _tileIndex[commitment];
        bytes32[] storage tiles = _civTiles[fromCiv];
        uint256 lastIdx = tiles.length - 1;

        if (idx != lastIdx) {
            bytes32 last = tiles[lastIdx];
            tiles[idx] = last;
            _tileIndex[last] = idx;
        }
        tiles.pop();

        // Add to winner's array
        _tileIndex[commitment] = _civTiles[toCiv].length;
        _civTiles[toCiv].push(commitment);
        _owner[commitment] = toCiv;

        emit TileLost(commitment, fromCiv, toCiv);
    }

    /// @notice Check if a commitment is owned by a specific civ.
    function isOwnedBy(bytes32 commitment, uint256 civId) external view returns (bool) {
        return _owner[commitment] == civId;
    }

    /// @notice Get the owner of a commitment (0 = unclaimed).
    function ownerOf(bytes32 commitment) external view returns (uint256) {
        return _owner[commitment];
    }

    /// @notice Get all tile commitments owned by a civilization.
    function tilesOf(uint256 civId) external view returns (bytes32[] memory) {
        return _civTiles[civId];
    }

    /// @notice Count tiles owned by a civilization.
    function tileCount(uint256 civId) external view returns (uint256) {
        return _civTiles[civId].length;
    }
}

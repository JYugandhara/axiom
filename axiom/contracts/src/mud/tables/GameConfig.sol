// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title GameConfigStore
/// @notice MUD v2 table — global mutable game parameters (DAO-controlled).
contract GameConfigStore {
    struct Config {
        uint32  currentSeason;
        uint32  seasonLengthBlocks;    // Blocks per season
        uint32  baseMovementRange;     // Base tiles per move
        uint32  entryFeeAxm;           // $AXM to mint a civilization
        uint256 energyPerBlockPerTile; // $ENERGY per block per tile (18 dec)
        bool    paused;                // Emergency pause
    }

    Config private _config;
    address public world;
    address public dao;

    modifier onlyDAO()   { require(msg.sender == dao,   "GameConfig: not DAO");   _; }
    modifier onlyWorld() { require(msg.sender == world, "GameConfig: not world"); _; }

    event ConfigUpdated(Config config);
    event SeasonAdvanced(uint32 oldSeason, uint32 newSeason);
    event PauseToggled(bool paused);

    constructor(address _world, address _dao) {
        world = _world;
        dao   = _dao;
        _config = Config({
            currentSeason        : 1,
            seasonLengthBlocks   : 302400,  // ~1 week at 2s blocks
            baseMovementRange    : 5,
            entryFeeAxm          : 100,
            energyPerBlockPerTile: 1e18,
            paused               : false
        });
    }

    function get() external view returns (Config memory) {
        return _config;
    }

    function advanceSeason() external onlyWorld {
        uint32 old = _config.currentSeason;
        _config.currentSeason++;
        emit SeasonAdvanced(old, _config.currentSeason);
    }

    function update(Config calldata cfg) external onlyDAO {
        _config = cfg;
        emit ConfigUpdated(cfg);
    }

    function pause(bool _paused) external onlyDAO {
        _config.paused = _paused;
        emit PauseToggled(_paused);
    }
}

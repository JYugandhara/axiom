// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MoveSystem}             from "../../src/mud/systems/MoveSystem.sol";
import {AxiomWorld}             from "../../src/mud/AxiomWorld.sol";
import {TerritoryMapStore}      from "../../src/mud/tables/TerritoryMap.sol";
import {CivilizationStateStore, CivilizationState} from "../../src/mud/tables/CivilizationState.sol";
import {GameConfigStore}        from "../../src/mud/tables/GameConfig.sol";

/// @notice Configurable fog verifier mock — lets fuzz tests toggle validity.
contract FuzzFogVerifier {
    bool public pass = true;
    function verify(bytes calldata, bytes32[] calldata) external view returns (bool) { return pass; }
    function setPass(bool v) external { pass = v; }
}

/// @title MovementFuzzTest
/// @notice Property-based fuzz tests for fog-of-war movement.
///         Verifies the MoveSystem's invariants hold across the entire
///         input space: range bounds, proof gating, nonce replay protection,
///         and coordinate-encoding round-trips.
contract MovementFuzzTest is Test {
    AxiomWorld             world;
    MoveSystem             moveSystem;
    TerritoryMapStore      territory;
    CivilizationStateStore civs;
    GameConfigStore        cfg;
    FuzzFogVerifier        verifier;

    address dao = address(0xDA0);

    // Coordinate offset used in circuits (Prover.toml): coord + 1_000_000
    uint256 constant COORD_OFFSET = 1_000_000;

    function setUp() public {
        verifier = new FuzzFogVerifier();

        // Deploy the world — it owns all the table stores, which is the
        // correct fixture (stores enforce onlyWorld).
        world = new AxiomWorld(
            dao,
            address(verifier),       // fogVerifier
            address(verifier),       // territoryVerifier (reuse mock)
            address(verifier),       // aiVerifier (reuse mock)
            address(0xE1),           // energy (unused here)
            address(0xC1),           // civNFT (unused here)
            address(0x7A),           // taskManager (unused here)
            address(0xA0)            // automation (unused here)
        );

        moveSystem = world.moveSystem();
        territory  = world.territoryMap();
        civs       = world.civState();
        cfg        = world.gameConfig();
    }

    // ── Helpers ────────────────────────────────────────────────

    /// @dev Seed a civilization owned by `owner` with a starting tile.
    function _seedCiv(uint256 civId, address owner, bytes32 startTile) internal {
        // The world owns the stores, so we must impersonate it.
        CivilizationState.Data memory d;
        d.owner = owner; d.territory = 1; d.moveNonce = 0; d.season = 1;
        d.attackPower = 50; d.defensePower = 50;

        vm.prank(address(world));
        civs.set(civId, d);

        vm.prank(address(world));
        territory.claim(startTile, civId);
    }

    /// @dev Build a fog-of-war public-input array the way MoveSystem expects.
    function _encodeCoord(int256 worldCoord) internal pure returns (uint256) {
        return uint256(int256(COORD_OFFSET) + worldCoord);
    }

    // ── Fuzz: range gating ─────────────────────────────────────

    /// @notice Fuzz: any movementRange above baseMovementRange must revert,
    ///         regardless of proof validity.
    function testFuzz_rangeAboveMaxAlwaysReverts(uint32 range) public {
        GameConfigStore.Config memory c = cfg.get();
        range = uint32(bound(range, c.baseMovementRange + 1, type(uint32).max));

        address alice = address(0xA11CE);
        bytes32 from  = keccak256("from");
        bytes32 to    = keccak256("to");
        _seedCiv(1, alice, from);

        vm.prank(alice);
        vm.expectRevert(MoveSystem.MoveRangeExceeded.selector);
        moveSystem.move(1, from, to, range, 0, bytes("proof"));
    }

    /// @notice Fuzz: a valid proof + in-range move always succeeds and
    ///         transfers ownership of the destination tile.
    function testFuzz_validMoveInRangeSucceeds(uint32 range, bytes32 to) public {
        GameConfigStore.Config memory c = cfg.get();
        range = uint32(bound(range, 1, c.baseMovementRange));
        vm.assume(to != bytes32(0));

        address alice = address(0xA11CE);
        bytes32 from  = keccak256("origin");
        vm.assume(to != from);
        _seedCiv(1, alice, from);

        verifier.setPass(true);
        vm.prank(alice);
        moveSystem.move(1, from, to, range, 0, bytes("proof"));

        assertEq(territory.ownerOf(to), 1, "destination not owned after move");
        assertEq(territory.ownerOf(from), 0, "origin not released after move");
    }

    // ── Fuzz: proof gating ─────────────────────────────────────

    /// @notice Fuzz: an invalid proof always reverts, for any in-range move.
    function testFuzz_invalidProofAlwaysReverts(uint32 range, bytes calldata proof) public {
        GameConfigStore.Config memory c = cfg.get();
        range = uint32(bound(range, 1, c.baseMovementRange));

        address alice = address(0xA11CE);
        bytes32 from  = keccak256("from");
        bytes32 to    = keccak256("to");
        _seedCiv(1, alice, from);

        verifier.setPass(false);
        vm.prank(alice);
        vm.expectRevert(MoveSystem.InvalidProof.selector);
        moveSystem.move(1, from, to, range, 0, proof);
    }

    // ── Fuzz: nonce replay protection ──────────────────────────

    /// @notice Fuzz: any nonce that doesn't match the civ's current nonce reverts.
    function testFuzz_wrongNonceAlwaysReverts(uint64 nonce) public {
        vm.assume(nonce != 0); // 0 is the valid starting nonce

        address alice = address(0xA11CE);
        bytes32 from  = keccak256("from");
        bytes32 to    = keccak256("to");
        _seedCiv(1, alice, from);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MoveSystem.InvalidNonce.selector, uint64(0), nonce));
        moveSystem.move(1, from, to, 5, nonce, bytes("proof"));
    }

    /// @notice Fuzz: nonce strictly increments by 1 after each successful move,
    ///         so a replayed proof with the old nonce always fails.
    function testFuzz_nonceIncrementsPreventReplay(bytes32 t1, bytes32 t2) public {
        vm.assume(t1 != bytes32(0) && t2 != bytes32(0));
        bytes32 from = keccak256("origin");
        vm.assume(t1 != from && t2 != from && t1 != t2);

        address alice = address(0xA11CE);
        _seedCiv(1, alice, from);

        // First move with nonce 0 — succeeds.
        vm.prank(alice);
        moveSystem.move(1, from, t1, 5, 0, bytes("proof"));

        CivilizationState.Data memory d = civs.get(1);
        assertEq(d.moveNonce, 1, "nonce did not increment");

        // Replaying with the stale nonce 0 must revert.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MoveSystem.InvalidNonce.selector, uint64(1), uint64(0)));
        moveSystem.move(1, t1, t2, 5, 0, bytes("proof"));
    }

    // ── Fuzz: ownership gating ─────────────────────────────────

    /// @notice Fuzz: only the civ owner can move; any other caller reverts.
    function testFuzz_nonOwnerAlwaysReverts(address caller) public {
        address alice = address(0xA11CE);
        vm.assume(caller != alice && caller != address(0));

        bytes32 from = keccak256("from");
        bytes32 to   = keccak256("to");
        _seedCiv(1, alice, from);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(MoveSystem.NotCivOwner.selector, uint256(1), caller));
        moveSystem.move(1, from, to, 5, 0, bytes("proof"));
    }

    /// @notice Fuzz: moving from a tile the civ does not own always reverts.
    function testFuzz_moveFromUnownedTileReverts(bytes32 wrongFrom) public {
        bytes32 realFrom = keccak256("real_origin");
        vm.assume(wrongFrom != realFrom && wrongFrom != bytes32(0));

        address alice = address(0xA11CE);
        _seedCiv(1, alice, realFrom);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MoveSystem.TileNotOwned.selector, wrongFrom));
        moveSystem.move(1, wrongFrom, keccak256("dest"), 5, 0, bytes("proof"));
    }

    // ── Fuzz: coordinate encoding round-trip ───────────────────

    /// @notice Fuzz: the COORD_OFFSET encoding round-trips for the whole
    ///         signed range used by the circuits (keeps field elements positive).
    function testFuzz_coordEncodingRoundTrip(int256 worldCoord) public pure {
        // Bound to the playable world: +/- 1,000,000 tiles.
        worldCoord = bound(worldCoord, -int256(COORD_OFFSET), int256(COORD_OFFSET));
        uint256 encoded = uint256(int256(COORD_OFFSET) + worldCoord);
        int256  decoded = int256(encoded) - int256(COORD_OFFSET);
        assertEq(decoded, worldCoord, "coordinate encoding did not round-trip");
    }

    /// @notice Fuzz: Manhattan distance is symmetric and non-negative.
    function testFuzz_manhattanDistanceSymmetric(
        int256 x1, int256 y1, int256 x2, int256 y2
    ) public pure {
        x1 = bound(x1, -1000, 1000); y1 = bound(y1, -1000, 1000);
        x2 = bound(x2, -1000, 1000); y2 = bound(y2, -1000, 1000);

        uint256 dAB = _manhattan(x1, y1, x2, y2);
        uint256 dBA = _manhattan(x2, y2, x1, y1);
        assertEq(dAB, dBA, "Manhattan distance not symmetric");
    }

    function _manhattan(int256 x1, int256 y1, int256 x2, int256 y2)
        internal pure returns (uint256)
    {
        uint256 dx = x1 > x2 ? uint256(x1 - x2) : uint256(x2 - x1);
        uint256 dy = y1 > y2 ? uint256(y1 - y2) : uint256(y2 - y1);
        return dx + dy;
    }
}

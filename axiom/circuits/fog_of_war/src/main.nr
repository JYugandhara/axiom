// ─────────────────────────────────────────────────────────────
//  AXIOM — Fog of War Circuit
//  File: circuits/fog_of_war/src/main.nr
// ─────────────────────────────────────────────────────────────
//
//  WHAT THIS PROVES
//  ────────────────
//  A civilization moved from tile (from_x, from_y) to tile
//  (to_x, to_y) in the AXIOM world without revealing the actual
//  coordinates to any other player or on-chain observer.
//
//  The prover knows the real coordinates privately.
//  The verifier only sees Poseidon2 commitments + move range.
//
//  SECURITY MODEL
//  ──────────────
//  Position commitment: C(x, y) = Poseidon2(x, y, player_secret)
//    - player_secret is a 32-byte random salt per player
//    - Two players at the same tile have different commitments
//    - Binding: prover cannot open C to a different (x,y)
//    - Hiding: commitment reveals nothing about (x, y)
//
//  CONSTRAINTS VERIFIED
//  ─────────────────────
//  1. from_commitment = Poseidon2(from_x, from_y, player_secret)
//  2. to_commitment   = Poseidon2(to_x,   to_y,   player_secret)
//  3. Manhattan distance |dx| + |dy| ≤ movement_range
//  4. Coordinates are consistent: to = from + signed_delta
//  5. Movement range ≤ MAX_MOVEMENT_RANGE (prevent overflow)
//  6. Cannot move to the same tile (dx + dy > 0)
//
//  USAGE (from circuits/fog_of_war/)
//  ──────────────────────────────────
//  1. Fill Prover.toml with your values (run compute_witness.sh)
//  2. nargo prove    →  generates proofs/fog_of_war.proof
//  3. nargo verify   →  verifies locally
//  4. nargo codegen-verifier  →  outputs contract/plonk_vk.sol
//     (copy to contracts/src/zk/FogVerifier.sol)
// ─────────────────────────────────────────────────────────────

use dep::std::hash::poseidon2::Poseidon2;

// ─────────────────────────────────────────────────────────────
//  Constants
// ─────────────────────────────────────────────────────────────

/// Maximum allowed movement range per action.
/// Matches CivilizationState.sol BASE_MOVEMENT_RANGE.
global MAX_MOVEMENT_RANGE: u32 = 100;

/// Maximum absolute coordinate value.
/// World is [-WORLD_BOUND, WORLD_BOUND] in each axis.
/// Encoded as offset: actual_coord = field_coord - COORD_OFFSET
global COORD_OFFSET: Field = 1000000; // 1 million tile offset

// ─────────────────────────────────────────────────────────────
//  Main Circuit
// ─────────────────────────────────────────────────────────────

fn main(
    // ── Private inputs (known only to the prover / player) ────

    /// Source tile X coordinate (as Field, offset by COORD_OFFSET)
    from_x          : Field,

    /// Source tile Y coordinate (as Field, offset by COORD_OFFSET)
    from_y          : Field,

    /// Destination tile X coordinate
    to_x            : Field,

    /// Destination tile Y coordinate
    to_y            : Field,

    /// Player's private salt — binds commitment to this player
    /// Generated once per player: keccak256(privateKey + "AXIOM_SALT")
    player_secret   : Field,

    /// |to_x - from_x| as unsigned integer (magnitude only)
    dx_magnitude    : u32,

    /// |to_y - from_y| as unsigned integer (magnitude only)
    dy_magnitude    : u32,

    /// True if to_x > from_x (movement direction)
    dx_positive     : bool,

    /// True if to_y > from_y (movement direction)
    dy_positive     : bool,

    // ── Public inputs (visible on-chain to verifier) ──────────

    /// Poseidon2(from_x, from_y, player_secret)
    /// Stored in MUD TerritoryMap table as current position
    from_commitment : pub Field,

    /// Poseidon2(to_x, to_y, player_secret)
    /// Becomes the new position commitment after move
    to_commitment   : pub Field,

    /// Maximum Manhattan distance this civilization can move
    /// Read from CivilizationState.sol for this civ_id
    movement_range  : pub u32,

    /// Anti-replay nonce — must match on-chain nonce for this civ
    nonce           : pub Field,

    /// Current game season number
    season          : pub u32,
) {
    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 1: Verify from_commitment
    //  Proves the prover knows the actual source coordinates
    // ═══════════════════════════════════════════════════════════

    let computed_from = Poseidon2::hash([from_x, from_y, player_secret], 3);

    assert(
        computed_from == from_commitment,
        "from_commitment does not match Poseidon2(from_x, from_y, player_secret)"
    );

    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 2: Verify to_commitment
    //  Proves the prover knows the actual destination coordinates
    // ═══════════════════════════════════════════════════════════

    let computed_to = Poseidon2::hash([to_x, to_y, player_secret], 3);

    assert(
        computed_to == to_commitment,
        "to_commitment does not match Poseidon2(to_x, to_y, player_secret)"
    );

    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 3: Validate movement_range cap
    //  Prevents abusing a maliciously large movement_range
    // ═══════════════════════════════════════════════════════════

    assert(
        movement_range <= MAX_MOVEMENT_RANGE,
        "movement_range exceeds MAX_MOVEMENT_RANGE"
    );

    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 4: Manhattan distance check
    //  |dx| + |dy| ≤ movement_range
    //  Uses u32 arithmetic — safe because magnitudes are bounded
    // ═══════════════════════════════════════════════════════════

    // Overflow protection: each magnitude fits in u32 already
    // (ensured by Noir's range check on u32 inputs)
    let total_distance: u32 = dx_magnitude + dy_magnitude;

    assert(
        total_distance <= movement_range,
        "Move distance exceeds movement_range"
    );

    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 5: Must move to a different tile
    //  Prevents zero-moves (replay a move without changing state)
    // ═══════════════════════════════════════════════════════════

    assert(
        total_distance > 0,
        "Cannot move to the same tile"
    );

    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 6: Coordinate consistency
    //  Verifies that (to_x, to_y) = (from_x, from_y) + signed delta
    //  This ties the commitment to the actual movement direction.
    // ═══════════════════════════════════════════════════════════

    let dx_field: Field = dx_magnitude as Field;
    let dy_field: Field = dy_magnitude as Field;

    // Compute expected to_x based on sign of dx
    let expected_to_x: Field = if dx_positive {
        from_x + dx_field
    } else {
        from_x - dx_field
    };

    // Compute expected to_y based on sign of dy
    let expected_to_y: Field = if dy_positive {
        from_y + dy_field
    } else {
        from_y - dy_field
    };

    assert(
        expected_to_x == to_x,
        "to_x coordinate is inconsistent with from_x and dx"
    );

    assert(
        expected_to_y == to_y,
        "to_y coordinate is inconsistent with from_y and dy"
    );

    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 7: Bind nonce to commitment (anti-replay)
    //  The nonce hash is computed but not stored — the verifier
    //  checks the public nonce against the chain's stored nonce.
    //  Including it in the witness prevents proof reuse across rounds.
    // ═══════════════════════════════════════════════════════════

    // nonce is a public input — its inclusion in the circuit
    // means a proof generated for nonce=N cannot be submitted
    // when the on-chain nonce is N+1.
    // No additional constraint needed — presence as pub input is sufficient.

    // Season check — prevents using proofs from previous seasons
    // (season is checked on-chain in MoveSystem.sol)
    let _ = season; // acknowledged as public input
}

// ─────────────────────────────────────────────────────────────
//  Helper: compute_commitment
//  Unconstrained — use off-circuit to compute Prover.toml values
// ─────────────────────────────────────────────────────────────

/// Compute a position commitment. Call this to generate Prover.toml values.
/// NOT a circuit constraint — run with `nargo execute` or in a #[test].
unconstrained fn compute_commitment(x: Field, y: Field, secret: Field) -> Field {
    Poseidon2::hash([x, y, secret], 3)
}

/// Compute nonce hash for anti-replay binding.
unconstrained fn compute_nonce_hash(nonce: Field, civ_id: Field) -> Field {
    Poseidon2::hash([nonce, civ_id], 2)
}

// ─────────────────────────────────────────────────────────────
//  Tests
//  Run with: nargo test (from circuits/fog_of_war/)
// ─────────────────────────────────────────────────────────────

#[test]
fn test_valid_move_east() {
    // Player at (100, 200) moves east to (101, 200)
    let from_x: Field = 1000100; // 100 + COORD_OFFSET
    let from_y: Field = 1000200; // 200 + COORD_OFFSET
    let to_x: Field   = 1000101; // 101 + COORD_OFFSET
    let to_y: Field   = 1000200; // same Y
    let secret: Field = 99999;

    let from_c = Poseidon2::hash([from_x, from_y, secret], 3);
    let to_c   = Poseidon2::hash([to_x, to_y, secret], 3);

    main(
        from_x, from_y, to_x, to_y,
        secret,
        1, 0,       // dx=1 east, dy=0
        true, true, // dx positive, dy direction irrelevant
        from_c, to_c,
        5,          // movement_range = 5
        1,          // nonce
        1,          // season
    );
}

#[test]
fn test_valid_diagonal_move() {
    // Player moves 3 east, 2 north — total Manhattan dist = 5
    let from_x: Field = 1000050;
    let from_y: Field = 1000050;
    let to_x: Field   = 1000053; // +3
    let to_y: Field   = 1000052; // +2
    let secret: Field = 77777;

    let from_c = Poseidon2::hash([from_x, from_y, secret], 3);
    let to_c   = Poseidon2::hash([to_x,   to_y,   secret], 3);

    main(
        from_x, from_y, to_x, to_y,
        secret,
        3, 2,         // dx=3, dy=2
        true, true,   // both positive direction
        from_c, to_c,
        10,           // movement_range = 10
        42,           // nonce
        2,            // season
    );
}

#[test]
fn test_valid_move_negative_direction() {
    // Player moves 2 west, 1 south (negative dx and dy)
    let from_x: Field = 1000010;
    let from_y: Field = 1000010;
    let to_x: Field   = 1000008; // -2 (west)
    let to_y: Field   = 1000009; // -1 (south)
    let secret: Field = 12345;

    let from_c = Poseidon2::hash([from_x, from_y, secret], 3);
    let to_c   = Poseidon2::hash([to_x,   to_y,   secret], 3);

    main(
        from_x, from_y, to_x, to_y,
        secret,
        2, 1,           // magnitudes
        false, false,   // both negative
        from_c, to_c,
        5,
        99,
        3,
    );
}

#[test(should_fail_with = "Move distance exceeds movement_range")]
fn test_move_too_far_fails() {
    // Attempt to move 6 tiles when range is 5 — should fail
    let from_x: Field = 1000000;
    let from_y: Field = 1000000;
    let to_x: Field   = 1000006;
    let to_y: Field   = 1000000;
    let secret: Field = 11111;

    let from_c = Poseidon2::hash([from_x, from_y, secret], 3);
    let to_c   = Poseidon2::hash([to_x,   to_y,   secret], 3);

    main(
        from_x, from_y, to_x, to_y,
        secret,
        6, 0,
        true, true,
        from_c, to_c,
        5,   // movement_range = 5, but distance = 6
        1, 1,
    );
}

#[test(should_fail_with = "Cannot move to the same tile")]
fn test_zero_move_fails() {
    // Moving to same tile — should fail
    let from_x: Field = 1000000;
    let from_y: Field = 1000000;
    let secret: Field = 55555;

    let commitment = Poseidon2::hash([from_x, from_y, secret], 3);

    main(
        from_x, from_y, from_x, from_y,
        secret,
        0, 0,
        true, true,
        commitment, commitment, // same commitment = same tile
        5, 1, 1,
    );
}

#[test(should_fail_with = "from_commitment does not match")]
fn test_wrong_from_commitment_fails() {
    let from_x: Field = 1000001;
    let from_y: Field = 1000001;
    let to_x: Field   = 1000002;
    let to_y: Field   = 1000001;
    let secret: Field = 33333;

    let wrong_commitment: Field = 0; // garbage commitment
    let to_c = Poseidon2::hash([to_x, to_y, secret], 3);

    main(
        from_x, from_y, to_x, to_y,
        secret,
        1, 0, true, true,
        wrong_commitment, to_c, // wrong from_commitment
        5, 1, 1,
    );
}

#[test(should_fail_with = "to_x coordinate is inconsistent")]
fn test_lying_about_destination_fails() {
    // Prover claims small dx but commits to distant tile — should fail
    let from_x: Field = 1000000;
    let from_y: Field = 1000000;
    let actual_to_x: Field = 1000050; // actually 50 tiles away
    let secret: Field = 44444;

    let from_c = Poseidon2::hash([from_x, from_y, secret], 3);
    // Commit to actual distant position
    let to_c   = Poseidon2::hash([actual_to_x, from_y, secret], 3);

    main(
        from_x, from_y,
        actual_to_x, from_y,
        secret,
        1, 0,   // claims dx=1 but actual dx=50 → inconsistency
        true, true,
        from_c, to_c,
        5, 1, 1,
    );
}

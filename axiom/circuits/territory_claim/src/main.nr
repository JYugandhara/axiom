// ─────────────────────────────────────────────────────────────
//  AXIOM — Territory Claim Circuit
//  File: circuits/territory_claim/src/main.nr
// ─────────────────────────────────────────────────────────────
//
//  WHAT THIS PROVES
//  ────────────────
//  A civilization claims ownership of tile (claim_x, claim_y) by
//  proving ALL of the following WITHOUT revealing coordinates:
//
//    1. Prover knows the claim tile coordinates and civ secret
//    2. claim_commitment = Poseidon2(claim_x, claim_y, civ_secret)
//    3. Prover already owns an adjacent tile (anchor tile)
//    4. anchor_commitment = Poseidon2(anchor_x, anchor_y, civ_secret)
//    5. The claim tile is exactly 1 step from the anchor tile
//       (Manhattan distance = 1 — must be directly adjacent, no diagonals)
//    6. The civ_id_hash binds the claim to a specific civilization
//       civ_id_hash = Poseidon2(civ_id, civ_secret)
//
//  WHY THIS DESIGN
//  ────────────────
//  Territory expansion must be provably adjacent — you can't teleport
//  and claim tiles on the other side of the map. But we don't want to
//  reveal which specific tiles you're expanding to (fog of war).
//
//  The anchor tile must already be recorded in TerritoryMap.sol.
//  ClaimSystem.sol checks: anchor_commitment ∈ owned_commitments[civ_id]
//
//  ADJACENCY RULE
//  ──────────────
//  Valid claim: |dx| + |dy| = 1  (4-directional: N/E/S/W)
//  Invalid:     |dx| + |dy| > 1  (too far)
//  Invalid:     |dx| + |dy| = 0  (same tile as anchor)
//  Diagonal movement (|dx|=1, |dy|=1) is NOT allowed by this circuit.
//
//  USAGE (from circuits/territory_claim/)
//  ───────────────────────────────────────
//  1. Fill Prover.toml with your values
//  2. nargo prove    →  generates proof
//  3. nargo codegen-verifier  →  TerritoryVerifier.sol
// ─────────────────────────────────────────────────────────────

use dep::std::hash::poseidon2::Poseidon2;

// ─────────────────────────────────────────────────────────────
//  Constants
// ─────────────────────────────────────────────────────────────

/// Tiles must be directly adjacent (4-directional only, no diagonals)
global REQUIRED_ADJACENCY: u32 = 1;

// ─────────────────────────────────────────────────────────────
//  Main Circuit
// ─────────────────────────────────────────────────────────────

fn main(
    // ── Private inputs ─────────────────────────────────────────

    /// Coordinates of the tile being claimed (private until revealed)
    claim_x          : Field,
    claim_y          : Field,

    /// Coordinates of an already-owned adjacent tile (anchor)
    anchor_x         : Field,
    anchor_y         : Field,

    /// Civilization's private salt — ties commitment to this civ only
    civ_secret       : Field,

    /// |claim_x - anchor_x| as unsigned magnitude
    dx_magnitude     : u32,

    /// |claim_y - anchor_y| as unsigned magnitude
    dy_magnitude     : u32,

    /// True if claim_x > anchor_x
    dx_positive      : bool,

    /// True if claim_y > anchor_y
    dy_positive      : bool,

    // ── Public inputs (visible on-chain) ────────────────────────

    /// Poseidon2(claim_x, claim_y, civ_secret)
    /// Becomes the new entry in TerritoryMap for this civ
    claim_commitment  : pub Field,

    /// Poseidon2(anchor_x, anchor_y, civ_secret)
    /// Must already exist in TerritoryMap — checked on-chain by ClaimSystem
    anchor_commitment : pub Field,

    /// Poseidon2(civ_id, civ_secret)
    /// Binds this proof to one specific civilization — prevents
    /// using another civ's proof to claim your own territory
    civ_id_hash       : pub Field,

    /// The civilization's on-chain ID
    civ_id            : pub Field,

    /// Current game season — proofs from past seasons are rejected
    season            : pub u32,

    /// Anti-replay nonce — must match CivilizationState.claim_nonce
    nonce             : pub Field,
) {
    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 1: Verify claim_commitment
    //  Proves prover knows the real (claim_x, claim_y)
    // ═══════════════════════════════════════════════════════════

    let computed_claim = Poseidon2::hash([claim_x, claim_y, civ_secret], 3);

    assert(
        computed_claim == claim_commitment,
        "claim_commitment mismatch: Poseidon2(claim_x, claim_y, civ_secret)"
    );

    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 2: Verify anchor_commitment
    //  Proves prover knows the real (anchor_x, anchor_y) they own
    // ═══════════════════════════════════════════════════════════

    let computed_anchor = Poseidon2::hash([anchor_x, anchor_y, civ_secret], 3);

    assert(
        computed_anchor == anchor_commitment,
        "anchor_commitment mismatch: Poseidon2(anchor_x, anchor_y, civ_secret)"
    );

    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 3: Verify civ_id_hash
    //  Binds the proof to this specific civilization.
    //  Prevents Civ A from stealing Civ B's proof.
    // ═══════════════════════════════════════════════════════════

    let computed_civ_hash = Poseidon2::hash([civ_id, civ_secret], 2);

    assert(
        computed_civ_hash == civ_id_hash,
        "civ_id_hash mismatch: Poseidon2(civ_id, civ_secret)"
    );

    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 4: Strict adjacency check
    //  |dx| + |dy| must equal exactly 1 (4-directional only)
    //  This means exactly one of dx or dy is 1, the other is 0.
    // ═══════════════════════════════════════════════════════════

    let total_distance: u32 = dx_magnitude + dy_magnitude;

    assert(
        total_distance == REQUIRED_ADJACENCY,
        "Claim tile must be exactly 1 step from anchor tile (no diagonals)"
    );

    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 5: Coordinate consistency
    //  Verifies (claim_x, claim_y) = (anchor_x, anchor_y) + signed delta
    //  This ties the commitment to the actual position claimed.
    // ═══════════════════════════════════════════════════════════

    let dx_field: Field = dx_magnitude as Field;
    let dy_field: Field = dy_magnitude as Field;

    let expected_claim_x: Field = if dx_positive {
        anchor_x + dx_field
    } else {
        anchor_x - dx_field
    };

    let expected_claim_y: Field = if dy_positive {
        anchor_y + dy_field
    } else {
        anchor_y - dy_field
    };

    assert(
        expected_claim_x == claim_x,
        "claim_x is inconsistent with anchor_x and dx"
    );

    assert(
        expected_claim_y == claim_y,
        "claim_y is inconsistent with anchor_y and dy"
    );

    // ═══════════════════════════════════════════════════════════
    //  CONSTRAINT 6: Cannot claim the anchor tile itself
    //  (guaranteed by total_distance == 1, but explicit for clarity)
    // ═══════════════════════════════════════════════════════════

    // Ensured by Constraint 4: if total_distance == 1 then claim != anchor.
    // No additional assertion needed.

    // Season and nonce are public inputs — their presence binds
    // the proof to the current season and nonce without extra constraints.
    let _ = season;
    let _ = nonce;
}

// ─────────────────────────────────────────────────────────────
//  Helper: batch adjacency check
//  For multi-tile expansion proofs (future feature)
// ─────────────────────────────────────────────────────────────

/// Returns true if two tiles are directly adjacent (4-directional).
/// Unconstrained — use in tests and off-circuit helpers only.
unconstrained fn is_adjacent(x1: Field, y1: Field, x2: Field, y2: Field) -> bool {
    // Manhattan distance == 1
    // Using abs for field elements is tricky — this is only for off-circuit use
    let dx = if x2 > x1 { x2 - x1 } else { x1 - x2 };
    let dy = if y2 > y1 { y2 - y1 } else { y1 - y2 };
    (dx + dy) == 1
}

/// Compute all 4 neighboring tile commitments for a given position.
/// Used in the frontend to precompute valid expansion candidates.
unconstrained fn compute_neighbor_commitments(
    x: Field,
    y: Field,
    civ_secret: Field,
) -> [Field; 4] {
    [
        Poseidon2::hash([x + 1, y,     civ_secret], 3), // east
        Poseidon2::hash([x - 1, y,     civ_secret], 3), // west
        Poseidon2::hash([x,     y + 1, civ_secret], 3), // north
        Poseidon2::hash([x,     y - 1, civ_secret], 3), // south
    ]
}

// ─────────────────────────────────────────────────────────────
//  Tests
//  Run with: nargo test (from circuits/territory_claim/)
// ─────────────────────────────────────────────────────────────

#[test]
fn test_valid_claim_north() {
    // Civ owns (50, 50) and claims (50, 51) — one step north
    let anchor_x: Field = 1000050;
    let anchor_y: Field = 1000050;
    let claim_x: Field  = 1000050; // same X
    let claim_y: Field  = 1000051; // +1 north
    let civ_secret: Field = 888888;
    let civ_id: Field   = 42;

    let claim_c  = Poseidon2::hash([claim_x,  claim_y,  civ_secret], 3);
    let anchor_c = Poseidon2::hash([anchor_x, anchor_y, civ_secret], 3);
    let civ_hash = Poseidon2::hash([civ_id, civ_secret], 2);

    main(
        claim_x, claim_y,
        anchor_x, anchor_y,
        civ_secret,
        0, 1,           // dx=0, dy=1 (north)
        true, true,     // dy positive (north)
        claim_c, anchor_c, civ_hash,
        civ_id,
        1,   // season
        1,   // nonce
    );
}

#[test]
fn test_valid_claim_east() {
    let anchor_x: Field = 1000020;
    let anchor_y: Field = 1000030;
    let claim_x: Field  = 1000021; // +1 east
    let claim_y: Field  = 1000030; // same Y
    let civ_secret: Field = 777777;
    let civ_id: Field = 7;

    let claim_c  = Poseidon2::hash([claim_x,  claim_y,  civ_secret], 3);
    let anchor_c = Poseidon2::hash([anchor_x, anchor_y, civ_secret], 3);
    let civ_hash = Poseidon2::hash([civ_id, civ_secret], 2);

    main(
        claim_x, claim_y,
        anchor_x, anchor_y,
        civ_secret,
        1, 0,           // dx=1 east, dy=0
        true, true,
        claim_c, anchor_c, civ_hash,
        civ_id, 2, 5,
    );
}

#[test]
fn test_valid_claim_west_negative_direction() {
    // Claiming west: claim_x = anchor_x - 1
    let anchor_x: Field = 1000010;
    let anchor_y: Field = 1000010;
    let claim_x: Field  = 1000009; // -1 west
    let claim_y: Field  = 1000010;
    let civ_secret: Field = 666666;
    let civ_id: Field = 3;

    let claim_c  = Poseidon2::hash([claim_x,  claim_y,  civ_secret], 3);
    let anchor_c = Poseidon2::hash([anchor_x, anchor_y, civ_secret], 3);
    let civ_hash = Poseidon2::hash([civ_id, civ_secret], 2);

    main(
        claim_x, claim_y,
        anchor_x, anchor_y,
        civ_secret,
        1, 0,           // dx=1, direction is west (negative)
        false, true,    // dx_positive=false (west), dy irrelevant
        claim_c, anchor_c, civ_hash,
        civ_id, 1, 2,
    );
}

#[test(should_fail_with = "Claim tile must be exactly 1 step")]
fn test_diagonal_claim_fails() {
    // Diagonal claim: dx=1, dy=1 → total=2 → should fail
    let anchor_x: Field = 1000000;
    let anchor_y: Field = 1000000;
    let claim_x: Field  = 1000001;
    let claim_y: Field  = 1000001;
    let civ_secret: Field = 11111;
    let civ_id: Field = 1;

    let claim_c  = Poseidon2::hash([claim_x,  claim_y,  civ_secret], 3);
    let anchor_c = Poseidon2::hash([anchor_x, anchor_y, civ_secret], 3);
    let civ_hash = Poseidon2::hash([civ_id, civ_secret], 2);

    main(
        claim_x, claim_y, anchor_x, anchor_y, civ_secret,
        1, 1,         // total distance = 2 — diagonal not allowed
        true, true,
        claim_c, anchor_c, civ_hash,
        civ_id, 1, 1,
    );
}

#[test(should_fail_with = "Claim tile must be exactly 1 step")]
fn test_too_far_claim_fails() {
    // Claim 5 tiles away — should fail
    let anchor_x: Field = 1000000;
    let anchor_y: Field = 1000000;
    let claim_x: Field  = 1000005;
    let claim_y: Field  = 1000000;
    let civ_secret: Field = 22222;
    let civ_id: Field = 2;

    let claim_c  = Poseidon2::hash([claim_x,  claim_y,  civ_secret], 3);
    let anchor_c = Poseidon2::hash([anchor_x, anchor_y, civ_secret], 3);
    let civ_hash = Poseidon2::hash([civ_id, civ_secret], 2);

    main(
        claim_x, claim_y, anchor_x, anchor_y, civ_secret,
        5, 0,
        true, true,
        claim_c, anchor_c, civ_hash,
        civ_id, 1, 1,
    );
}

#[test(should_fail_with = "claim_commitment mismatch")]
fn test_wrong_claim_commitment_fails() {
    let anchor_x: Field = 1000000;
    let anchor_y: Field = 1000000;
    let claim_x: Field  = 1000001;
    let claim_y: Field  = 1000000;
    let civ_secret: Field = 33333;
    let civ_id: Field = 5;

    let wrong_claim_c: Field = 9999; // wrong commitment
    let anchor_c = Poseidon2::hash([anchor_x, anchor_y, civ_secret], 3);
    let civ_hash = Poseidon2::hash([civ_id, civ_secret], 2);

    main(
        claim_x, claim_y, anchor_x, anchor_y, civ_secret,
        1, 0, true, true,
        wrong_claim_c, anchor_c, civ_hash,
        civ_id, 1, 1,
    );
}

#[test(should_fail_with = "civ_id_hash mismatch")]
fn test_wrong_civ_secret_fails() {
    // Attacker uses correct coordinates but wrong civ_secret
    let anchor_x: Field = 1000000;
    let anchor_y: Field = 1000000;
    let claim_x: Field  = 1000001;
    let claim_y: Field  = 1000000;
    let real_secret: Field  = 44444;
    let wrong_secret: Field = 99999; // attacker's secret, not this civ's
    let civ_id: Field = 1;

    // Commitments computed with correct secret
    let claim_c  = Poseidon2::hash([claim_x,  claim_y,  real_secret], 3);
    let anchor_c = Poseidon2::hash([anchor_x, anchor_y, real_secret], 3);
    // But civ_hash computed with wrong secret — mismatch!
    let wrong_civ_hash = Poseidon2::hash([civ_id, wrong_secret], 2);

    main(
        claim_x, claim_y, anchor_x, anchor_y, real_secret,
        1, 0, true, true,
        claim_c, anchor_c, wrong_civ_hash,
        civ_id, 1, 1,
    );
}

#[test(should_fail_with = "claim_x is inconsistent")]
fn test_lying_about_claim_position_fails() {
    // Prover commits to tile at (10, 0) but says delta is dx=1 from anchor (0,0)
    // Real claim tile should be (1, 0), not (10, 0)
    let anchor_x: Field = 1000000;
    let anchor_y: Field = 1000000;
    let real_claim_x: Field = 1000010; // actually 10 tiles away
    let claim_y: Field = 1000000;
    let civ_secret: Field = 55555;
    let civ_id: Field = 9;

    let claim_c  = Poseidon2::hash([real_claim_x, claim_y, civ_secret], 3);
    let anchor_c = Poseidon2::hash([anchor_x, anchor_y, civ_secret], 3);
    let civ_hash = Poseidon2::hash([civ_id, civ_secret], 2);

    main(
        real_claim_x, claim_y,  // actual distant position
        anchor_x, anchor_y,
        civ_secret,
        1, 0,    // claims dx=1 but actual dx=10 → fails consistency check
        true, true,
        claim_c, anchor_c, civ_hash,
        civ_id, 1, 1,
    );
}

// ─────────────────────────────────────────────────────────────
//  Noir Witness Computation — browser-side
//  Computes Poseidon2 commitments and witness values
//  needed to fill in ZK proof inputs.
//
//  Used by useZKProof hook before calling noir.execute().
// ─────────────────────────────────────────────────────────────

// Coordinate encoding: actual world coordinate + COORD_OFFSET
export const COORD_OFFSET = 1_000_000n;

export function encodeCoord(worldCoord: number): bigint {
  return BigInt(worldCoord) + COORD_OFFSET;
}

export function decodeCoord(fieldCoord: bigint): number {
  return Number(fieldCoord - COORD_OFFSET);
}

// ─────────────────────────────────────────────────────────────
//  Compute delta (signed magnitude representation)
// ─────────────────────────────────────────────────────────────

export interface SignedDelta {
  magnitude : number;
  positive  : boolean;
}

export function computeDelta(from: number, to: number): SignedDelta {
  const diff = to - from;
  return {
    magnitude: Math.abs(diff),
    positive : diff >= 0,
  };
}

// ─────────────────────────────────────────────────────────────
//  Fog of War witness builder
// ─────────────────────────────────────────────────────────────

export interface FogWitnessInputs {
  fromX          : number;   // world coordinate
  fromY          : number;
  toX            : number;
  toY            : number;
  playerSecret   : string;   // hex or decimal string
  movementRange  : number;
  nonce          : number;
  season         : number;
  fromCommitment : string;   // pre-computed — fill after nargo execute
  toCommitment   : string;
}

export function buildFogWitness(inputs: FogWitnessInputs): Record<string, string | boolean> {
  const dx = computeDelta(inputs.fromX, inputs.toX);
  const dy = computeDelta(inputs.fromY, inputs.toY);

  return {
    from_x          : encodeCoord(inputs.fromX).toString(),
    from_y          : encodeCoord(inputs.fromY).toString(),
    to_x            : encodeCoord(inputs.toX).toString(),
    to_y            : encodeCoord(inputs.toY).toString(),
    player_secret   : inputs.playerSecret,
    dx_magnitude    : dx.magnitude.toString(),
    dy_magnitude    : dy.magnitude.toString(),
    dx_positive     : dx.positive,
    dy_positive     : dy.positive,
    from_commitment : inputs.fromCommitment,
    to_commitment   : inputs.toCommitment,
    movement_range  : inputs.movementRange.toString(),
    nonce           : inputs.nonce.toString(),
    season          : inputs.season.toString(),
  };
}

// ─────────────────────────────────────────────────────────────
//  Territory Claim witness builder
// ─────────────────────────────────────────────────────────────

export interface ClaimWitnessInputs {
  claimX           : number;
  claimY           : number;
  anchorX          : number;
  anchorY          : number;
  civSecret        : string;
  civId            : number;
  season           : number;
  nonce            : number;
  claimCommitment  : string;
  anchorCommitment : string;
  civIdHash        : string;
}

export function buildClaimWitness(inputs: ClaimWitnessInputs): Record<string, string | boolean> {
  const dx = computeDelta(inputs.anchorX, inputs.claimX);
  const dy = computeDelta(inputs.anchorY, inputs.claimY);

  return {
    claim_x           : encodeCoord(inputs.claimX).toString(),
    claim_y           : encodeCoord(inputs.claimY).toString(),
    anchor_x          : encodeCoord(inputs.anchorX).toString(),
    anchor_y          : encodeCoord(inputs.anchorY).toString(),
    civ_secret        : inputs.civSecret,
    dx_magnitude      : dx.magnitude.toString(),
    dy_magnitude      : dy.magnitude.toString(),
    dx_positive       : dx.positive,
    dy_positive       : dy.positive,
    claim_commitment  : inputs.claimCommitment,
    anchor_commitment : inputs.anchorCommitment,
    civ_id_hash       : inputs.civIdHash,
    civ_id            : inputs.civId.toString(),
    season            : inputs.season.toString(),
    nonce             : inputs.nonce.toString(),
  };
}

// ─────────────────────────────────────────────────────────────
//  Player secret management
//  Stored in localStorage — never sent to any server
// ─────────────────────────────────────────────────────────────

const SECRET_KEY = "axiom_player_secret";

export function getOrCreatePlayerSecret(): string {
  if (typeof window === "undefined") return "0";
  const existing = localStorage.getItem(SECRET_KEY);
  if (existing) return existing;

  // Generate a random 31-byte secret (fits in BN254 field)
  const bytes  = crypto.getRandomValues(new Uint8Array(31));
  const hex    = Array.from(bytes).map(b => b.toString(16).padStart(2, "0")).join("");
  const secret = BigInt("0x" + hex).toString();
  localStorage.setItem(SECRET_KEY, secret);
  return secret;
}

export function getCivSecret(civId: number): string {
  if (typeof window === "undefined") return "0";
  const key = `axiom_civ_secret_${civId}`;
  const existing = localStorage.getItem(key);
  if (existing) return existing;

  const bytes  = crypto.getRandomValues(new Uint8Array(31));
  const hex    = Array.from(bytes).map(b => b.toString(16).padStart(2, "0")).join("");
  const secret = BigInt("0x" + hex).toString();
  localStorage.setItem(key, secret);
  return secret;
}

// ─────────────────────────────────────────────────────────────
//  Validate move before proving (cheap pre-check)
// ─────────────────────────────────────────────────────────────

export function validateMove(
  fromX: number, fromY: number,
  toX: number,   toY: number,
  movementRange: number
): { valid: boolean; error?: string } {
  const distance = Math.abs(toX - fromX) + Math.abs(toY - fromY);
  if (distance === 0)              return { valid: false, error: "Cannot move to same tile" };
  if (distance > movementRange)    return { valid: false, error: `Move distance ${distance} exceeds range ${movementRange}` };
  if (movementRange > 100)         return { valid: false, error: "Movement range exceeds maximum" };
  return { valid: true };
}

export function validateClaim(
  claimX: number, claimY: number,
  anchorX: number, anchorY: number
): { valid: boolean; error?: string } {
  const distance = Math.abs(claimX - anchorX) + Math.abs(claimY - anchorY);
  if (distance !== 1) return { valid: false, error: `Tile must be exactly adjacent (distance=${distance})` };
  return { valid: true };
}

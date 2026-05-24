"use client";

import { useState, useCallback, useRef } from "react";

// ─────────────────────────────────────────────────────────────
//  useZKProof
//  Generates Noir ZK proofs client-side using @noir-lang/noir_js
//  Called by TileModal (claim proof) and MoveModal (move proof)
// ─────────────────────────────────────────────────────────────

interface FogProofInputs {
  fromX       : number;
  fromY       : number;
  toX         : number;
  toY         : number;
  playerSecret: string;
  dxMagnitude : number;
  dyMagnitude : number;
  dxPositive  : boolean;
  dyPositive  : boolean;
  // Public
  fromCommitment  : string;
  toCommitment    : string;
  movementRange   : number;
  nonce           : number;
  season          : number;
}

interface ClaimProofInputs {
  claimX          : number;
  claimY          : number;
  anchorX         : number;
  anchorY         : number;
  civSecret       : string;
  dxMagnitude     : number;
  dyMagnitude     : number;
  dxPositive      : boolean;
  dyPositive      : boolean;
  // Public
  claimCommitment : string;
  anchorCommitment: string;
  civIdHash       : string;
  civId           : number;
  season          : number;
  nonce           : number;
}

interface ZKProofResult {
  proof      : Uint8Array;
  publicInputs: string[];
}

export function useZKProof() {
  const [isProving, setIsProving]   = useState(false);
  const [progress,  setProgress]    = useState(0);
  const [error,     setError]       = useState<string | null>(null);

  // Lazy-load Noir.js to avoid SSR issues
  const noirRef = useRef<any>(null);

  const loadNoir = useCallback(async () => {
    if (noirRef.current) return noirRef.current;
    const [{ Noir }, { BarretenbergBackend }] = await Promise.all([
      import("@noir-lang/noir_js"),
      import("@noir-lang/backend_barretenberg"),
    ]);
    noirRef.current = { Noir, BarretenbergBackend };
    return noirRef.current;
  }, []);

  // ── Load a compiled circuit artifact ───────────────────────
  const loadCircuit = useCallback(async (circuitName: "fog_of_war" | "territory_claim") => {
    const res = await fetch(`/circuits/${circuitName}.json`);
    if (!res.ok) throw new Error(`Circuit not found: ${circuitName}.json — run nargo compile first`);
    return res.json();
  }, []);

  // ── Generate fog-of-war movement proof ─────────────────────
  const generateMoveProof = useCallback(async (inputs: FogProofInputs): Promise<ZKProofResult> => {
    setIsProving(true);
    setProgress(0);
    setError(null);

    try {
      const { Noir, BarretenbergBackend } = await loadNoir();
      setProgress(10);

      const circuit = await loadCircuit("fog_of_war");
      setProgress(20);

      const backend = new BarretenbergBackend(circuit, { threads: navigator.hardwareConcurrency ?? 4 });
      const noir    = new Noir(circuit, backend);
      setProgress(30);

      // Build witness
      const witness = {
        from_x         : inputs.fromX.toString(),
        from_y         : inputs.fromY.toString(),
        to_x           : inputs.toX.toString(),
        to_y           : inputs.toY.toString(),
        player_secret  : inputs.playerSecret,
        dx_magnitude   : inputs.dxMagnitude.toString(),
        dy_magnitude   : inputs.dyMagnitude.toString(),
        dx_positive    : inputs.dxPositive,
        dy_positive    : inputs.dyPositive,
        from_commitment: inputs.fromCommitment,
        to_commitment  : inputs.toCommitment,
        movement_range : inputs.movementRange.toString(),
        nonce          : inputs.nonce.toString(),
        season         : inputs.season.toString(),
      };
      setProgress(40);

      // Execute + prove (the slow step — ~3-8s)
      const { witness: solved } = await noir.execute(witness);
      setProgress(70);

      const { proof, publicInputs } = await backend.generateProof(solved);
      setProgress(95);

      await backend.destroy();
      setProgress(100);

      return { proof, publicInputs };
    } catch (e: any) {
      setError(e.message);
      throw e;
    } finally {
      setIsProving(false);
    }
  }, [loadNoir, loadCircuit]);

  // ── Generate territory claim proof ──────────────────────────
  const generateClaimProof = useCallback(async (inputs: Partial<ClaimProofInputs> & {
    claimCommitment: string;
    anchorCommitment: string;
    civSecret: string;
    civId: number;
  }): Promise<ZKProofResult> => {
    setIsProving(true);
    setProgress(0);
    setError(null);

    try {
      const { Noir, BarretenbergBackend } = await loadNoir();
      setProgress(15);

      const circuit = await loadCircuit("territory_claim");
      setProgress(25);

      const backend = new BarretenbergBackend(circuit, { threads: navigator.hardwareConcurrency ?? 4 });
      const noir    = new Noir(circuit, backend);
      setProgress(35);

      // For claim proof, compute the civ_id_hash client-side
      // In production: use a proper Poseidon JS implementation
      const witness = {
        claim_x          : (inputs.claimX ?? 0).toString(),
        claim_y          : (inputs.claimY ?? 0).toString(),
        anchor_x         : (inputs.anchorX ?? 0).toString(),
        anchor_y         : (inputs.anchorY ?? 0).toString(),
        civ_secret       : inputs.civSecret,
        dx_magnitude     : (inputs.dxMagnitude ?? 0).toString(),
        dy_magnitude     : (inputs.dyMagnitude ?? 1).toString(),
        dx_positive      : inputs.dxPositive ?? true,
        dy_positive      : inputs.dyPositive ?? true,
        claim_commitment : inputs.claimCommitment,
        anchor_commitment: inputs.anchorCommitment,
        civ_id_hash      : inputs.civIdHash ?? "0",
        civ_id           : inputs.civId.toString(),
        season           : (inputs.season ?? 1).toString(),
        nonce            : (inputs.nonce ?? 0).toString(),
      };
      setProgress(45);

      const { witness: solved } = await noir.execute(witness);
      setProgress(75);

      const { proof, publicInputs } = await backend.generateProof(solved);
      setProgress(95);

      await backend.destroy();
      setProgress(100);

      return { proof, publicInputs };
    } catch (e: any) {
      setError(e.message);
      throw e;
    } finally {
      setIsProving(false);
    }
  }, [loadNoir, loadCircuit]);

  return {
    generateMoveProof,
    generateClaimProof,
    isProving,
    progress,
    error,
  };
}

"use client";

import { useZKProof } from "../../hooks/useZKProof";
import { useAccount } from "wagmi";
import { toast } from "sonner";

interface TileModalProps {
  tile: { commitment: string; owner: number };
  onClose: () => void;
}

// ─────────────────────────────────────────────────────────────
//  TileModal — shown when player clicks a tile on the world map
// ─────────────────────────────────────────────────────────────

export default function TileModal({ tile, onClose }: TileModalProps) {
  const { address } = useAccount();
  const { generateClaimProof, isProving, progress } = useZKProof();

  const handleClaim = async () => {
    if (!address) { toast.error("Connect wallet first"); return; }
    try {
      toast.info("Generating ZK proof… this takes ~5s");
      const proof = await generateClaimProof({
        claimCommitment : tile.commitment,
        anchorCommitment: "0x" + "0".repeat(64), // set from actual anchor tile
        civSecret       : "0",                    // read from local storage
        civId           : 1,
      });
      toast.success("Proof generated! Submitting on-chain…");
      // writeContract → ClaimSystem.claim(...)
    } catch (e: any) {
      toast.error(`Proof failed: ${e.message}`);
    }
  };

  return (
    <div className="absolute inset-0 flex items-center justify-center z-30 pointer-events-none">
      <div className="game-card w-80 pointer-events-auto shadow-2xl border-border-default">
        {/* Header */}
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-mono font-semibold text-text-primary">Tile Details</h3>
          <button onClick={onClose} className="text-text-muted hover:text-text-primary text-lg leading-none">×</button>
        </div>

        {/* Commitment */}
        <div className="mb-4">
          <div className="text-xs font-mono text-text-muted mb-1">Commitment Hash</div>
          <div className="bg-bg-tertiary rounded-lg px-3 py-2 font-mono text-xs text-text-secondary break-all">
            {tile.commitment.slice(0, 20)}…{tile.commitment.slice(-8)}
          </div>
        </div>

        {/* Ownership */}
        <div className="mb-4 flex items-center gap-2">
          <div className={`w-2 h-2 rounded-full ${tile.owner === 0 ? "bg-border-default" : tile.owner === 1 ? "bg-accent-blue" : "bg-red-500"}`} />
          <span className="text-sm font-mono text-text-secondary">
            {tile.owner === 0 ? "Unclaimed" : tile.owner === 1 ? "Your territory" : `Civ #${tile.owner}`}
          </span>
        </div>

        {/* ZK proof progress */}
        {isProving && (
          <div className="mb-4">
            <div className="text-xs font-mono text-text-muted mb-1">Generating ZK proof…</div>
            <div className="h-1 bg-bg-tertiary rounded-full overflow-hidden">
              <div className="proof-bar" style={{ width: `${progress}%` }} />
            </div>
          </div>
        )}

        {/* Actions */}
        {tile.owner === 0 && (
          <button onClick={handleClaim} disabled={isProving}
            className="w-full py-2.5 rounded-lg bg-accent-green/20 border border-accent-green/40 text-accent-green font-mono text-sm hover:bg-accent-green/30 disabled:opacity-40 transition-all">
            {isProving ? `Proving… ${progress}%` : "Claim This Tile"}
          </button>
        )}
        {tile.owner === 1 && (
          <button className="w-full py-2.5 rounded-lg bg-accent-blue/20 border border-accent-blue/40 text-accent-blue font-mono text-sm hover:bg-accent-blue/30 transition-all">
            Move Here
          </button>
        )}
        {tile.owner > 1 && (
          <button className="w-full py-2.5 rounded-lg bg-red-500/10 border border-red-500/30 text-red-400 font-mono text-sm hover:bg-red-500/20 transition-all">
            Attack (costs 100 ENERGY)
          </button>
        )}
      </div>
    </div>
  );
}

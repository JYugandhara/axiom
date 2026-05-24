"use client";

import { useReadContract } from "wagmi";
import { ADDRESSES } from "../../lib/contracts/addresses";
import { CIV_NFT_ABI } from "../../lib/contracts/abis/CivilizationNFT";
import Link from "next/link";

interface CivCardProps {
  civId: bigint;
}

export default function CivCard({ civId }: CivCardProps) {
  const { data: meta } = useReadContract({
    address: ADDRESSES.l3.civNFT as `0x${string}`,
    abi: CIV_NFT_ABI,
    functionName: "metadata",
    args: [civId],
  });

  const { data: tba } = useReadContract({
    address: ADDRESSES.l3.civNFT as `0x${string}`,
    abi: CIV_NFT_ABI,
    functionName: "agentAccountOf",
    args: [civId],
  });

  const name       = (meta as any)?.[0] ?? `Civilization #${civId}`;
  const modelHash  = (meta as any)?.[1] ?? "0x" + "0".repeat(64);
  const autonomous = (meta as any)?.[2] ?? false;
  const hasModel   = modelHash !== "0x" + "0".repeat(64);

  return (
    <div className="game-card hover:border-border-default transition-colors">
      {/* Header */}
      <div className="flex items-start justify-between mb-4">
        <div>
          <div className="text-xs font-mono text-text-muted mb-0.5">Civ #{civId.toString()}</div>
          <h3 className="font-mono font-bold text-text-primary text-lg">{name}</h3>
        </div>
        <div className="flex flex-col items-end gap-1">
          {autonomous && (
            <span className="text-xs font-mono text-accent-purple bg-accent-purple/10 border border-accent-purple/30 px-2 py-0.5 rounded-full agent-pulse">
              🤖 Autonomous
            </span>
          )}
          {hasModel && !autonomous && (
            <span className="text-xs font-mono text-accent-amber bg-accent-amber/10 border border-accent-amber/30 px-2 py-0.5 rounded-full">
              Model deployed
            </span>
          )}
        </div>
      </div>

      {/* Stats grid */}
      <div className="grid grid-cols-3 gap-3 mb-4">
        {[
          { label: "Territory", value: "—", unit: "tiles",  color: "text-accent-blue" },
          { label: "Energy",    value: "—", unit: "ENERGY", color: "text-accent-green" },
          { label: "Battles",   value: "—", unit: "won",    color: "text-accent-amber" },
        ].map(({ label, value, unit, color }) => (
          <div key={label} className="bg-bg-tertiary rounded-lg p-2.5 text-center">
            <div className={`text-lg font-mono font-bold ${color}`}>{value}</div>
            <div className="text-text-muted text-xs font-mono">{label}</div>
            <div className="text-text-muted text-[10px]">{unit}</div>
          </div>
        ))}
      </div>

      {/* Stat bars */}
      <div className="space-y-2 mb-4">
        {[
          { label: "Attack",  value: 50, color: "bg-red-500" },
          { label: "Defense", value: 50, color: "bg-blue-500" },
        ].map(({ label, value, color }) => (
          <div key={label}>
            <div className="flex justify-between text-xs font-mono text-text-muted mb-1">
              <span>{label}</span>
              <span>{value}/100</span>
            </div>
            <div className="h-1.5 bg-bg-tertiary rounded-full overflow-hidden">
              <div className={`h-full ${color} rounded-full`} style={{ width: `${value}%` }} />
            </div>
          </div>
        ))}
      </div>

      {/* TBA address */}
      {tba && (
        <div className="mb-4 text-xs font-mono">
          <div className="text-text-muted mb-0.5">Agent Account (ERC-6551)</div>
          <div className="text-text-secondary truncate">{tba as string}</div>
        </div>
      )}

      {/* Actions */}
      <div className="flex gap-2">
        <Link href={`/world`}
          className="flex-1 py-2 rounded-lg bg-bg-tertiary border border-border-subtle text-text-secondary hover:text-text-primary hover:border-border-default font-mono text-xs text-center transition-all">
          View on Map
        </Link>
        <Link href={`/agent-studio`}
          className="flex-1 py-2 rounded-lg bg-accent-blue/10 border border-accent-blue/30 text-accent-blue hover:bg-accent-blue/20 font-mono text-xs text-center transition-all">
          Configure AI
        </Link>
      </div>
    </div>
  );
}

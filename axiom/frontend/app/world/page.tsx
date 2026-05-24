"use client";

import { Suspense, useState } from "react";
import dynamic from "next/dynamic";
import { useAccount } from "wagmi";

// Three.js WorldMap must be client-side only (no SSR)
const WorldMap = dynamic(() => import("../../components/world/WorldMap"), {
  ssr: false,
  loading: () => (
    <div className="flex items-center justify-center h-[calc(100vh-56px)] bg-bg-primary">
      <div className="text-center">
        <div className="text-accent-blue font-mono text-xl mb-2 animate-pulse">Syncing world state...</div>
        <div className="text-text-muted text-sm font-mono">Connecting to MUD world</div>
      </div>
    </div>
  ),
});

const TileModal = dynamic(() => import("../../components/world/TileModal"), { ssr: false });

export default function WorldPage() {
  const { isConnected } = useAccount();
  const [selectedTile, setSelectedTile] = useState<{ commitment: string; owner: number } | null>(null);
  const [showCoords, setShowCoords] = useState(false);

  return (
    <div className="relative h-[calc(100vh-56px)] overflow-hidden bg-bg-primary">

      {/* World map canvas */}
      <WorldMap onTileClick={setSelectedTile} />

      {/* HUD — top left */}
      <div className="absolute top-4 left-4 z-10 flex flex-col gap-2">
        <div className="game-card text-xs font-mono min-w-[180px]">
          <div className="text-text-muted mb-1">Season 1</div>
          <div className="flex justify-between">
            <span className="text-text-secondary">Block</span>
            <span className="text-accent-blue">—</span>
          </div>
          <div className="flex justify-between">
            <span className="text-text-secondary">Season ends</span>
            <span className="text-accent-amber">~6d 14h</span>
          </div>
        </div>
      </div>

      {/* Legend — bottom left */}
      <div className="absolute bottom-6 left-4 z-10 game-card text-xs font-mono">
        <div className="text-text-muted mb-2 text-[10px] uppercase tracking-wider">Legend</div>
        {[
          { color: "bg-blue-500/60",   label: "Your territory" },
          { color: "bg-red-500/60",    label: "Enemy territory" },
          { color: "bg-gray-700/60",   label: "Neutral / unclaimed" },
          { color: "bg-gray-950/80",   label: "Fog (unknown)" },
        ].map(({ color, label }) => (
          <div key={label} className="flex items-center gap-2 mb-1">
            <div className={`w-3 h-3 rounded-sm ${color}`} />
            <span className="text-text-secondary">{label}</span>
          </div>
        ))}
      </div>

      {/* Controls — bottom right */}
      <div className="absolute bottom-6 right-4 z-10 flex flex-col gap-2">
        <button onClick={() => setShowCoords(v => !v)}
          className="game-card text-xs font-mono text-text-secondary hover:text-text-primary transition-colors">
          {showCoords ? "Hide" : "Show"} Coords
        </button>
        <div className="game-card text-xs font-mono text-text-muted">
          Scroll to zoom · Drag to pan
        </div>
      </div>

      {/* Not connected banner */}
      {!isConnected && (
        <div className="absolute inset-x-0 bottom-0 z-20 bg-accent-amber/10 border-t border-accent-amber/30 px-6 py-3 text-center">
          <span className="text-accent-amber text-sm font-mono">
            Connect wallet to interact with the world
          </span>
        </div>
      )}

      {/* Tile detail modal */}
      {selectedTile && (
        <TileModal tile={selectedTile} onClose={() => setSelectedTile(null)} />
      )}
    </div>
  );
}

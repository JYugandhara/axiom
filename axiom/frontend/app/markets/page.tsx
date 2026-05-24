"use client";

import { useState } from "react";
import { useAccount, useWriteContract, useReadContract } from "wagmi";
import { ADDRESSES } from "../../lib/contracts/addresses";

// ─────────────────────────────────────────────────────────────
//  Markets Page
// ─────────────────────────────────────────────────────────────

export default function MarketsPage() {
  const { isConnected } = useAccount();
  const [betAmount, setBetAmount] = useState("10");
  const [selectedMarket, setSelectedMarket] = useState<number | null>(null);

  // Placeholder markets — replace with The Graph query
  const markets = [
    { id: 1, civId: 42, civName: "Iron Citadel", yesOdds: 65, noOdds: 35, totalPool: "12,500 AXM", closesIn: "5d 14h" },
    { id: 2, civId: 7,  civName: "Storm Nomads", yesOdds: 48, noOdds: 52, totalPool: "8,200 AXM",  closesIn: "5d 14h" },
    { id: 3, civId: 13, civName: "Deep Vault",   yesOdds: 22, noOdds: 78, totalPool: "3,100 AXM",  closesIn: "5d 14h" },
  ];

  return (
    <div className="max-w-5xl mx-auto px-6 py-10">
      <div className="mb-8">
        <h1 className="text-2xl font-mono font-bold text-text-primary mb-1">Prediction Markets</h1>
        <p className="text-text-secondary text-sm">
          Bet $AXM on which civilization wins Season 1. AMM pricing — odds update live.
        </p>
      </div>

      <div className="grid gap-4">
        {markets.map(m => (
          <div key={m.id} className={`game-card cursor-pointer transition-all ${selectedMarket === m.id ? "border-accent-blue" : "hover:border-border-default"}`}
            onClick={() => setSelectedMarket(selectedMarket === m.id ? null : m.id)}>

            <div className="flex items-center justify-between mb-3">
              <div>
                <span className="text-xs font-mono text-text-muted">Civ #{m.civId}</span>
                <h3 className="font-mono font-semibold text-text-primary">{m.civName} wins Season 1?</h3>
              </div>
              <div className="text-right">
                <div className="text-xs font-mono text-text-muted">Total pool</div>
                <div className="text-sm font-mono text-accent-amber">{m.totalPool}</div>
              </div>
            </div>

            {/* Odds bar */}
            <div className="flex rounded-lg overflow-hidden h-8 mb-3">
              <div className="bg-accent-green/30 flex items-center justify-center text-xs font-mono text-accent-green font-semibold"
                style={{ width: `${m.yesOdds}%` }}>
                YES {m.yesOdds}%
              </div>
              <div className="bg-red-500/20 flex items-center justify-center text-xs font-mono text-red-400 font-semibold flex-1">
                NO {m.noOdds}%
              </div>
            </div>

            <div className="flex items-center justify-between text-xs font-mono text-text-muted">
              <span>Closes in {m.closesIn}</span>
              <span className="text-accent-blue">Click to bet</span>
            </div>

            {/* Bet form — expands on click */}
            {selectedMarket === m.id && (
              <div className="mt-4 pt-4 border-t border-border-subtle flex gap-3 items-end">
                <div className="flex-1">
                  <label className="text-xs font-mono text-text-muted block mb-1">Amount ($AXM)</label>
                  <input value={betAmount} onChange={e => setBetAmount(e.target.value)}
                    className="w-full bg-bg-tertiary border border-border-default rounded-lg px-3 py-2 text-sm font-mono text-text-primary focus:outline-none focus:border-accent-blue" />
                </div>
                <button disabled={!isConnected}
                  className="px-4 py-2 rounded-lg bg-accent-green/20 border border-accent-green/40 text-accent-green font-mono text-sm hover:bg-accent-green/30 disabled:opacity-40 transition-all">
                  Bet YES
                </button>
                <button disabled={!isConnected}
                  className="px-4 py-2 rounded-lg bg-red-500/10 border border-red-500/30 text-red-400 font-mono text-sm hover:bg-red-500/20 disabled:opacity-40 transition-all">
                  Bet NO
                </button>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

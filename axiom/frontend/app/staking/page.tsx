"use client";

import { useState } from "react";
import { useAccount, useWriteContract } from "wagmi";

const LOCK_OPTIONS = [
  { label: "7 days",   days: 7,   apy: "10%",  multiplier: "1.0x" },
  { label: "30 days",  days: 30,  apy: "16%",  multiplier: "1.6x" },
  { label: "90 days",  days: 90,  apy: "24%",  multiplier: "2.4x" },
  { label: "180 days", days: 180, apy: "32%",  multiplier: "3.2x" },
  { label: "365 days", days: 365, apy: "40%",  multiplier: "4.0x" },
];

export default function StakingPage() {
  const { isConnected } = useAccount();
  const { writeContract, isPending } = useWriteContract();
  const [amount, setAmount]     = useState("100");
  const [lockIdx, setLockIdx]   = useState(1);

  const selected = LOCK_OPTIONS[lockIdx];

  // Placeholder positions — replace with contract reads
  const positions: any[] = [];

  return (
    <div className="max-w-4xl mx-auto px-6 py-10">
      <div className="mb-8">
        <h1 className="text-2xl font-mono font-bold text-text-primary mb-1">Stake $AXM</h1>
        <p className="text-text-secondary text-sm">
          Lock $AXM to earn $ENERGY generation multipliers. Longer locks = higher APY.
        </p>
      </div>

      <div className="grid md:grid-cols-5 gap-4 mb-8">
        {LOCK_OPTIONS.map((opt, i) => (
          <button key={i} onClick={() => setLockIdx(i)}
            className={`game-card text-center transition-all ${i === lockIdx ? "border-accent-blue bg-accent-blue/10" : "hover:border-border-default"}`}>
            <div className="text-lg font-mono font-bold text-accent-blue">{opt.apy}</div>
            <div className="text-xs text-text-secondary font-mono mt-1">{opt.label}</div>
            <div className="text-xs text-text-muted mt-0.5">{opt.multiplier} energy</div>
          </button>
        ))}
      </div>

      <div className="grid md:grid-cols-2 gap-6">
        {/* Stake form */}
        <div className="game-card">
          <h2 className="font-mono font-semibold text-text-primary mb-4">New Position</h2>

          <label className="text-xs font-mono text-text-muted block mb-1">Amount ($AXM)</label>
          <input value={amount} onChange={e => setAmount(e.target.value)}
            className="w-full bg-bg-tertiary border border-border-default rounded-lg px-3 py-2 text-sm font-mono text-text-primary mb-4 focus:outline-none focus:border-accent-blue" />

          <div className="space-y-2 mb-6 text-sm font-mono">
            {[
              { label: "Lock duration", value: selected.label },
              { label: "APY",           value: selected.apy },
              { label: "Energy boost",  value: selected.multiplier },
              { label: "Unlocks at",    value: `~${new Date(Date.now() + selected.days * 86400000).toLocaleDateString()}` },
            ].map(({ label, value }) => (
              <div key={label} className="flex justify-between">
                <span className="text-text-muted">{label}</span>
                <span className="text-text-primary">{value}</span>
              </div>
            ))}
          </div>

          <button disabled={!isConnected || isPending}
            className="w-full py-2.5 rounded-lg bg-accent-blue text-bg-primary font-mono font-semibold text-sm hover:bg-accent-blue/80 disabled:opacity-40 transition-all">
            {isPending ? "Staking..." : `Stake ${amount} AXM for ${selected.label}`}
          </button>
        </div>

        {/* Active positions */}
        <div className="game-card">
          <h2 className="font-mono font-semibold text-text-primary mb-4">Active Positions</h2>
          {positions.length === 0 ? (
            <div className="text-center py-12 text-text-muted font-mono text-sm">
              No active staking positions
            </div>
          ) : (
            <div className="space-y-3">
              {positions.map((pos, i) => (
                <div key={i} className="bg-bg-tertiary rounded-lg p-3 text-sm font-mono">
                  <div className="flex justify-between mb-1">
                    <span className="text-text-secondary">{pos.amount} AXM</span>
                    <span className="text-accent-green">{pos.apy}</span>
                  </div>
                  <div className="flex justify-between text-xs text-text-muted">
                    <span>Unlocks {pos.unlockDate}</span>
                    <button className="text-accent-blue hover:text-accent-blue/80">Claim</button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

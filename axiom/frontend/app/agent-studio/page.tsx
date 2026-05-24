"use client";

import { useState } from "react";
import { useAccount, useWriteContract } from "wagmi";
import { ADDRESSES } from "../../lib/contracts/addresses";
import { CIV_NFT_ABI } from "../../lib/contracts/abis/CivilizationNFT";

const ACTION_NAMES = ["Expand North", "Expand East", "Expand South", "Expand West", "Attack", "Defend", "Harvest", "Idle"];

export default function AgentStudioPage() {
  const { isConnected } = useAccount();
  const { writeContract, isPending } = useWriteContract();

  const [civId, setCivId]         = useState("1");
  const [modelHash, setModelHash] = useState("");
  const [autonomous, setAutonomous] = useState(false);

  // Strategy weights (visual only — actual weights are in the ONNX model)
  const [weights, setWeights] = useState({
    aggression: 50,
    defense: 40,
    harvest: 30,
    expand: 60,
  });

  const deployModel = () => {
    if (!modelHash || !civId) return;
    writeContract({
      address: ADDRESSES.l3.civNFT as `0x${string}`,
      abi: CIV_NFT_ABI,
      functionName: "setAgentModel",
      args: [BigInt(civId), modelHash as `0x${string}`],
    });
  };

  const toggleAutonomous = () => {
    writeContract({
      address: ADDRESSES.l3.civNFT as `0x${string}`,
      abi: CIV_NFT_ABI,
      functionName: "setAutonomous",
      args: [BigInt(civId), !autonomous],
    });
    setAutonomous(v => !v);
  };

  if (!isConnected) {
    return (
      <div className="max-w-2xl mx-auto px-6 py-24 text-center">
        <div className="text-6xl mb-4">🤖</div>
        <p className="text-text-secondary font-mono">Connect wallet to access Agent Studio</p>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto px-6 py-10">
      <div className="mb-8">
        <h1 className="text-2xl font-mono font-bold text-text-primary mb-1">AI Agent Studio</h1>
        <p className="text-text-secondary text-sm">
          Configure your autonomous faction AI. Trained on EZKL — every action is ZK-verified on-chain.
        </p>
      </div>

      <div className="grid md:grid-cols-2 gap-6">

        {/* Left — model deployment */}
        <div className="game-card">
          <h2 className="font-mono font-semibold mb-4 text-text-primary">Deploy Model</h2>

          <label className="block text-xs font-mono text-text-muted mb-1">Civilization ID</label>
          <input value={civId} onChange={e => setCivId(e.target.value)}
            className="w-full bg-bg-tertiary border border-border-default rounded-lg px-3 py-2 text-sm font-mono text-text-primary mb-4 focus:outline-none focus:border-accent-blue" />

          <label className="block text-xs font-mono text-text-muted mb-1">Model Hash (bytes32)</label>
          <input value={modelHash} onChange={e => setModelHash(e.target.value)}
            placeholder="0x..."
            className="w-full bg-bg-tertiary border border-border-default rounded-lg px-3 py-2 text-sm font-mono text-text-primary mb-2 focus:outline-none focus:border-accent-blue" />
          <p className="text-text-muted text-xs mb-4">
            Get this from <code className="text-accent-blue">ezkl_compile.py</code> output
          </p>

          <button onClick={deployModel} disabled={isPending || !modelHash}
            className="w-full py-2.5 rounded-lg bg-accent-blue text-bg-primary font-mono font-semibold text-sm hover:bg-accent-blue/80 disabled:opacity-40 disabled:cursor-not-allowed transition-all">
            {isPending ? "Deploying..." : "Deploy Model On-Chain"}
          </button>

          <div className="mt-4 pt-4 border-t border-border-subtle flex items-center justify-between">
            <div>
              <div className="font-mono text-sm text-text-primary">Autonomous Mode</div>
              <div className="text-text-muted text-xs">Agent plays while you're offline</div>
            </div>
            <button onClick={toggleAutonomous}
              className={`w-12 h-6 rounded-full transition-colors ${autonomous ? "bg-accent-green" : "bg-border-default"}`}>
              <div className={`w-4 h-4 bg-white rounded-full shadow transition-transform mx-1 ${autonomous ? "translate-x-6" : ""}`} />
            </button>
          </div>
        </div>

        {/* Right — strategy preview */}
        <div className="game-card">
          <h2 className="font-mono font-semibold mb-4 text-text-primary">Strategy Preview</h2>
          <p className="text-text-muted text-xs mb-4">Visual representation of model behavior. Actual weights come from trained ONNX model.</p>

          {Object.entries(weights).map(([key, val]) => (
            <div key={key} className="mb-4">
              <div className="flex justify-between mb-1">
                <span className="text-sm font-mono text-text-secondary capitalize">{key}</span>
                <span className="text-sm font-mono text-accent-blue">{val}%</span>
              </div>
              <input type="range" min={0} max={100} value={val}
                onChange={e => setWeights(w => ({ ...w, [key]: +e.target.value }))}
                className="w-full accent-[#58A6FF]" />
            </div>
          ))}

          <div className="mt-4 pt-4 border-t border-border-subtle">
            <div className="text-xs font-mono text-text-muted mb-2">Predicted action distribution</div>
            <div className="grid grid-cols-4 gap-1">
              {ACTION_NAMES.map((name, i) => (
                <div key={i} className="text-center">
                  <div className="bg-accent-blue/20 rounded h-8 flex items-end justify-center">
                    <div className="bg-accent-blue rounded-sm w-3"
                      style={{ height: `${Math.random() * 28 + 4}px` }} />
                  </div>
                  <div className="text-[9px] font-mono text-text-muted mt-1 leading-tight">{name}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Agent activity log */}
      <div className="game-card mt-6">
        <h2 className="font-mono font-semibold mb-4 text-text-primary">Live Agent Actions</h2>
        <div className="space-y-2">
          {[
            { block: "—", action: "Waiting for first autonomous action...", proof: "—" },
          ].map(({ block, action, proof }, i) => (
            <div key={i} className="flex items-center gap-4 py-2 border-b border-border-subtle text-sm font-mono">
              <span className="text-text-muted w-20">#{block}</span>
              <span className="text-text-secondary flex-1">{action}</span>
              <span className="text-accent-green text-xs">{proof}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

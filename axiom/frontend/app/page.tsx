"use client";

import { useAccount } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import Link from "next/link";

export default function HomePage() {
  const { isConnected } = useAccount();

  return (
    <div className="min-h-screen bg-bg-primary bg-hero-gradient">
      {/* Hero */}
      <section className="flex flex-col items-center justify-center text-center px-6 py-32 gap-8">
        <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full border border-accent-blue/30 bg-accent-blue/10 text-accent-blue text-xs font-mono mb-2">
          <span className="w-1.5 h-1.5 rounded-full bg-accent-green animate-pulse" />
          Season 1 — Live on AXIOM L3
        </div>

        <h1 className="text-5xl md:text-7xl font-bold font-mono tracking-tight">
          <span className="text-text-primary">Conquer the</span>
          <br />
          <span className="text-accent-blue" style={{ textShadow: "0 0 40px #58A6FF60" }}>
            Infinite World
          </span>
        </h1>

        <p className="text-text-secondary max-w-xl text-lg leading-relaxed">
          A fully on-chain civilization strategy game. ZK fog-of-war hides your position.
          AI agents play while you sleep. Every move is a cryptographic proof.
        </p>

        <div className="flex gap-4 flex-wrap justify-center">
          {isConnected ? (
            <Link href="/world"
              className="px-6 py-3 rounded-lg bg-accent-blue text-bg-primary font-mono font-semibold hover:bg-accent-blue/80 transition-all">
              Enter World →
            </Link>
          ) : (
            <ConnectButton label="Connect to Play" />
          )}
          <a href="https://docs.axiom.world" target="_blank" rel="noreferrer"
            className="px-6 py-3 rounded-lg border border-border-default text-text-secondary font-mono hover:border-accent-blue hover:text-text-primary transition-all">
            Read Docs
          </a>
        </div>
      </section>

      {/* Stats bar */}
      <section className="max-w-4xl mx-auto px-6 pb-20">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {[
            { label: "Civilizations", value: "—", unit: "active" },
            { label: "Tiles Claimed",  value: "—", unit: "total" },
            { label: "Battles",        value: "—", unit: "this season" },
            { label: "AXM Staked",     value: "—", unit: "tokens" },
          ].map(({ label, value, unit }) => (
            <div key={label} className="game-card text-center">
              <div className="text-2xl font-mono font-bold stat-glow">{value}</div>
              <div className="text-text-secondary text-xs mt-1">{label}</div>
              <div className="text-text-muted text-xs">{unit}</div>
            </div>
          ))}
        </div>
      </section>

      {/* Features */}
      <section className="max-w-5xl mx-auto px-6 pb-32">
        <div className="grid md:grid-cols-3 gap-6">
          {[
            {
              icon: "🔐",
              title: "ZK Fog of War",
              desc: "Your position is a Poseidon2 commitment. Noir circuits prove movement without revealing coordinates.",
              tag: "Noir + Barretenberg",
            },
            {
              icon: "🤖",
              title: "Autonomous AI Agents",
              desc: "Train a faction strategy model. Deploy it as your ERC-6551 agent. Your civ plays 24/7 — EZKL verifies every move.",
              tag: "EZKL + ERC-6551",
            },
            {
              icon: "⚡",
              title: "EigenLayer Compute",
              desc: "Heavy pathfinding and AI inference run off-chain on AVS operators, slashed for wrong answers.",
              tag: "EigenLayer AVS",
            },
          ].map(({ icon, title, desc, tag }) => (
            <div key={title} className="game-card hover:border-accent-blue/40 transition-colors">
              <div className="text-3xl mb-3">{icon}</div>
              <div className="font-mono font-semibold text-text-primary mb-2">{title}</div>
              <p className="text-text-secondary text-sm leading-relaxed mb-4">{desc}</p>
              <span className="text-xs font-mono text-accent-blue/80 bg-accent-blue/10 px-2 py-0.5 rounded">
                {tag}
              </span>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}

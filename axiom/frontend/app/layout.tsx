"use client";

import "@rainbow-me/rainbowkit/styles.css";
import "./globals.css";

import { ReactNode } from "react";
import { WagmiProvider, createConfig, http } from "wagmi";
import { arbitrum, mainnet } from "wagmi/chains";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { RainbowKitProvider, darkTheme, getDefaultConfig } from "@rainbow-me/rainbowkit";
import { Toaster } from "sonner";

// ── AXIOM L3 custom chain definition ─────────────────────────
const axiomL3 = {
  id: 42069,
  name: "AXIOM World",
  nativeCurrency: { name: "AXIOM Token", symbol: "AXM", decimals: 18 },
  rpcUrls: {
    default: { http: [process.env.NEXT_PUBLIC_L3_RPC_URL ?? "http://localhost:8545"] },
  },
  blockExplorers: {
    default: { name: "AXIOM Explorer", url: "https://explorer.axiom.world" },
  },
} as const;

// ── Wagmi config ──────────────────────────────────────────────
const wagmiConfig = getDefaultConfig({
  appName: "AXIOM — Autonomous Civilization Game",
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_ID ?? "axiom-dev",
  chains: [axiomL3, arbitrum, mainnet],
  transports: {
    [axiomL3.id]: http(process.env.NEXT_PUBLIC_L3_RPC_URL ?? "http://localhost:8545"),
    [arbitrum.id]: http(process.env.NEXT_PUBLIC_L2_RPC_URL),
    [mainnet.id]:  http(process.env.NEXT_PUBLIC_MAINNET_RPC_URL),
  },
  ssr: true,
});

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 1000 * 60, refetchOnWindowFocus: false },
  },
});

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className="dark">
      <head>
        <title>AXIOM — Autonomous Civilization Game</title>
        <meta name="description" content="Fully on-chain autonomous civilization strategy game with ZK fog-of-war and AI agents" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <link rel="icon" href="/favicon.ico" />
        <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&family=Inter:wght@400;500;600&display=swap" rel="stylesheet" />
      </head>
      <body className="bg-bg-primary text-text-primary font-sans antialiased min-h-screen">
        <WagmiProvider config={wagmiConfig}>
          <QueryClientProvider client={queryClient}>
            <RainbowKitProvider
              theme={darkTheme({
                accentColor: "#58A6FF",
                accentColorForeground: "#0D1117",
                borderRadius: "medium",
                fontStack: "system",
              })}
            >
              {/* Global nav */}
              <nav className="fixed top-0 left-0 right-0 z-50 flex items-center justify-between px-6 py-3 bg-bg-secondary/80 backdrop-blur border-b border-border-subtle">
                <div className="flex items-center gap-3">
                  <span className="text-accent-blue font-mono font-bold text-lg tracking-wider">AXIOM</span>
                  <span className="text-text-muted text-xs font-mono">v0.1.0 — Season 1</span>
                </div>
                <div className="flex items-center gap-6">
                  {[
                    { href: "/world",        label: "World" },
                    { href: "/civilization", label: "Civilization" },
                    { href: "/agent-studio", label: "AI Agent" },
                    { href: "/markets",      label: "Markets" },
                    { href: "/staking",      label: "Staking" },
                  ].map(({ href, label }) => (
                    <a key={href} href={href}
                      className="text-text-secondary hover:text-text-primary text-sm font-mono transition-colors">
                      {label}
                    </a>
                  ))}
                </div>
                <ConnectButtonWrapper />
              </nav>

              {/* Page content — padded for fixed nav */}
              <main className="pt-14">{children}</main>

              <Toaster
                theme="dark"
                toastOptions={{ style: { background: "#161B22", border: "1px solid #30363D", color: "#E6EDF3" } }}
              />
            </RainbowKitProvider>
          </QueryClientProvider>
        </WagmiProvider>
      </body>
    </html>
  );
}

// Lazy import to avoid SSR issues
function ConnectButtonWrapper() {
  const { ConnectButton } = require("@rainbow-me/rainbowkit");
  return <ConnectButton accountStatus="avatar" chainStatus="icon" showBalance={false} />;
}

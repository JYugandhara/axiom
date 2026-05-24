import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,

  // Required for Noir WASM proof generation in browser
  webpack: (config, { isServer }) => {
    if (!isServer) {
      config.experiments = { ...config.experiments, asyncWebAssembly: true };
      config.output.webassemblyModuleFilename = "static/wasm/[modulehash].wasm";
    }
    // Fix for wagmi / viem ESM modules
    config.resolve.fallback = {
      ...config.resolve.fallback,
      fs: false,
      net: false,
      tls: false,
    };
    return config;
  },

  // Allow IPFS and Arweave image sources for NFT metadata
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "ipfs.io" },
      { protocol: "https", hostname: "arweave.net" },
      { protocol: "https", hostname: "gateway.pinata.cloud" },
    ],
  },

  // Required for MUD store-sync WebSocket
  experimental: {
    serverComponentsExternalPackages: ["@latticexyz/store-sync"],
  },

  // Transpile packages that don't ship CJS
  transpilePackages: [
    "@rainbow-me/rainbowkit",
    "@latticexyz/store-sync",
    "@latticexyz/world",
  ],
};

export default nextConfig;
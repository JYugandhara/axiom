"use client";

import { useAccount } from "wagmi";
import { useReadContract, useReadContracts } from "wagmi";
import { ADDRESSES } from "../../lib/contracts/addresses";
import { CIV_NFT_ABI } from "../../lib/contracts/abis/CivilizationNFT";
import CivCard from "../../components/civilization/CivCard";
import Link from "next/link";

export default function CivilizationPage() {
  const { address, isConnected } = useAccount();

  // Fetch token IDs owned by this wallet
  const { data: balance } = useReadContract({
    address: ADDRESSES.l3.civNFT as `0x${string}`,
    abi: CIV_NFT_ABI,
    functionName: "balanceOf",
    args: [address!],
    query: { enabled: !!address },
  });

  if (!isConnected) {
    return (
      <div className="max-w-2xl mx-auto px-6 py-24 text-center">
        <div className="text-6xl mb-6">🏛️</div>
        <h1 className="text-2xl font-mono font-bold text-text-primary mb-3">No Civilization Yet</h1>
        <p className="text-text-secondary mb-8">Connect your wallet to view or mint your civilization.</p>
      </div>
    );
  }

  if (balance === BigInt(0)) {
    return (
      <div className="max-w-2xl mx-auto px-6 py-24 text-center">
        <div className="text-6xl mb-6">🏛️</div>
        <h1 className="text-2xl font-mono font-bold mb-3">Mint Your Civilization</h1>
        <p className="text-text-secondary mb-8">
          Join the world. Mint a civilization NFT to start claiming territory.
          Costs 100 $AXM.
        </p>
        <MintButton />
      </div>
    );
  }

  return (
    <div className="max-w-5xl mx-auto px-6 py-10">
      <div className="flex items-center justify-between mb-8">
        <h1 className="text-2xl font-mono font-bold text-text-primary">My Civilizations</h1>
        <MintButton />
      </div>

      {/* Civ cards grid */}
      <div className="grid md:grid-cols-2 gap-6">
        {Array.from({ length: Number(balance ?? 0) }).map((_, i) => (
          <CivCardLoader key={i} owner={address!} index={i} />
        ))}
      </div>
    </div>
  );
}

function CivCardLoader({ owner, index }: { owner: string; index: number }) {
  const { data: tokenId } = useReadContract({
    address: ADDRESSES.l3.civNFT as `0x${string}`,
    abi: CIV_NFT_ABI,
    functionName: "tokenOfOwnerByIndex",
    args: [owner as `0x${string}`, BigInt(index)],
  });

  if (!tokenId) return <div className="game-card animate-pulse h-48" />;
  return <CivCard civId={tokenId} />;
}

function MintButton() {
  return (
    <button className="px-5 py-2.5 rounded-lg bg-accent-blue text-bg-primary font-mono font-semibold text-sm hover:bg-accent-blue/80 transition-all">
      + Mint Civilization
    </button>
  );
}

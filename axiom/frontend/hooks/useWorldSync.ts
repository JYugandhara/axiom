"use client";

import { useEffect, useState, useRef } from "react";
import { usePublicClient } from "wagmi";
import { ADDRESSES } from "../lib/contracts/addresses";

export interface TileState {
  commitment : string;
  owner      : number;    // civId (0 = unclaimed)
  claimedAt  : bigint;
}

export interface WorldState {
  tiles      : Map<string, TileState>;   // commitment → TileState
  civCounts  : Map<number, number>;      // civId → tile count
  isReady    : boolean;
  blockNumber: bigint;
}

// ─────────────────────────────────────────────────────────────
//  useWorldSync
//  Syncs TerritoryMap on-chain state to the client.
//  Uses event log polling + WebSocket subscription.
//  In production: replace with @latticexyz/store-sync for
//  full MUD ECS table replication.
// ─────────────────────────────────────────────────────────────

export function useWorldSync() {
  const client = usePublicClient();
  const [world,  setWorld]  = useState<WorldState>({
    tiles     : new Map(),
    civCounts : new Map(),
    isReady   : false,
    blockNumber: 0n,
  });
  const [error, setError]   = useState<string | null>(null);
  const syncedBlock = useRef<bigint>(0n);

  useEffect(() => {
    if (!client || !ADDRESSES.l3.territoryMap) return;

    let unwatch: (() => void) | null = null;

    const init = async () => {
      try {
        // ── Step 1: Snapshot all TileClaimed events from genesis ──
        const claimLogs = await client.getLogs({
          address  : ADDRESSES.l3.territoryMap as `0x${string}`,
          event    : {
            type   : "event",
            name   : "TileClaimed",
            inputs : [
              { type: "bytes32",  name: "commitment", indexed: true },
              { type: "uint256",  name: "civId",      indexed: true },
            ],
          },
          fromBlock: "earliest",
          toBlock  : "latest",
        });

        const tileLost = await client.getLogs({
          address  : ADDRESSES.l3.territoryMap as `0x${string}`,
          event    : {
            type   : "event",
            name   : "TileLost",
            inputs : [
              { type: "bytes32",  name: "commitment", indexed: true },
              { type: "uint256",  name: "fromCiv",    indexed: true },
              { type: "uint256",  name: "toCiv",      indexed: true },
            ],
          },
          fromBlock: "earliest",
          toBlock  : "latest",
        });

        const block   = await client.getBlockNumber();
        const tiles   = new Map<string, TileState>();
        const counts  = new Map<number, number>();

        // Apply claims
        for (const log of claimLogs) {
          const commitment = (log as any).args.commitment as string;
          const civId      = Number((log as any).args.civId ?? 0n);
          tiles.set(commitment, { commitment, owner: civId, claimedAt: log.blockNumber ?? 0n });
          counts.set(civId, (counts.get(civId) ?? 0) + 1);
        }

        // Apply transfers (battles)
        for (const log of tileLost) {
          const commitment = (log as any).args.commitment as string;
          const fromCiv    = Number((log as any).args.fromCiv ?? 0n);
          const toCiv      = Number((log as any).args.toCiv   ?? 0n);
          const existing   = tiles.get(commitment);
          if (existing) {
            tiles.set(commitment, { ...existing, owner: toCiv });
            counts.set(fromCiv, Math.max(0, (counts.get(fromCiv) ?? 1) - 1));
            counts.set(toCiv,   (counts.get(toCiv) ?? 0) + 1);
          }
        }

        syncedBlock.current = block;
        setWorld({ tiles, civCounts: counts, isReady: true, blockNumber: block });

        // ── Step 2: Watch for new events ──────────────────────────
        unwatch = client.watchContractEvent({
          address  : ADDRESSES.l3.territoryMap as `0x${string}`,
          abi      : [
            { type:"event", name:"TileClaimed", inputs:[
              { type:"bytes32", name:"commitment", indexed:true },
              { type:"uint256", name:"civId",      indexed:true },
            ]},
            { type:"event", name:"TileLost", inputs:[
              { type:"bytes32", name:"commitment", indexed:true },
              { type:"uint256", name:"fromCiv",    indexed:true },
              { type:"uint256", name:"toCiv",      indexed:true },
            ]},
          ],
          eventName: "TileClaimed",
          onLogs(logs) {
            setWorld(prev => {
              const next      = new Map(prev.tiles);
              const nextCounts = new Map(prev.civCounts);
              for (const log of logs) {
                const commitment = (log as any).args.commitment as string;
                const civId      = Number((log as any).args.civId ?? 0n);
                next.set(commitment, { commitment, owner: civId, claimedAt: (log as any).blockNumber ?? 0n });
                nextCounts.set(civId, (nextCounts.get(civId) ?? 0) + 1);
              }
              return { ...prev, tiles: next, civCounts: nextCounts };
            });
          },
        });
      } catch (e: any) {
        setError(e.message);
      }
    };

    init();
    return () => { unwatch?.(); };
  }, [client]);

  return { world, error };
}

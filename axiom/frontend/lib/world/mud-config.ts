// ─────────────────────────────────────────────────────────────
//  MUD v2 Client Config
//  Configures @latticexyz/store-sync to replicate on-chain
//  ECS table state to the browser for real-time world rendering.
// ─────────────────────────────────────────────────────────────

import { ADDRESSES } from "../contracts/addresses";

export const MUD_CONFIG = {
  // L3 chain WebSocket RPC for store-sync
  rpcUrl      : process.env.NEXT_PUBLIC_L3_RPC_URL ?? "ws://localhost:8546",
  worldAddress: (ADDRESSES.l3.world ?? "0x0") as `0x${string}`,
  chainId     : 42069,

  // Start syncing from this block (set to world deploy block)
  startBlock  : BigInt(process.env.NEXT_PUBLIC_WORLD_START_BLOCK ?? "0"),

  // Tables to sync — matches contracts/src/mud/tables/
  tables: {
    CivilizationState: {
      tableId: "0x" + Buffer.from("axiom.CivilizationState").toString("hex").padStart(64, "0"),
      schema : {
        civId         : "uint256",
        territory     : "uint256",
        energyBalance : "uint256",
        energyPerBlock: "uint256",
        agentModelHash: "bytes32",
        isAutonomous  : "bool",
        moveNonce     : "uint64",
        claimNonce    : "uint64",
        attackPower   : "uint32",
        defensePower  : "uint32",
        season        : "uint32",
        owner         : "address",
      },
    },

    TerritoryMap: {
      tableId: "0x" + Buffer.from("axiom.TerritoryMap").toString("hex").padStart(64, "0"),
      schema : {
        commitment : "bytes32",
        civId      : "uint256",
      },
    },

    AgentActions: {
      tableId: "0x" + Buffer.from("axiom.AgentActions").toString("hex").padStart(64, "0"),
      schema : {
        taskId      : "uint256",
        civId       : "uint256",
        actionType  : "uint8",
        executed    : "bool",
        submittedAt : "uint64",
      },
    },

    BattleHistory: {
      tableId: "0x" + Buffer.from("axiom.BattleHistory").toString("hex").padStart(64, "0"),
      schema : {
        battleId            : "uint256",
        attackerId          : "uint256",
        defenderId          : "uint256",
        attackerWon         : "bool",
        territoryTransferred: "uint32",
        damageDealt         : "uint32",
        blockNumber         : "uint256",
      },
    },

    GameConfig: {
      tableId: "0x" + Buffer.from("axiom.GameConfig").toString("hex").padStart(64, "0"),
      schema : {
        currentSeason       : "uint32",
        seasonLengthBlocks  : "uint32",
        baseMovementRange   : "uint32",
        entryFeeAxm         : "uint32",
        energyPerBlockPerTile: "uint256",
        paused              : "bool",
      },
    },
  },
} as const;

// ─────────────────────────────────────────────────────────────
//  Store-sync setup (call once in layout.tsx or a provider)
// ─────────────────────────────────────────────────────────────

export async function setupMudSync() {
  // Dynamic import to avoid SSR
  const { syncToZustand } = await import("@latticexyz/store-sync/zustand");

  const { tables, useStore, latestBlock$, storedBlockLogs$ } = await syncToZustand({
    config       : MUD_CONFIG,
    address      : MUD_CONFIG.worldAddress,
    publicClient : undefined as any, // inject viem publicClient
    startBlock   : MUD_CONFIG.startBlock,
  });

  return { tables, useStore, latestBlock$, storedBlockLogs$ };
}

// ─────────────────────────────────────────────────────────────
//  Helper: tile commitment lookup key
// ─────────────────────────────────────────────────────────────

export function tileKey(x: number, y: number): string {
  // Matches the encoding used in Prover.toml: coord + 1_000_000
  const fx = (x + 1_000_000).toString();
  const fy = (y + 1_000_000).toString();
  return `${fx},${fy}`;
}

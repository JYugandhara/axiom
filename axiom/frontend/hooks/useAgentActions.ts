"use client";

import { useEffect, useState, useCallback } from "react";
import { usePublicClient } from "wagmi";
import { ADDRESSES } from "../lib/contracts/addresses";

const ACTION_NAMES = [
  "expand_north", "expand_east", "expand_south", "expand_west",
  "attack", "defend", "harvest", "idle",
];

export interface AgentAction {
  taskId      : string;
  civId       : string;
  action      : number;
  actionName  : string;
  blockNumber : bigint;
  txHash      : string;
  timestamp   : number;
}

// ─────────────────────────────────────────────────────────────
//  useAgentActions
//  Watches AgentActionExecuted events from AgentSystem.sol.
//  Shows real-time autonomous moves for a civilization.
// ─────────────────────────────────────────────────────────────

export function useAgentActions(civId?: bigint) {
  const client = usePublicClient();
  const [actions, setActions]   = useState<AgentAction[]>([]);
  const [loading, setLoading]   = useState(true);
  const [error,   setError]     = useState<string | null>(null);

  // ── Load recent history ─────────────────────────────────────
  const loadHistory = useCallback(async () => {
    if (!client || !ADDRESSES.l3.agentSystem) return;
    setLoading(true);
    try {
      const logs = await client.getLogs({
        address  : ADDRESSES.l3.agentSystem as `0x${string}`,
        event    : {
          type   : "event",
          name   : "AgentActionExecuted",
          inputs : [
            { type: "uint256", name: "taskId",  indexed: true },
            { type: "uint256", name: "civId",   indexed: true },
            { type: "uint8",   name: "action",  indexed: false },
          ],
        },
        args     : civId ? { civId } : undefined,
        fromBlock: "earliest",
        toBlock  : "latest",
      });

      const parsed: AgentAction[] = logs.map(log => {
        const action = Number((log as any).args.action ?? 7);
        return {
          taskId    : ((log as any).args.taskId ?? 0n).toString(),
          civId     : ((log as any).args.civId  ?? 0n).toString(),
          action,
          actionName: ACTION_NAMES[action] ?? "idle",
          blockNumber: log.blockNumber ?? 0n,
          txHash    : log.transactionHash ?? "",
          timestamp : Date.now(),
        };
      });

      setActions(parsed.reverse()); // newest first
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [client, civId]);

  useEffect(() => { loadHistory(); }, [loadHistory]);

  // ── Subscribe to new events ─────────────────────────────────
  useEffect(() => {
    if (!client || !ADDRESSES.l3.agentSystem) return;

    const unwatch = client.watchContractEvent({
      address : ADDRESSES.l3.agentSystem as `0x${string}`,
      abi     : [{
        type   : "event",
        name   : "AgentActionExecuted",
        inputs : [
          { type: "uint256", name: "taskId", indexed: true },
          { type: "uint256", name: "civId",  indexed: true },
          { type: "uint8",   name: "action", indexed: false },
        ],
      }],
      eventName: "AgentActionExecuted",
      args     : civId ? { civId } : undefined,
      onLogs(logs) {
        const newActions: AgentAction[] = logs.map(log => {
          const action = Number((log as any).args.action ?? 7);
          return {
            taskId    : ((log as any).args.taskId ?? 0n).toString(),
            civId     : ((log as any).args.civId  ?? 0n).toString(),
            action,
            actionName: ACTION_NAMES[action] ?? "idle",
            blockNumber: (log as any).blockNumber ?? 0n,
            txHash    : (log as any).transactionHash ?? "",
            timestamp : Date.now(),
          };
        });
        setActions(prev => [...newActions, ...prev].slice(0, 50));
      },
    });

    return () => { unwatch(); };
  }, [client, civId]);

  return { actions, loading, error, reload: loadHistory };
}

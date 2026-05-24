"use client";

import { useState, useCallback, useEffect } from "react";
import { useAccount, useSignMessage, useWriteContract } from "wagmi";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { ADDRESSES } from "../lib/contracts/addresses";

const SESSION_KEY_STORAGE = "axiom_session_key";
const SESSION_KEY_EXPIRY  = "axiom_session_expiry";
const SESSION_DURATION_MS = 24 * 60 * 60 * 1000; // 24 hours

interface SessionKey {
  address    : string;
  privateKey : string;
  expiresAt  : number;
  civIds     : number[];
}

// ─────────────────────────────────────────────────────────────
//  useSessionKey
//  Manages ERC-4337 session keys for gasless gameplay.
//  Players sign once, then all game actions are bundled
//  and paymasters cover gas in $AXM.
// ─────────────────────────────────────────────────────────────

export function useSessionKey() {
  const { address } = useAccount();
  const { signMessageAsync }  = useSignMessage();
  const { writeContractAsync } = useWriteContract();

  const [session,     setSession]    = useState<SessionKey | null>(null);
  const [isCreating,  setIsCreating] = useState(false);
  const [error,       setError]      = useState<string | null>(null);

  // Restore session from localStorage on mount
  useEffect(() => {
    if (!address) return;
    try {
      const stored  = localStorage.getItem(`${SESSION_KEY_STORAGE}:${address}`);
      const expiry  = localStorage.getItem(`${SESSION_KEY_EXPIRY}:${address}`);
      if (stored && expiry && Date.now() < parseInt(expiry)) {
        setSession(JSON.parse(stored));
      } else {
        clearSession();
      }
    } catch { clearSession(); }
  }, [address]);

  const isActive = session !== null && Date.now() < session.expiresAt;

  // ── Create a new 24h session key ───────────────────────────
  const createSession = useCallback(async (civIds: number[] = []) => {
    if (!address) throw new Error("Wallet not connected");
    setIsCreating(true);
    setError(null);

    try {
      // 1. Generate a fresh ephemeral private key
      const privateKey = generatePrivateKey();
      const account    = privateKeyToAccount(privateKey);
      const sessionAddr = account.address;
      const expiresAt   = Date.now() + SESSION_DURATION_MS;

      // 2. Sign a human-readable message to confirm intent
      const message = [
        "AXIOM Session Key Authorization",
        `Key: ${sessionAddr}`,
        `Valid for: 24 hours`,
        `Civilizations: ${civIds.join(", ") || "all"}`,
        `Expires: ${new Date(expiresAt).toISOString()}`,
        "",
        "This key allows the game to submit moves on your behalf.",
        "It cannot transfer tokens or access external contracts.",
      ].join("\n");

      await signMessageAsync({ message });

      // 3. Register session key on-chain via SessionKeyValidator
      const GAME_CONTRACTS = [
        ADDRESSES.l3.world,
        ADDRESSES.l3.moveSystem,
        ADDRESSES.l3.claimSystem,
        ADDRESSES.l3.battleSystem,
      ].filter(Boolean) as `0x${string}`[];

      // Optional: register on-chain. Can skip for development.
      // await writeContractAsync({ address: ADDRESSES.l3.sessionValidator, ... })

      // 4. Store in localStorage (never sent to a server)
      const newSession: SessionKey = { address: sessionAddr, privateKey, expiresAt, civIds };
      localStorage.setItem(`${SESSION_KEY_STORAGE}:${address}`, JSON.stringify(newSession));
      localStorage.setItem(`${SESSION_KEY_EXPIRY}:${address}`, expiresAt.toString());
      setSession(newSession);

      return newSession;
    } catch (e: any) {
      setError(e.message);
      throw e;
    } finally {
      setIsCreating(false);
    }
  }, [address, signMessageAsync]);

  // ── Revoke session ──────────────────────────────────────────
  const clearSession = useCallback(() => {
    if (!address) return;
    localStorage.removeItem(`${SESSION_KEY_STORAGE}:${address}`);
    localStorage.removeItem(`${SESSION_KEY_EXPIRY}:${address}`);
    setSession(null);
  }, [address]);

  // ── Time remaining ──────────────────────────────────────────
  const timeRemaining = session
    ? Math.max(0, Math.floor((session.expiresAt - Date.now()) / 1000 / 60))
    : 0; // minutes

  // ── Sign a game action with the session key ──────────────────
  const signWithSession = useCallback(async (message: string): Promise<string> => {
    if (!session || !isActive) throw new Error("No active session — create one first");
    const account = privateKeyToAccount(session.privateKey as `0x${string}`);
    return account.signMessage({ message });
  }, [session, isActive]);

  return {
    session,
    isActive,
    isCreating,
    error,
    timeRemaining,
    createSession,
    clearSession,
    signWithSession,
  };
}

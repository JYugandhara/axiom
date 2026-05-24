"use client";

import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useState } from "react";
import { ADDRESSES } from "../lib/contracts/addresses";
import { parseUnits } from "viem";

const PREDICTION_MARKET_ABI = [
  { type:"function", name:"bet",  inputs:[{type:"uint256",name:"marketId"},{type:"bool",name:"isYes"},{type:"uint256",name:"axmIn"}], outputs:[], stateMutability:"nonpayable" },
  { type:"function", name:"claim",inputs:[{type:"uint256",name:"betIdx"}], outputs:[], stateMutability:"nonpayable" },
  { type:"function", name:"impliedProbabilityYes", inputs:[{type:"uint256",name:"marketId"}], outputs:[{type:"uint256"}], stateMutability:"view" },
  { type:"function", name:"markets", inputs:[{type:"uint256",name:""}], outputs:[{type:"uint256",name:"season"},{type:"uint256",name:"civId"},{type:"uint256",name:"yesPool"},{type:"uint256",name:"noPool"},{type:"bool",name:"resolved"},{type:"bool",name:"outcome"},{type:"uint256",name:"closesAtBlock"}], stateMutability:"view" },
  { type:"function", name:"userBets", inputs:[{type:"address",name:""},{type:"uint256",name:""}], outputs:[{type:"uint256",name:"marketId"},{type:"bool",name:"isYes"},{type:"uint256",name:"shares"},{type:"uint256",name:"axmIn"},{type:"bool",name:"claimed"}], stateMutability:"view" },
] as const;

// ─────────────────────────────────────────────────────────────
//  usePredictionMarket
// ─────────────────────────────────────────────────────────────

export function usePredictionMarket(marketId?: bigint) {
  const [betAmount, setBetAmount] = useState("10");

  const { data: market } = useReadContract({
    address  : ADDRESSES.l3.predictionMarket as `0x${string}`,
    abi      : PREDICTION_MARKET_ABI,
    functionName: "markets",
    args     : [marketId ?? 1n],
    query    : { enabled: !!marketId, refetchInterval: 5000 },
  });

  const { data: yesOdds } = useReadContract({
    address  : ADDRESSES.l3.predictionMarket as `0x${string}`,
    abi      : PREDICTION_MARKET_ABI,
    functionName: "impliedProbabilityYes",
    args     : [marketId ?? 1n],
    query    : { enabled: !!marketId, refetchInterval: 5000 },
  });

  const { writeContract, data: txHash, isPending } = useWriteContract();

  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: txHash });

  const placeBet = (isYes: boolean) => {
    if (!marketId) return;
    writeContract({
      address  : ADDRESSES.l3.predictionMarket as `0x${string}`,
      abi      : PREDICTION_MARKET_ABI,
      functionName: "bet",
      args     : [marketId, isYes, parseUnits(betAmount, 18)],
    });
  };

  const claimWinnings = (betIdx: bigint) => {
    writeContract({
      address  : ADDRESSES.l3.predictionMarket as `0x${string}`,
      abi      : PREDICTION_MARKET_ABI,
      functionName: "claim",
      args     : [betIdx],
    });
  };

  const yesPercent  = yesOdds ? Number(yesOdds) / 100 : 50;
  const noPercent   = 100 - yesPercent;

  return {
    market,
    yesPercent,
    noPercent,
    betAmount,
    setBetAmount,
    placeBet,
    claimWinnings,
    isPending,
    isConfirming,
    txHash,
  };
}

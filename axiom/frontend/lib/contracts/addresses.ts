// ─────────────────────────────────────────────────────────────
//  AXIOM Contract Addresses
//  Auto-updated by forge deployment scripts.
//  Manually update after each deploy.
// ─────────────────────────────────────────────────────────────

type ChainAddresses = {
  [key: string]: string | undefined;
};

export const ADDRESSES: {
  l3      : ChainAddresses;
  l2      : ChainAddresses;
  mainnet : ChainAddresses;
} = {
  // ── AXIOM L3 (chain ID: 42069) ───────────────────────────────
  l3: {
    world           : process.env.NEXT_PUBLIC_WORLD_ADDRESS,
    moveSystem      : process.env.NEXT_PUBLIC_MOVE_SYSTEM,
    claimSystem     : process.env.NEXT_PUBLIC_CLAIM_SYSTEM,
    battleSystem    : process.env.NEXT_PUBLIC_BATTLE_SYSTEM,
    agentSystem     : process.env.NEXT_PUBLIC_AGENT_SYSTEM,
    energySystem    : process.env.NEXT_PUBLIC_ENERGY_SYSTEM,
    civState        : process.env.NEXT_PUBLIC_CIV_STATE,
    territoryMap    : process.env.NEXT_PUBLIC_TERRITORY_MAP,
    agentActions    : process.env.NEXT_PUBLIC_AGENT_ACTIONS,
    battleHistory   : process.env.NEXT_PUBLIC_BATTLE_HISTORY,
    gameConfig      : process.env.NEXT_PUBLIC_GAME_CONFIG,
    civNFT          : process.env.NEXT_PUBLIC_CIV_NFT,
    erc6551Registry : process.env.NEXT_PUBLIC_ERC6551_REGISTRY,
    energyToken     : process.env.NEXT_PUBLIC_ENERGY_TOKEN,
    sessionValidator: process.env.NEXT_PUBLIC_SESSION_VALIDATOR,
    paymaster       : process.env.NEXT_PUBLIC_PAYMASTER,
    predictionMarket: process.env.NEXT_PUBLIC_PREDICTION_MARKET,
  },

  // ── Arbitrum One (chain ID: 42161) ───────────────────────────
  l2: {
    taskManager    : process.env.NEXT_PUBLIC_TASK_MANAGER,
    serviceManager : process.env.NEXT_PUBLIC_SERVICE_MANAGER,
    operatorRegistry: process.env.NEXT_PUBLIC_OPERATOR_REGISTRY,
    axmToken       : process.env.NEXT_PUBLIC_AXM_TOKEN_L2,
    staking        : process.env.NEXT_PUBLIC_STAKING,
    marketplace    : process.env.NEXT_PUBLIC_MARKETPLACE,
    bridge         : process.env.NEXT_PUBLIC_BRIDGE_L2,
  },

  // ── Ethereum Mainnet (chain ID: 1) ───────────────────────────
  mainnet: {
    axmToken : process.env.NEXT_PUBLIC_AXM_TOKEN_MAINNET,
    treasury : process.env.NEXT_PUBLIC_TREASURY,
    bridge   : process.env.NEXT_PUBLIC_BRIDGE_MAINNET,
  },
};

// ── Development fallbacks (Anvil local node) ─────────────────
if (process.env.NODE_ENV === "development") {
  Object.assign(ADDRESSES.l3, {
    world        : ADDRESSES.l3.world        ?? "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    civNFT       : ADDRESSES.l3.civNFT       ?? "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
    territoryMap : ADDRESSES.l3.territoryMap ?? "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
    energyToken  : ADDRESSES.l3.energyToken  ?? "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9",
  });
}

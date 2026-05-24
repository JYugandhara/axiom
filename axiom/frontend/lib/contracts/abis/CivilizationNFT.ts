// Auto-generated from forge build — do not edit manually
// Run: forge build && cp out/CivilizationNFT.sol/CivilizationNFT.json ../frontend/lib/contracts/abis/

export const CIV_NFT_ABI = [
  // ── View functions ──────────────────────────────────────────
  {
    type: "function",
    name: "balanceOf",
    inputs: [{ type: "address", name: "owner" }],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "ownerOf",
    inputs: [{ type: "uint256", name: "tokenId" }],
    outputs: [{ type: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "tokenOfOwnerByIndex",
    inputs: [{ type: "address", name: "owner" }, { type: "uint256", name: "index" }],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "metadata",
    inputs: [{ type: "uint256", name: "tokenId" }],
    outputs: [
      { type: "string",  name: "name" },
      { type: "bytes32", name: "agentModelHash" },
      { type: "bool",    name: "isAutonomous" },
      { type: "uint256", name: "mintedAtBlock" },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "agentAccountOf",
    inputs: [{ type: "uint256", name: "tokenId" }],
    outputs: [{ type: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "mintFee",
    inputs: [],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },

  // ── Write functions ─────────────────────────────────────────
  {
    type: "function",
    name: "mint",
    inputs: [{ type: "string", name: "civName" }],
    outputs: [{ type: "uint256", name: "tokenId" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setAgentModel",
    inputs: [
      { type: "uint256", name: "tokenId" },
      { type: "bytes32", name: "modelHash" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setAutonomous",
    inputs: [
      { type: "uint256", name: "tokenId" },
      { type: "bool",    name: "autonomous" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },

  // ── Events ─────────────────────────────────────────────────
  {
    type: "event",
    name: "CivilizationMinted",
    inputs: [
      { type: "uint256", name: "tokenId", indexed: true },
      { type: "address", name: "owner",   indexed: true },
      { type: "address", name: "tba",     indexed: false },
    ],
  },
  {
    type: "event",
    name: "AgentModelSet",
    inputs: [
      { type: "uint256", name: "tokenId",   indexed: true },
      { type: "bytes32", name: "modelHash", indexed: false },
    ],
  },
  {
    type: "event",
    name: "AutonomyToggled",
    inputs: [
      { type: "uint256", name: "tokenId",   indexed: true },
      { type: "bool",    name: "autonomous",indexed: false },
    ],
  },
] as const;

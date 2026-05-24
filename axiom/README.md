# AXIOM — Fully On-Chain Autonomous Civilization Game

> A dark-forest-inspired strategy game where every move is a ZK proof,
> every agent is an on-chain AI, and every battle is verified by EigenLayer.

---

## What Makes This Different

| Feature | Implementation |
|---|---|
| **ZK Fog of War** | Noir circuits — coordinates stay private, movement is provable |
| **On-Chain AI Agents** | EZKL compiles PyTorch → ZK circuit — every AI action is verifiable |
| **EigenLayer AVS** | Operators run pathfinding + AI inference with slashing for dishonesty |
| **Sovereign L3** | Custom OP Stack chain — gas paid in `$AXM`, 500ms block time |
| **MUD v2 World** | Entire game state lives on-chain as composable ECS tables |
| **ERC-6551 TBA** | Civilization NFTs own their own agent accounts |
| **Cross-chain** | LayerZero v2 bridges `$AXM` between mainnet, Arbitrum, L3 |

---

## Architecture

```
Player Wallet (ERC-4337 session keys)
        ↓
  AXIOM L3 (OP Stack, chain ID 42069)
  ├── MUD v2 World (on-chain ECS)
  │   ├── MoveSystem     ← verifies fog-of-war Noir proof
  │   ├── ClaimSystem    ← verifies territory Noir proof
  │   ├── BattleSystem   ← dispatches to EigenLayer AVS
  │   ├── AgentSystem    ← verifies EZKL AI proof
  │   └── EnergySystem   ← Chainlink Automation minting
  ├── ZK Verifiers
  │   ├── FogVerifier.sol       (nargo codegen-verifier)
  │   ├── TerritoryVerifier.sol (nargo codegen-verifier)
  │   └── AIVerifier.sol        (ezkl create-evm-verifier)
  └── Economy
      ├── $ENERGY Token (in-game resource)
      └── Prediction Market (bet on season outcomes)

EigenLayer AVS (Arbitrum One)
  └── avs-operator (Rust)
      ├── A* pathfinding
      ├── ONNX AI inference
      └── EZKL proof generation

Ethereum Mainnet
  ├── $AXM Token (governance, capped 1B)
  ├── Staking (lock AXM → energy boost)
  └── LayerZero Bridge

The Graph (event indexing)
  └── Leaderboard, battle history, prediction bets
```

---

## Project Structure

```
axiom/
├── .vscode/           VS Code workspace config (settings, launch, tasks)
├── circuits/          Noir ZK circuits
│   ├── fog_of_war/    Movement without revealing coordinates
│   └── territory_claim/ Tile ownership with adjacency proof
├── contracts/         Solidity (Foundry)
│   ├── src/mud/       MUD v2 tables + systems
│   ├── src/avs/       EigenLayer AVS contracts
│   ├── src/agents/    CivilizationNFT + ERC-6551
│   ├── src/economy/   AXM, Energy, Staking, Market
│   └── src/bridge/    LayerZero OApp
├── avs-operator/      Rust — EigenLayer operator node
├── ai-model/          Python — train + EZKL compile AI model
├── circuits/          Noir ZK circuits
├── l3-chain/          OP Stack chain config
├── subgraph/          The Graph event indexer
├── frontend/          Next.js 14 dApp
└── docker-compose.yml Full local dev stack
```

---

## Prerequisites

All commands run inside **WSL2 (Ubuntu)** on Windows, or native Linux/macOS.

| Tool | Install |
|---|---|
| WSL2 + Ubuntu | `wsl --install -d Ubuntu` (Windows only) |
| Node.js 20 | `nvm install 20 && nvm use 20` |
| Bun | `curl -fsSL https://bun.sh/install \| bash` |
| Foundry | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
| Nargo (Noir) | `curl -L https://raw.githubusercontent.com/noir-lang/noirup/main/install \| bash && noirup` |
| Rust | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| Python 3.11 | `sudo apt install python3.11 python3.11-venv` |
| Docker Desktop | `winget install Docker.DockerDesktop` (Windows) |
| VS Code + Remote WSL | See `.vscode/extensions.json` for all extensions |

---

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/your-org/axiom.git
cd axiom
cp .env.example .env
# Fill in your RPC URLs and keys in .env
```

### 2. Start the local stack

```bash
# Generate JWT secret for L3 node
mkdir -p secrets && openssl rand -hex 32 > secrets/jwt.hex

# Start L3 node + Graph node + IPFS + PostgreSQL
docker compose up -d l3-node postgres ipfs graph-node

# Verify L3 is running
curl http://localhost:8545 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### 3. Deploy contracts

```bash
cd contracts

# Install dependencies
forge install

# Run tests first
forge test -vvv

# Deploy ZK verifiers (after running nargo codegen-verifier)
# See circuits/compute_witness.sh

# Deploy full L3 world
forge script script/DeployL3.s.sol \
  --rpc-url http://localhost:8545 \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast -vvvv

# Deploy economy (mainnet / L2)
forge script script/DeployEconomy.s.sol \
  --rpc-url $L2_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast -vvvv

# Deploy AVS (Arbitrum)
forge script script/DeployAVS.s.sol \
  --rpc-url $L2_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast -vvvv
```

### 4. Build ZK circuits

```bash
cd circuits

# Run all tests
nargo test

# Compute witness values (generates commitment hashes for Prover.toml)
chmod +x compute_witness.sh && ./compute_witness.sh

# Prove + export Solidity verifiers
cd fog_of_war
nargo prove
nargo codegen-verifier
# Copy contract/plonk_vk.sol → ../contracts/src/zk/FogVerifier.sol

cd ../territory_claim
nargo prove
nargo codegen-verifier
# Copy contract/plonk_vk.sol → ../contracts/src/zk/TerritoryVerifier.sol
```

### 5. Train AI model and compile to ZK

```bash
cd ai-model

# Create Python venv
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Train faction strategy model (~5 min on CPU)
python train.py --epochs 100

# Export to ONNX
python export.py

# Inspect model predictions (open in VS Code Jupyter)
# Open inference_test.ipynb and run all cells

# Compile to ZK circuit + generate AIVerifier.sol
python ezkl_compile.py --output-dir ../circuits/ai_inference
# AIVerifier.sol is automatically copied to contracts/src/zk/
```

### 6. Start AVS operator

```bash
cd avs-operator

# Register operator on-chain (first time only)
cd ../contracts
forge script script/RegisterOperator.s.sol \
  --rpc-url $L2_RPC_URL \
  --private-key $OPERATOR_PRIVATE_KEY \
  --broadcast

# Start the operator node
cd ../avs-operator
cp .env.example .env  # fill in your keys
cargo run -- --env development
```

### 7. Deploy subgraph

```bash
cd subgraph
bun install

# Generate AssemblyScript types
graph codegen

# Build
graph build

# Deploy to local Graph node
graph create --node http://localhost:8020/ axiom/axiom-world
graph deploy --node http://localhost:8020/ --ipfs http://localhost:5001 axiom/axiom-world
```

### 8. Start frontend

```bash
cd frontend
bun install

# Copy contract addresses from deploy output to .env
# (forge script auto-writes to frontend/lib/contracts/*-addresses.json)

bun dev
# → http://localhost:3000
```

---

## Development Workflow

### VS Code tasks (Terminal → Run Task)

| Task | What it does |
|---|---|
| `AXIOM: dev (full local stack)` | Starts Anvil + Next.js + AVS watcher |
| `forge: test (all)` | Runs all Foundry tests with gas report |
| `forge: test (fuzz only)` | Runs fuzz tests with 10,000 runs |
| `nargo: test (all circuits)` | Tests both ZK circuits |
| `nargo: prove (fog_of_war)` | Generates a fog-of-war proof |
| `cargo: watch (auto rebuild)` | Rebuilds AVS operator on file change |
| `python: train faction model` | Trains the AI model |
| `ezkl: compile full pipeline` | Runs the full EZKL compilation |
| `docker: up (full stack)` | Starts all Docker services |

### Running tests

```bash
# Contracts — all tests
cd contracts && forge test -vvv

# Contracts — specific file
forge test --match-path test/unit/MoveSystem.t.sol -vvvv

# Contracts — fuzz with more runs
forge test --match-path test/fuzz/ --fuzz-runs 50000

# Contracts — invariant tests
forge test --match-path test/invariant/ -vvv

# Circuits
cd circuits && nargo test

# AVS operator
cd avs-operator && cargo test

# Frontend type-check
cd frontend && bun run type-check
```

### Generating ZK verifier contracts

After modifying a Noir circuit:

```bash
cd circuits/fog_of_war
nargo codegen-verifier
cp contract/plonk_vk.sol ../../contracts/src/zk/FogVerifier.sol

cd ../territory_claim
nargo codegen-verifier
cp contract/plonk_vk.sol ../../contracts/src/zk/TerritoryVerifier.sol
```

After modifying the AI model:

```bash
cd ai-model
source .venv/bin/activate
python train.py && python export.py && python ezkl_compile.py
# AIVerifier.sol is auto-copied to contracts/src/zk/
```

---

## Smart Contract Architecture

### MUD v2 Tables (on-chain state)

| Table | Key | Description |
|---|---|---|
| `CivilizationState` | `civId` | Territory, energy, agent model, nonces |
| `TerritoryMap` | `commitment` | Poseidon2 tile → civ owner mapping |
| `AgentActions` | `taskId` | Pending autonomous agent action queue |
| `BattleHistory` | `battleId` | Immutable battle record |
| `GameConfig` | singleton | Season, movement range, energy rate |

### MUD v2 Systems (on-chain actions)

| System | Verifies | Action |
|---|---|---|
| `MoveSystem` | Fog verifier (Noir proof) | Update position commitment |
| `ClaimSystem` | Territory verifier (Noir proof) | Add tile to territory |
| `BattleSystem` | — | Dispatch compute task to AVS |
| `AgentSystem` | AI verifier (EZKL proof) | Execute autonomous action |
| `EnergySystem` | — | Mint `$ENERGY` per block |

### Token Flow

```
$AXM (mainnet, capped 1B)
  → Bridge (LayerZero) → L2/L3
  → Staking → $ENERGY generation boost
  → Prediction Market → season bets
  → Paymaster → gasless gameplay

$ENERGY (L3 only, uncapped)
  → Minted by EnergySystem per tile per block
  → Burned for: battles (100), upgrades
```

---

## ZK Circuit Design

### Fog of War (`circuits/fog_of_war/`)

Proves movement from A→B without revealing A or B.

**Private inputs:** `from_x`, `from_y`, `to_x`, `to_y`, `player_secret`, `dx_magnitude`, `dy_magnitude`, `dx_positive`, `dy_positive`

**Public inputs:** `from_commitment`, `to_commitment`, `movement_range`, `nonce`, `season`

**Constraints:**
1. `from_commitment = Poseidon2(from_x, from_y, player_secret)`
2. `to_commitment = Poseidon2(to_x, to_y, player_secret)`
3. `|dx| + |dy| ≤ movement_range` (Manhattan distance)
4. `to = from + signed_delta` (coordinate consistency)
5. `movement_range ≤ 100` (cap)
6. `|dx| + |dy| > 0` (must actually move)

### Territory Claim (`circuits/territory_claim/`)

Proves adjacency-based expansion without revealing tile coordinates.

**Constraints:**
1. `claim_commitment = Poseidon2(claim_x, claim_y, civ_secret)`
2. `anchor_commitment = Poseidon2(anchor_x, anchor_y, civ_secret)`
3. `civ_id_hash = Poseidon2(civ_id, civ_secret)` (prevents proof theft)
4. `|dx| + |dy| = 1` (strict 4-directional adjacency)
5. Coordinate consistency (claim = anchor + delta)

---

## EigenLayer AVS

The AXIOM AVS handles off-chain compute that's too expensive for the L3:

- **Pathfinding** — A* on the territory graph for movement optimization
- **AI inference** — ONNX faction strategy model execution
- **Proof generation** — EZKL ZK proofs of AI inference results

Operators stake `$AXM` and get slashed for:
- Submitting wrong battle outcomes
- Missing task deadlines
- Submitting invalid AI proofs

**Register as an operator:**
```bash
cd contracts
forge script script/RegisterOperator.s.sol \
  --rpc-url $L2_RPC_URL \
  --private-key $OPERATOR_PRIVATE_KEY \
  --broadcast
```

---

## Deployment Checklist

### Testnet (Arbitrum Sepolia + custom L3)

- [ ] Generate JWT secret: `openssl rand -hex 32 > secrets/jwt.hex`
- [ ] Deploy L3 genesis block: `op-node genesis l2`
- [ ] Start L3 node + op-node
- [ ] Deploy ZK verifier contracts (after Noir compile)
- [ ] Run `DeployEconomy.s.sol` on Arbitrum Sepolia
- [ ] Run `DeployAVS.s.sol` on Arbitrum Sepolia
- [ ] Run `DeployL3.s.sol` on L3
- [ ] Register operator: `RegisterOperator.s.sol`
- [ ] Deploy subgraph to hosted service
- [ ] Set `NEXT_PUBLIC_*` addresses in frontend `.env`
- [ ] Run `bun run build` — verify no type errors
- [ ] Deploy frontend to Vercel / Netlify

### Mainnet

- [ ] Full audit (Trail of Bits for AVS, Spearbit for ZK verifiers)
- [ ] Formal verification of Noir circuits (Veridise)
- [ ] Bug bounty on Immunefi
- [ ] Multisig for all admin roles (Safe)
- [ ] Timelock on DAO treasury
- [ ] Gradual rollout — Season 0 with invite-only

---

## Contributing

```bash
# Run full test suite before opening a PR
cd contracts      && forge test --fuzz-runs 10000
cd ../circuits    && nargo test
cd ../avs-operator && cargo test
cd ../frontend    && bun run type-check && bun run lint
```

Code style:
- **Solidity** — `forge fmt` (enforced by CI)
- **Rust** — `cargo fmt` + `cargo clippy`
- **TypeScript** — `prettier` (auto on save via VS Code)
- **Noir** — `nargo fmt`

---

## License

MIT — see [LICENSE](./LICENSE)

---

## Acknowledgements

Built on the shoulders of:
- [Dark Forest](https://zkga.me/) — ZK fog-of-war concept
- [MUD v2](https://mud.dev/) by Lattice — on-chain ECS framework
- [Noir](https://noir-lang.org/) by Aztec — ZK circuit language
- [EZKL](https://ezkl.xyz/) — ZK-ML compilation
- [EigenLayer](https://eigenlayer.xyz/) — restaking + AVS framework
- [OP Stack](https://stack.optimism.io/) — L2/L3 rollup infrastructure
- [LayerZero v2](https://layerzero.network/) — cross-chain messaging

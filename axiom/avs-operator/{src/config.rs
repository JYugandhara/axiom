//! Operator configuration.
//! Loaded from environment variables + optional config file.

use eyre::Result;
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OperatorConfig {
    /// Environment name
    pub env: String,

    // ── Chain ─────────────────────────────────────────────────
    /// L3 WebSocket RPC URL
    pub l3_rpc_url: String,
    /// Ethereum mainnet RPC (for EigenLayer registry)
    pub mainnet_rpc_url: String,
    /// Arbitrum One RPC (for AVS ServiceManager)
    pub l2_rpc_url: String,

    // ── Contracts ─────────────────────────────────────────────
    /// AxiomTaskManager.sol address on L3
    pub task_manager_address: String,
    /// AxiomServiceManager.sol address on L2
    pub service_manager_address: String,
    /// AxiomWorld MUD world address on L3
    pub world_address: String,

    // ── Operator identity ─────────────────────────────────────
    /// Operator ECDSA private key (hex, no 0x prefix)
    /// In production: load from KMS / HSM, never hardcode
    pub operator_private_key: String,
    /// BLS private key for EigenLayer operator registration
    pub bls_private_key: String,

    // ── AI model ──────────────────────────────────────────────
    /// Path to compiled ONNX model
    pub model_path: String,
    /// Path to EZKL compiled circuit
    pub circuit_path: String,
    /// Path to EZKL proving key
    pub proving_key_path: String,

    // ── Worker settings ───────────────────────────────────────
    /// Max concurrent tasks being processed
    pub max_concurrent_tasks: usize,
    /// Task deadline buffer (blocks before deadline to stop accepting)
    pub deadline_buffer_blocks: u64,
    /// Max task age in ms before dropping
    pub max_task_age_ms: u64,
    /// Pathfinding: max graph nodes to explore
    pub pathfinding_max_nodes: usize,

    // ── Proof settings ────────────────────────────────────────
    /// Timeout for EZKL proof generation (seconds)
    pub proof_timeout_secs: u64,
    /// Retry failed proofs this many times
    pub proof_retries: u32,

    // ── Submission ────────────────────────────────────────────
    /// Gas limit for submitTaskResponse transactions
    pub submit_gas_limit: u64,
    /// Max gas price in gwei
    pub max_gas_gwei: u64,
    /// Retry failed submissions this many times
    pub submit_retries: u32,

    // ── Misc ──────────────────────────────────────────────────
    /// Skip on-chain submission (for local testing)
    pub dry_run: bool,
    /// Poll interval for new tasks (milliseconds)
    pub poll_interval_ms: u64,
}

impl OperatorConfig {
    pub fn load(env: &str, config_path: Option<&str>) -> Result<Self> {
        // Load .env file
        dotenvy::dotenv().ok();

        // Build config from environment variables with defaults
        let cfg = Self {
            env: env.to_string(),

            // Chain endpoints
            l3_rpc_url: std::env::var("L3_RPC_URL")
                .unwrap_or_else(|_| match env {
                    "development" => "ws://127.0.0.1:8546".to_string(),
                    "testnet"     => "wss://axiom-testnet.rpc.thirdweb.com".to_string(),
                    _             => "wss://axiom-mainnet.rpc.thirdweb.com".to_string(),
                }),

            mainnet_rpc_url: std::env::var("MAINNET_RPC_URL")
                .unwrap_or_else(|_| "wss://eth-mainnet.g.alchemy.com/v2/demo".to_string()),

            l2_rpc_url: std::env::var("L2_RPC_URL")
                .unwrap_or_else(|_| "wss://arb-mainnet.g.alchemy.com/v2/demo".to_string()),

            // Contracts
            task_manager_address: std::env::var("TASK_MANAGER_ADDRESS")
                .unwrap_or_else(|_| "0x0000000000000000000000000000000000000001".to_string()),

            service_manager_address: std::env::var("SERVICE_MANAGER_ADDRESS")
                .unwrap_or_else(|_| "0x0000000000000000000000000000000000000002".to_string()),

            world_address: std::env::var("WORLD_ADDRESS")
                .unwrap_or_else(|_| "0x0000000000000000000000000000000000000003".to_string()),

            // Operator keys — NEVER hardcode in production
            operator_private_key: std::env::var("OPERATOR_PRIVATE_KEY")
                .unwrap_or_else(|_| {
                    if env == "development" {
                        // Anvil account #0 — dev only
                        "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80".to_string()
                    } else {
                        panic!("OPERATOR_PRIVATE_KEY must be set in .env for {env}")
                    }
                }),

            bls_private_key: std::env::var("BLS_PRIVATE_KEY")
                .unwrap_or_else(|_| "0x01".to_string()),

            // AI model artifacts
            model_path: std::env::var("MODEL_PATH")
                .unwrap_or_else(|_| "../ai-model/model.onnx".to_string()),

            circuit_path: std::env::var("CIRCUIT_PATH")
                .unwrap_or_else(|_| "../circuits/ai_inference/circuit.ezkl".to_string()),

            proving_key_path: std::env::var("PROVING_KEY_PATH")
                .unwrap_or_else(|_| "../circuits/ai_inference/pk.key".to_string()),

            // Worker
            max_concurrent_tasks: std::env::var("MAX_CONCURRENT_TASKS")
                .ok().and_then(|v| v.parse().ok()).unwrap_or(4),

            deadline_buffer_blocks: std::env::var("DEADLINE_BUFFER_BLOCKS")
                .ok().and_then(|v| v.parse().ok()).unwrap_or(5),

            max_task_age_ms: std::env::var("MAX_TASK_AGE_MS")
                .ok().and_then(|v| v.parse().ok()).unwrap_or(30_000),

            pathfinding_max_nodes: std::env::var("PATHFINDING_MAX_NODES")
                .ok().and_then(|v| v.parse().ok()).unwrap_or(10_000),

            // Proof
            proof_timeout_secs: std::env::var("PROOF_TIMEOUT_SECS")
                .ok().and_then(|v| v.parse().ok()).unwrap_or(120),

            proof_retries: std::env::var("PROOF_RETRIES")
                .ok().and_then(|v| v.parse().ok()).unwrap_or(2),

            // Submission
            submit_gas_limit: std::env::var("SUBMIT_GAS_LIMIT")
                .ok().and_then(|v| v.parse().ok()).unwrap_or(500_000),

            max_gas_gwei: std::env::var("MAX_GAS_GWEI")
                .ok().and_then(|v| v.parse().ok()).unwrap_or(50),

            submit_retries: std::env::var("SUBMIT_RETRIES")
                .ok().and_then(|v| v.parse().ok()).unwrap_or(3),

            dry_run: std::env::var("DRY_RUN")
                .map(|v| v == "true" || v == "1").unwrap_or(false),

            poll_interval_ms: std::env::var("POLL_INTERVAL_MS")
                .ok().and_then(|v| v.parse().ok()).unwrap_or(500),
        };

        // Override with config file if provided
        if let Some(path) = config_path {
            if Path::new(path).exists() {
                tracing::info!(path, "Loading config file overrides");
                // In production: merge JSON/TOML config file here
            }
        }

        cfg.validate()?;
        Ok(cfg)
    }

    fn validate(&self) -> Result<()> {
        if self.operator_private_key.is_empty() {
            eyre::bail!("OPERATOR_PRIVATE_KEY is required");
        }
        if self.task_manager_address == "0x0000000000000000000000000000000000000001"
            && self.env != "development"
        {
            eyre::bail!("TASK_MANAGER_ADDRESS must be set for env={}", self.env);
        }
        Ok(())
    }
}
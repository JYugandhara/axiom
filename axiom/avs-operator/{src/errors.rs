//! Custom error types for the AXIOM AVS operator.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum OperatorError {
    // ── Chain errors ─────────────────────────────────────────
    #[error("Failed to connect to L3 chain: {0}")]
    ChainConnection(String),

    #[error("RPC call failed: {method} — {reason}")]
    RpcError { method: String, reason: String },

    #[error("Transaction failed: {tx_hash} — {reason}")]
    TxFailed { tx_hash: String, reason: String },

    #[error("Transaction reverted: {0}")]
    TxReverted(String),

    #[error("Gas estimation failed: {0}")]
    GasEstimation(String),

    // ── Task errors ───────────────────────────────────────────
    #[error("Unknown task type: {0}")]
    UnknownTaskType(u8),

    #[error("Task decode failed: {0}")]
    TaskDecode(String),

    #[error("Task {task_id} expired (deadline block {deadline})")]
    TaskExpired { task_id: String, deadline: u64 },

    #[error("Task {task_id} too old ({age_ms}ms)")]
    TaskTooOld { task_id: String, age_ms: u64 },

    #[error("Task queue full ({capacity} slots)")]
    QueueFull { capacity: usize },

    // ── Pathfinding errors ────────────────────────────────────
    #[error("No path found from {from} to {to}")]
    NoPath { from: usize, to: usize },

    #[error("Pathfinding exceeded node limit ({limit} nodes)")]
    PathfindingLimitExceeded { limit: usize },

    #[error("Invalid graph: {0}")]
    InvalidGraph(String),

    // ── AI inference errors ───────────────────────────────────
    #[error("Failed to load ONNX model from {path}: {reason}")]
    ModelLoad { path: String, reason: String },

    #[error("Model inference failed: {0}")]
    InferenceFailed(String),

    #[error("Invalid model input shape: expected {expected:?}, got {got:?}")]
    InvalidInputShape { expected: Vec<usize>, got: Vec<usize> },

    #[error("Model output is NaN or Inf")]
    InvalidModelOutput,

    // ── Prover errors ─────────────────────────────────────────
    #[error("EZKL proof generation failed: {0}")]
    ProofFailed(String),

    #[error("Proof generation timed out after {secs}s")]
    ProofTimeout { secs: u64 },

    #[error("Proof verification failed locally — will not submit")]
    ProofInvalid,

    #[error("Circuit file not found: {0}")]
    CircuitNotFound(String),

    #[error("Proving key not found: {0}")]
    ProvingKeyNotFound(String),

    // ── Crypto errors ─────────────────────────────────────────
    #[error("Signing failed: {0}")]
    SigningFailed(String),

    #[error("Invalid signature: {0}")]
    InvalidSignature(String),

    // ── Config errors ─────────────────────────────────────────
    #[error("Missing required config: {0}")]
    MissingConfig(String),

    #[error("Invalid config value for {key}: {reason}")]
    InvalidConfig { key: String, reason: String },
}

/// Shorthand result type
pub type OperatorResult<T> = Result<T, OperatorError>;
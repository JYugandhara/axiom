//! Shared types used across all AVS operator modules.

use ethers::types::{Address, Bytes, H256, U256};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ─────────────────────────────────────────────────────────────
//  Task Types (mirrors AxiomTaskManager.sol events)
// ─────────────────────────────────────────────────────────────

/// Raw task as emitted by AxiomTaskManager.sol on L3
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawTask {
    /// On-chain task ID (incrementing uint256)
    pub task_id: U256,
    /// Task type discriminant
    pub task_type: TaskType,
    /// ABI-encoded task payload
    pub payload: Bytes,
    /// Block number when task was created
    pub created_block: u64,
    /// Deadline block — task expires if not answered by then
    pub deadline_block: u64,
    /// Requester civilization NFT ID
    pub civ_id: U256,
}

/// Decoded, typed task ready for dispatch
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Task {
    Pathfinding(PathfindingTask),
    AIAction(AIActionTask),
    BattleResolution(BattleTask),
}

impl Task {
    pub fn task_id(&self) -> U256 {
        match self {
            Task::Pathfinding(t)      => t.task_id,
            Task::AIAction(t)         => t.task_id,
            Task::BattleResolution(t) => t.task_id,
        }
    }

    pub fn civ_id(&self) -> U256 {
        match self {
            Task::Pathfinding(t)      => t.civ_id,
            Task::AIAction(t)         => t.civ_id,
            Task::BattleResolution(t) => t.attacker_id,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[repr(u8)]
pub enum TaskType {
    Pathfinding      = 0,
    AIAction         = 1,
    BattleResolution = 2,
}

impl TryFrom<u8> for TaskType {
    type Error = eyre::Error;
    fn try_from(v: u8) -> eyre::Result<Self> {
        match v {
            0 => Ok(TaskType::Pathfinding),
            1 => Ok(TaskType::AIAction),
            2 => Ok(TaskType::BattleResolution),
            n => eyre::bail!("Unknown task type: {n}"),
        }
    }
}

// ─────────────────────────────────────────────────────────────
//  Pathfinding Task
// ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PathfindingTask {
    pub task_id   : U256,
    pub civ_id    : U256,
    /// Poseidon-hashed source tile commitment
    pub from_hash : H256,
    /// Poseidon-hashed destination tile commitment
    pub to_hash   : H256,
    /// Known adjacency graph (only revealed tiles)
    pub graph     : TerritoryGraph,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerritoryGraph {
    /// Revealed tile coordinates (unhashed for pathfinding)
    pub tiles     : Vec<Tile>,
    /// Adjacency edges between tile indices
    pub edges     : Vec<(usize, usize, u32)>, // (from, to, cost)
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Tile {
    pub index     : usize,
    pub x         : i32,
    pub y         : i32,
    pub passable  : bool,
    pub cost      : u32,   // movement cost (terrain)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PathfindingResult {
    pub task_id   : U256,
    pub civ_id    : U256,
    /// Ordered list of tile indices forming the path
    pub path      : Vec<usize>,
    /// Total movement cost
    pub total_cost: u32,
    /// Found a valid path
    pub reachable : bool,
}

// ─────────────────────────────────────────────────────────────
//  AI Action Task
// ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIActionTask {
    pub task_id       : U256,
    pub civ_id        : U256,
    /// Last SEQ_LEN game states (flattened float32 tensor)
    pub state_history : Vec<f32>,   // shape: [SEQ_LEN * STATE_DIM]
    pub seq_len       : usize,
    pub state_dim     : usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIActionResult {
    pub task_id       : U256,
    pub civ_id        : U256,
    /// Predicted action index (0-7)
    pub action        : u8,
    pub action_name   : String,
    /// Softmax probabilities for all actions
    pub probabilities : Vec<f32>,
    /// Confidence (max probability)
    pub confidence    : f32,
    /// ZK proof of inference (EZKL proof bytes)
    pub proof         : Vec<u8>,
}

// ─────────────────────────────────────────────────────────────
//  Battle Task
// ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BattleTask {
    pub task_id      : U256,
    pub attacker_id  : U256,
    pub defender_id  : U256,
    pub attacker_atk : u32,
    pub attacker_def : u32,
    pub defender_atk : u32,
    pub defender_def : u32,
    /// VRF randomness seed for this battle
    pub vrf_seed     : H256,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BattleResult {
    pub task_id       : U256,
    pub attacker_wins : bool,
    pub damage_dealt  : u32,
    pub territory_transferred: u32,
}

// ─────────────────────────────────────────────────────────────
//  Task Response (submitted on-chain)
// ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskResponse {
    pub task_id        : U256,
    pub task_type      : u8,
    /// ABI-encoded result payload
    pub result_payload : Bytes,
    /// EZKL ZK proof (for AI tasks)
    pub zk_proof       : Bytes,
    /// Operator ECDSA signature over keccak256(task_id || result_payload)
    pub signature      : Bytes,
    /// Processing duration in milliseconds
    pub processing_ms  : u64,
    pub operator       : Address,
}

// ─────────────────────────────────────────────────────────────
//  Operator State
// ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OperatorStats {
    pub tasks_completed : u64,
    pub tasks_failed    : u64,
    pub tasks_timed_out : u64,
    pub avg_proof_ms    : f64,
    pub total_rewards   : U256,
    pub slash_count     : u64,
}

impl Default for OperatorStats {
    fn default() -> Self {
        Self {
            tasks_completed : 0,
            tasks_failed    : 0,
            tasks_timed_out : 0,
            avg_proof_ms    : 0.0,
            total_rewards   : U256::zero(),
            slash_count     : 0,
        }
    }
}

// ─────────────────────────────────────────────────────────────
//  Internal Worker Message Types
// ─────────────────────────────────────────────────────────────

#[derive(Debug)]
pub struct WorkerJob {
    pub job_id  : Uuid,
    pub task    : Task,
    pub created : chrono::DateTime<chrono::Utc>,
}

impl WorkerJob {
    pub fn new(task: Task) -> Self {
        Self {
            job_id  : Uuid::new_v4(),
            task,
            created : chrono::Utc::now(),
        }
    }

    pub fn age_ms(&self) -> i64 {
        (chrono::Utc::now() - self.created).num_milliseconds()
    }
}
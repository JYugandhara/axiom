//! Task Dispatcher
//!
//! Watches the L3 chain for new AxiomTaskManager events,
//! decodes them into typed Tasks, dispatches to the right
//! worker, collects results, and submits responses on-chain.

use std::sync::Arc;
use std::time::{Duration, Instant};

use eyre::Result;
use tokio::sync::{mpsc, Semaphore};
use tokio::time::sleep;
use tracing::{debug, error, info, warn};

use crate::{
    ai_inference::AIInferenceWorker,
    chain::ChainClient,
    config::OperatorConfig,
    errors::OperatorError,
    metrics::Metrics,
    pathfinding::PathfindingWorker,
    prover::ProverWorker,
    types::*,
};

// ─────────────────────────────────────────────────────────────
//  Task Dispatcher
// ─────────────────────────────────────────────────────────────

pub struct TaskDispatcher {
    chain       : Arc<ChainClient>,
    ai_worker   : Arc<AIInferenceWorker>,
    metrics     : Arc<Metrics>,
    cfg         : OperatorConfig,
    semaphore   : Arc<Semaphore>,
}

impl TaskDispatcher {
    pub fn new(
        chain     : Arc<ChainClient>,
        ai_worker : Arc<AIInferenceWorker>,
        metrics   : Arc<Metrics>,
        cfg       : OperatorConfig,
    ) -> Self {
        let semaphore = Arc::new(Semaphore::new(cfg.max_concurrent_tasks));
        Self { chain, ai_worker, metrics, cfg, semaphore }
    }

    /// Main loop — polls for tasks and dispatches them.
    pub async fn run(&self) -> Result<()> {
        let (result_tx, mut result_rx) = mpsc::channel::<TaskResponse>(64);
        let poll_ms = self.cfg.poll_interval_ms;

        info!(
            max_concurrent = self.cfg.max_concurrent_tasks,
            poll_interval_ms = poll_ms,
            "Task dispatcher started"
        );

        // Spawn result submitter
        let chain_clone   = Arc::clone(&self.chain);
        let metrics_clone = Arc::clone(&self.metrics);
        let dry_run       = self.cfg.dry_run;

        tokio::spawn(async move {
            while let Some(response) = result_rx.recv().await {
                Self::submit_response(&chain_clone, response, dry_run, &metrics_clone).await;
            }
        });

        // Main polling loop
        loop {
            match self.chain.fetch_pending_tasks().await {
                Ok(raw_tasks) => {
                    if !raw_tasks.is_empty() {
                        info!(count = raw_tasks.len(), "Fetched pending tasks");
                    }

                    for raw in raw_tasks {
                        let task = match self.decode_task(&raw) {
                            Ok(t)  => t,
                            Err(e) => {
                                warn!(
                                    task_id = %raw.task_id,
                                    error   = %e,
                                    "Skipping undecodable task"
                                );
                                self.metrics.tasks_failed.inc();
                                continue;
                            }
                        };

                        // Check task freshness
                        if let Err(e) = self.validate_task(&raw) {
                            warn!(task_id = %raw.task_id, reason = %e, "Dropping stale task");
                            self.metrics.tasks_timed_out.inc();
                            continue;
                        }

                        let permit    = match self.semaphore.clone().try_acquire_owned() {
                            Ok(p)  => p,
                            Err(_) => {
                                warn!("Task queue full — dropping task {}", raw.task_id);
                                self.metrics.tasks_dropped.inc();
                                continue;
                            }
                        };

                        // Spawn worker for this task
                        let tx          = result_tx.clone();
                        let ai          = Arc::clone(&self.ai_worker);
                        let metrics     = Arc::clone(&self.metrics);
                        let cfg         = self.cfg.clone();
                        let chain       = Arc::clone(&self.chain);

                        tokio::spawn(async move {
                            let _permit = permit; // dropped when task finishes
                            Self::process_task(task, ai, chain, metrics, cfg, tx).await;
                        });
                    }
                }
                Err(e) => {
                    error!("Failed to fetch tasks: {e}");
                    self.metrics.rpc_errors.inc();
                }
            }

            sleep(Duration::from_millis(poll_ms)).await;
        }
    }

    // ─────────────────────────────────────────────────────────
    //  Task Decode
    // ─────────────────────────────────────────────────────────

    fn decode_task(&self, raw: &RawTask) -> Result<Task> {
        match raw.task_type {
            TaskType::Pathfinding => {
                let t = decode_pathfinding_payload(&raw.payload, raw.task_id, raw.civ_id)
                    .map_err(|e| OperatorError::TaskDecode(e.to_string()))?;
                Ok(Task::Pathfinding(t))
            }
            TaskType::AIAction => {
                let t = decode_ai_payload(&raw.payload, raw.task_id, raw.civ_id)
                    .map_err(|e| OperatorError::TaskDecode(e.to_string()))?;
                Ok(Task::AIAction(t))
            }
            TaskType::BattleResolution => {
                let t = decode_battle_payload(&raw.payload, raw.task_id, raw.civ_id)
                    .map_err(|e| OperatorError::TaskDecode(e.to_string()))?;
                Ok(Task::BattleResolution(t))
            }
        }
    }

    fn validate_task(&self, raw: &RawTask) -> Result<()> {
        // Check deadline
        let current_block = 0u64; // TODO: fetch current block
        if raw.deadline_block < current_block + self.cfg.deadline_buffer_blocks {
            return Err(OperatorError::TaskExpired {
                task_id : raw.task_id.to_string(),
                deadline: raw.deadline_block,
            }.into());
        }
        Ok(())
    }

    // ─────────────────────────────────────────────────────────
    //  Task Processing
    // ─────────────────────────────────────────────────────────

    async fn process_task(
        task    : Task,
        ai      : Arc<AIInferenceWorker>,
        chain   : Arc<ChainClient>,
        metrics : Arc<Metrics>,
        cfg     : OperatorConfig,
        tx      : mpsc::Sender<TaskResponse>,
    ) {
        let task_id = task.task_id();
        let started = Instant::now();

        info!(task_id = %task_id, task_type = ?std::mem::discriminant(&task), "Processing task");

        let result = match &task {
            Task::Pathfinding(t) => {
                Self::handle_pathfinding(t, &cfg).await
            }
            Task::AIAction(t) => {
                Self::handle_ai_action(t, &ai, &cfg).await
            }
            Task::BattleResolution(t) => {
                Self::handle_battle(t).await
            }
        };

        let elapsed_ms = started.elapsed().as_millis() as u64;

        match result {
            Ok(response) => {
                info!(
                    task_id    = %task_id,
                    elapsed_ms = elapsed_ms,
                    "Task processed successfully"
                );
                metrics.tasks_completed.inc();
                metrics.processing_ms.observe(elapsed_ms as f64);

                if tx.send(response).await.is_err() {
                    error!("Result channel closed — dropping response for {task_id}");
                }
            }
            Err(e) => {
                error!(task_id = %task_id, error = %e, "Task processing failed");
                metrics.tasks_failed.inc();
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    //  Pathfinding Handler
    // ─────────────────────────────────────────────────────────

    async fn handle_pathfinding(
        task : &PathfindingTask,
        cfg  : &OperatorConfig,
    ) -> Result<TaskResponse> {
        let worker = PathfindingWorker::new(cfg.pathfinding_max_nodes);
        let result = worker.find_path(task)?;

        debug!(
            task_id    = %task.task_id,
            path_len   = result.path.len(),
            total_cost = result.total_cost,
            reachable  = result.reachable,
            "Pathfinding complete"
        );

        let payload = encode_pathfinding_result(&result);
        Ok(TaskResponse {
            task_id        : task.task_id,
            task_type      : TaskType::Pathfinding as u8,
            result_payload : payload.into(),
            zk_proof       : vec![].into(), // Pathfinding doesn't need ZK proof
            signature      : vec![].into(), // Signed in ChainClient.submit
            processing_ms  : 0,
            operator       : ethers::types::Address::zero(),
        })
    }

    // ─────────────────────────────────────────────────────────
    //  AI Action Handler
    // ─────────────────────────────────────────────────────────

    async fn handle_ai_action(
        task   : &AIActionTask,
        ai     : &Arc<AIInferenceWorker>,
        cfg    : &OperatorConfig,
    ) -> Result<TaskResponse> {
        // 1. Run AI inference
        let inference = ai.predict(task)?;

        info!(
            task_id    = %task.task_id,
            action     = inference.action,
            action_name = %inference.action_name,
            confidence = inference.confidence,
            "AI inference complete"
        );

        // 2. Generate EZKL ZK proof of the inference
        let prover = ProverWorker::new(
            &cfg.circuit_path,
            &cfg.proving_key_path,
            cfg.proof_timeout_secs,
        );
        let proof = tokio::time::timeout(
            Duration::from_secs(cfg.proof_timeout_secs),
            tokio::task::spawn_blocking(move || {
                prover.generate_proof(&task.state_history, inference.action)
            }),
        )
        .await
        .map_err(|_| OperatorError::ProofTimeout { secs: cfg.proof_timeout_secs })?
        .map_err(|e| OperatorError::ProofFailed(e.to_string()))??;

        info!(task_id = %task.task_id, proof_size_bytes = proof.len(), "ZK proof generated");

        let payload = encode_ai_result(&inference);
        Ok(TaskResponse {
            task_id        : task.task_id,
            task_type      : TaskType::AIAction as u8,
            result_payload : payload.into(),
            zk_proof       : proof.into(),
            signature      : vec![].into(),
            processing_ms  : 0,
            operator       : ethers::types::Address::zero(),
        })
    }

    // ─────────────────────────────────────────────────────────
    //  Battle Handler
    // ─────────────────────────────────────────────────────────

    async fn handle_battle(task: &BattleTask) -> Result<TaskResponse> {
        // Deterministic battle resolution from VRF seed
        let seed_bytes: [u8; 32] = task.vrf_seed.0;
        let roll = u64::from_le_bytes(seed_bytes[0..8].try_into().unwrap()) % 100;

        // Attack score: weighted random + stats
        let atk_score = (roll as u32 * task.attacker_atk) / 100
            + (task.attacker_atk.saturating_sub(task.defender_def));

        let def_score = ((100 - roll) as u32 * task.defender_def) / 100
            + task.defender_def / 2;

        let attacker_wins       = atk_score > def_score;
        let damage_dealt        = atk_score.max(def_score) - atk_score.min(def_score);
        let territory_transferred = if attacker_wins { (damage_dealt / 10).max(1) } else { 0 };

        let result = BattleResult {
            task_id: task.task_id,
            attacker_wins,
            damage_dealt,
            territory_transferred,
        };

        info!(
            task_id           = %task.task_id,
            attacker_wins     = attacker_wins,
            territory_lost    = territory_transferred,
            "Battle resolved"
        );

        let payload = encode_battle_result(&result);
        Ok(TaskResponse {
            task_id        : task.task_id,
            task_type      : TaskType::BattleResolution as u8,
            result_payload : payload.into(),
            zk_proof       : vec![].into(),
            signature      : vec![].into(),
            processing_ms  : 0,
            operator       : ethers::types::Address::zero(),
        })
    }

    // ─────────────────────────────────────────────────────────
    //  On-chain Submission
    // ─────────────────────────────────────────────────────────

    async fn submit_response(
        chain   : &ChainClient,
        response: TaskResponse,
        dry_run : bool,
        metrics : &Metrics,
    ) {
        if dry_run {
            info!(
                task_id   = %response.task_id,
                "[DRY RUN] Would submit task response"
            );
            return;
        }

        match chain.submit_task_response(response).await {
            Ok(tx_hash) => {
                info!(tx_hash = %tx_hash, "Task response submitted ✓");
                metrics.submissions_ok.inc();
            }
            Err(e) => {
                error!("Failed to submit task response: {e}");
                metrics.submissions_failed.inc();
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────
//  ABI Encode / Decode helpers
//  In production: use ethers::abi::encode for proper ABI packing
// ─────────────────────────────────────────────────────────────

fn decode_pathfinding_payload(
    payload : &[u8],
    task_id : ethers::types::U256,
    civ_id  : ethers::types::U256,
) -> Result<PathfindingTask> {
    // Stub — replace with ethers::abi::decode matching contract ABI
    Ok(PathfindingTask {
        task_id,
        civ_id,
        from_hash : ethers::types::H256::zero(),
        to_hash   : ethers::types::H256::zero(),
        graph     : TerritoryGraph { tiles: vec![], edges: vec![] },
    })
}

fn decode_ai_payload(
    payload : &[u8],
    task_id : ethers::types::U256,
    civ_id  : ethers::types::U256,
) -> Result<AIActionTask> {
    // Decode: first 4 bytes = seq_len, next 4 = state_dim, rest = f32 array
    if payload.len() < 8 {
        eyre::bail!("AI payload too short: {} bytes", payload.len());
    }
    let seq_len   = u32::from_be_bytes(payload[0..4].try_into()?) as usize;
    let state_dim = u32::from_be_bytes(payload[4..8].try_into()?) as usize;
    let expected  = seq_len * state_dim * 4 + 8;

    if payload.len() < expected {
        eyre::bail!("AI payload incomplete: got {}, want {}", payload.len(), expected);
    }

    let floats: Vec<f32> = payload[8..8 + seq_len * state_dim * 4]
        .chunks(4)
        .map(|b| f32::from_be_bytes(b.try_into().unwrap()))
        .collect();

    Ok(AIActionTask { task_id, civ_id, state_history: floats, seq_len, state_dim })
}

fn decode_battle_payload(
    payload : &[u8],
    task_id : ethers::types::U256,
    civ_id  : ethers::types::U256,
) -> Result<BattleTask> {
    // Stub — replace with ethers ABI decode
    Ok(BattleTask {
        task_id,
        attacker_id  : civ_id,
        defender_id  : ethers::types::U256::zero(),
        attacker_atk : 50,
        attacker_def : 40,
        defender_atk : 45,
        defender_def : 55,
        vrf_seed     : ethers::types::H256::random(),
    })
}

fn encode_pathfinding_result(result: &PathfindingResult) -> Vec<u8> {
    serde_json::to_vec(result).unwrap_or_default()
}

fn encode_ai_result(result: &AIActionResult) -> Vec<u8> {
    // Encode: action (1 byte) + confidence (4 bytes f32) + probs (ACTION_DIM * 4 bytes)
    let mut buf = vec![result.action];
    buf.extend_from_slice(&result.confidence.to_be_bytes());
    for p in &result.probabilities {
        buf.extend_from_slice(&p.to_be_bytes());
    }
    buf
}

fn encode_battle_result(result: &BattleResult) -> Vec<u8> {
    serde_json::to_vec(result).unwrap_or_default()
}
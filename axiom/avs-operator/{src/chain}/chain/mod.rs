//! Chain Client
//!
//! Connects to the AXIOM L3 chain via WebSocket RPC.
//! Watches AxiomTaskManager for NewTask events,
//! signs and submits TaskResponse transactions.

use std::sync::Arc;

use ethers::{
    contract::abigen,
    middleware::SignerMiddleware,
    providers::{Middleware, Provider, Ws},
    signers::{LocalWallet, Signer},
    types::{Address, Bytes, H256, U256},
};
use eyre::Result;
use tracing::{debug, info, warn};

use crate::{
    config::OperatorConfig,
    errors::OperatorError,
    types::{RawTask, TaskResponse, TaskType},
};

// ─────────────────────────────────────────────────────────────
//  Contract ABIs (generated from Solidity ABIs)
//  In production: use forge build --silent && forge inspect for ABIs
// ─────────────────────────────────────────────────────────────

abigen!(
    AxiomTaskManager,
    r#"[
        event NewTask(uint256 indexed taskId, uint8 taskType, bytes payload, uint256 civId, uint64 deadlineBlock)
        event TaskResponded(uint256 indexed taskId, address indexed operator, bool accepted)
        function submitTaskResponse(uint256 taskId, uint8 taskType, bytes calldata resultPayload, bytes calldata zkProof, bytes calldata signature) external
        function getTask(uint256 taskId) external view returns (uint8 taskType, bytes memory payload, uint256 civId, uint64 deadlineBlock, bool completed)
        function pendingTaskIds() external view returns (uint256[] memory)
        function isOperatorRegistered(address operator) external view returns (bool)
    ]"#
);

// ─────────────────────────────────────────────────────────────
//  Chain Client
// ─────────────────────────────────────────────────────────────

type SignedProvider = SignerMiddleware<Provider<Ws>, LocalWallet>;

pub struct ChainClient {
    provider        : Arc<SignedProvider>,
    task_manager    : AxiomTaskManager<SignedProvider>,
    operator_wallet : LocalWallet,
    cfg             : OperatorConfig,
}

impl ChainClient {
    pub async fn new(cfg: &OperatorConfig) -> Result<Self> {
        // Connect to L3 WebSocket RPC
        let ws = Ws::connect(&cfg.l3_rpc_url)
            .await
            .map_err(|e| OperatorError::ChainConnection(e.to_string()))?;

        let provider = Provider::new(ws);

        // Load operator wallet from private key
        let wallet: LocalWallet = cfg
            .operator_private_key
            .parse()
            .map_err(|e: eyre::Error| OperatorError::SigningFailed(e.to_string()))?;

        let chain_id = provider
            .get_chainid()
            .await
            .map_err(|e| OperatorError::RpcError {
                method: "eth_chainId".to_string(),
                reason: e.to_string(),
            })?
            .as_u64();

        info!(chain_id, operator = %wallet.address(), "Chain client initialized");

        let wallet   = wallet.with_chain_id(chain_id);
        let provider = Arc::new(SignerMiddleware::new(provider, wallet.clone()));

        // Instantiate task manager contract
        let task_manager_address: Address = cfg
            .task_manager_address
            .parse()
            .map_err(|_| OperatorError::InvalidConfig {
                key   : "task_manager_address".to_string(),
                reason: "Not a valid EVM address".to_string(),
            })?;

        let task_manager = AxiomTaskManager::new(
            task_manager_address,
            Arc::clone(&provider),
        );

        Ok(Self {
            provider,
            task_manager,
            operator_wallet: wallet,
            cfg: cfg.clone(),
        })
    }

    /// Returns the operator's Ethereum address.
    pub fn operator_address(&self) -> Address {
        self.operator_wallet.address()
    }

    // ─────────────────────────────────────────────────────────
    //  Task Fetching
    // ─────────────────────────────────────────────────────────

    /// Fetch all pending task IDs then decode each task.
    pub async fn fetch_pending_tasks(&self) -> Result<Vec<RawTask>> {
        let pending_ids = self
            .task_manager
            .pending_task_ids()
            .call()
            .await
            .map_err(|e| OperatorError::RpcError {
                method: "pendingTaskIds".to_string(),
                reason: e.to_string(),
            })?;

        if pending_ids.is_empty() {
            return Ok(vec![]);
        }

        debug!(count = pending_ids.len(), "Fetching pending tasks");

        let mut tasks = Vec::with_capacity(pending_ids.len());

        for task_id in pending_ids {
            match self.fetch_task(task_id).await {
                Ok(Some(task)) => tasks.push(task),
                Ok(None)       => {}  // Already completed
                Err(e) => {
                    warn!(task_id = %task_id, error = %e, "Failed to fetch task details");
                }
            }
        }

        Ok(tasks)
    }

    async fn fetch_task(&self, task_id: U256) -> Result<Option<RawTask>> {
        let (task_type_raw, payload, civ_id, deadline_block, completed) = self
            .task_manager
            .get_task(task_id)
            .call()
            .await
            .map_err(|e| OperatorError::RpcError {
                method: "getTask".to_string(),
                reason: e.to_string(),
            })?;

        if completed {
            return Ok(None);
        }

        let task_type = TaskType::try_from(task_type_raw)?;

        Ok(Some(RawTask {
            task_id,
            task_type,
            payload        : payload.into(),
            created_block  : 0, // Not tracked separately — use deadline as proxy
            deadline_block,
            civ_id,
        }))
    }

    // ─────────────────────────────────────────────────────────
    //  Operator Registration Check
    // ─────────────────────────────────────────────────────────

    pub async fn is_operator_registered(&self, operator: Address) -> Result<bool> {
        self.task_manager
            .is_operator_registered(operator)
            .call()
            .await
            .map_err(|e| OperatorError::RpcError {
                method: "isOperatorRegistered".to_string(),
                reason: e.to_string(),
            }.into())
    }

    // ─────────────────────────────────────────────────────────
    //  Task Response Submission
    // ─────────────────────────────────────────────────────────

    /// Sign and submit a task response on-chain.
    pub async fn submit_task_response(&self, mut response: TaskResponse) -> Result<H256> {
        // Sign the response
        let sig = self.sign_response(&response).await?;
        response.signature = sig.into();
        response.operator  = self.operator_address();

        info!(
            task_id   = %response.task_id,
            task_type = response.task_type,
            proof_len = response.zk_proof.len(),
            "Submitting task response on-chain"
        );

        // Estimate gas
        let tx = self.task_manager.submit_task_response(
            response.task_id,
            response.task_type,
            response.result_payload.clone(),
            response.zk_proof.clone(),
            response.signature.clone(),
        );

        let gas_estimate = tx.estimate_gas().await.unwrap_or(U256::from(self.cfg.submit_gas_limit));
        let gas_limit    = gas_estimate * 120 / 100; // 20% buffer

        // Get current gas price and cap it
        let provider_ref = self.provider.as_ref();
        let gas_price    = provider_ref
            .get_gas_price()
            .await
            .unwrap_or(U256::from(1_000_000_000u64)); // 1 gwei fallback

        let max_gas = U256::from(self.cfg.max_gas_gwei) * U256::exp10(9);
        let gas_price = gas_price.min(max_gas);

        // Send transaction
        let pending_tx = tx
            .gas(gas_limit)
            .gas_price(gas_price)
            .send()
            .await
            .map_err(|e| OperatorError::TxFailed {
                tx_hash: "pending".to_string(),
                reason : e.to_string(),
            })?;

        let tx_hash = *pending_tx;

        // Wait for confirmation
        match pending_tx.await {
            Ok(Some(receipt)) => {
                if receipt.status == Some(1u64.into()) {
                    info!(
                        tx_hash = %tx_hash,
                        gas_used = ?receipt.gas_used,
                        block    = ?receipt.block_number,
                        "Task response confirmed ✓"
                    );
                    Ok(tx_hash)
                } else {
                    Err(OperatorError::TxReverted(tx_hash.to_string()).into())
                }
            }
            Ok(None) => {
                warn!(tx_hash = %tx_hash, "Transaction dropped from mempool");
                Err(OperatorError::TxFailed {
                    tx_hash: tx_hash.to_string(),
                    reason : "Transaction dropped".to_string(),
                }.into())
            }
            Err(e) => Err(OperatorError::TxFailed {
                tx_hash: tx_hash.to_string(),
                reason : e.to_string(),
            }.into()),
        }
    }

    // ─────────────────────────────────────────────────────────
    //  Signing
    // ─────────────────────────────────────────────────────────

    /// Sign keccak256(task_id_bytes32 || result_payload)
    async fn sign_response(&self, response: &TaskResponse) -> Result<Vec<u8>> {
        use ethers::utils::keccak256;

        let mut msg = [0u8; 32];
        response.task_id.to_big_endian(&mut msg);

        let mut payload = msg.to_vec();
        payload.extend_from_slice(&response.result_payload);

        let hash = keccak256(&payload);

        let signature = self
            .operator_wallet
            .sign_message(hash)
            .await
            .map_err(|e| OperatorError::SigningFailed(e.to_string()))?;

        Ok(signature.to_vec())
    }
}
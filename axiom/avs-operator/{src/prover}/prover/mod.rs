//! Prover Worker
//!
//! Generates EZKL ZK proofs of AI inference results.
//! Each proof proves: "Given this game state, the model output this action"
//! without revealing the model weights.
//!
//! The proof is submitted on-chain to AIVerifier.sol.
//! If verification passes, the action is executed autonomously.

use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use eyre::Result;
use tracing::{debug, info, warn};

use crate::errors::OperatorError;

// ─────────────────────────────────────────────────────────────
//  Prover Worker
// ─────────────────────────────────────────────────────────────

pub struct ProverWorker {
    circuit_path     : String,
    proving_key_path : String,
    timeout_secs     : u64,
}

impl ProverWorker {
    pub fn new(
        circuit_path     : &str,
        proving_key_path : &str,
        timeout_secs     : u64,
    ) -> Self {
        Self {
            circuit_path    : circuit_path.to_string(),
            proving_key_path: proving_key_path.to_string(),
            timeout_secs,
        }
    }

    /// Generate a ZK proof for a given (state_history, action) pair.
    ///
    /// Steps:
    ///   1. Write witness input JSON
    ///   2. Call `ezkl gen-witness` (via CLI or Python subprocess)
    ///   3. Call `ezkl prove`
    ///   4. Read and return proof bytes
    ///   5. Optionally verify locally before returning
    pub fn generate_proof(
        &self,
        state_history : &[f32],
        action        : u8,
    ) -> Result<Vec<u8>> {
        // Validate circuit files exist
        if !Path::new(&self.circuit_path).exists() {
            return Err(OperatorError::CircuitNotFound(self.circuit_path.clone()).into());
        }
        if !Path::new(&self.proving_key_path).exists() {
            return Err(OperatorError::ProvingKeyNotFound(self.proving_key_path.clone()).into());
        }

        let started = Instant::now();
        info!(
            action       = action,
            state_len    = state_history.len(),
            circuit      = %self.circuit_path,
            "Generating ZK proof"
        );

        // ── Step 1: Write witness input ───────────────────────
        let witness_path = self.write_witness_input(state_history)?;

        // ── Step 2: Generate witness ──────────────────────────
        let witness_out_path = format!("{witness_path}.witness.json");
        self.run_ezkl_gen_witness(&witness_path, &witness_out_path)?;

        // ── Step 3: Prove ─────────────────────────────────────
        let proof_path = format!("{witness_path}.proof.json");
        self.run_ezkl_prove(&witness_out_path, &proof_path)?;

        // ── Step 4: Read proof bytes ──────────────────────────
        let proof_bytes = std::fs::read(&proof_path)
            .map_err(|e| OperatorError::ProofFailed(
                format!("Failed to read proof file: {e}")
            ))?;

        // ── Step 5: Local verify ──────────────────────────────
        self.verify_locally(&proof_path)?;

        let elapsed = started.elapsed();
        info!(
            action     = action,
            proof_size = proof_bytes.len(),
            elapsed_ms = elapsed.as_millis(),
            "ZK proof generated and verified locally ✓"
        );

        // Cleanup temp files
        let _ = std::fs::remove_file(&witness_path);
        let _ = std::fs::remove_file(&witness_out_path);
        let _ = std::fs::remove_file(&proof_path);

        Ok(proof_bytes)
    }

    // ─────────────────────────────────────────────────────────
    //  Step 1: Write witness JSON
    // ─────────────────────────────────────────────────────────

    fn write_witness_input(&self, state_history: &[f32]) -> Result<String> {
        use std::io::Write;

        let tmp_path = format!("/tmp/axiom-witness-{}.json", uuid::Uuid::new_v4());

        // EZKL witness format: {"input_data": [[f32 values...]]}
        let witness_json = serde_json::json!({
            "input_data": [state_history.iter().map(|&f| f).collect::<Vec<f32>>()],
        });

        let mut file = std::fs::File::create(&tmp_path)
            .map_err(|e| OperatorError::ProofFailed(
                format!("Failed to create witness file: {e}")
            ))?;
        file.write_all(serde_json::to_string(&witness_json)?.as_bytes())?;

        debug!(path = %tmp_path, "Witness input written");
        Ok(tmp_path)
    }

    // ─────────────────────────────────────────────────────────
    //  Step 2: ezkl gen-witness
    // ─────────────────────────────────────────────────────────

    fn run_ezkl_gen_witness(
        &self,
        input_path  : &str,
        output_path : &str,
    ) -> Result<()> {
        debug!("Running: ezkl gen-witness");

        let output = Command::new("ezkl")
            .args([
                "gen-witness",
                "--data",             input_path,
                "--compiled-circuit", &self.circuit_path,
                "--output",           output_path,
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .map_err(|e| OperatorError::ProofFailed(
                format!("ezkl gen-witness failed to start: {e} — is ezkl installed?")
            ))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(OperatorError::ProofFailed(
                format!("ezkl gen-witness failed:\n{stderr}")
            ).into());
        }

        Ok(())
    }

    // ─────────────────────────────────────────────────────────
    //  Step 3: ezkl prove
    // ─────────────────────────────────────────────────────────

    fn run_ezkl_prove(
        &self,
        witness_path : &str,
        proof_path   : &str,
    ) -> Result<()> {
        debug!("Running: ezkl prove");

        let output = Command::new("ezkl")
            .args([
                "prove",
                "--witness",          witness_path,
                "--compiled-circuit", &self.circuit_path,
                "--pk-path",          &self.proving_key_path,
                "--proof-path",       proof_path,
                "--proof-type",       "single",
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .map_err(|e| OperatorError::ProofFailed(
                format!("ezkl prove failed to start: {e}")
            ))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(OperatorError::ProofFailed(
                format!("ezkl prove failed:\n{stderr}")
            ).into());
        }

        Ok(())
    }

    // ─────────────────────────────────────────────────────────
    //  Step 5: Local verify before submitting
    // ─────────────────────────────────────────────────────────

    fn verify_locally(&self, proof_path: &str) -> Result<()> {
        // Derive paths from circuit_path
        let settings_path = self.circuit_path.replace(".ezkl", "settings.json");
        let vk_path       = self.proving_key_path.replace("pk.key", "vk.key");

        if !Path::new(&vk_path).exists() {
            warn!("vk.key not found — skipping local verification");
            return Ok(());
        }

        debug!("Running: ezkl verify");

        let output = Command::new("ezkl")
            .args([
                "verify",
                "--proof-path",   proof_path,
                "--settings-path",&settings_path,
                "--vk-path",      &vk_path,
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .map_err(|e| OperatorError::ProofFailed(
                format!("ezkl verify failed to start: {e}")
            ))?;

        if !output.status.success() {
            return Err(OperatorError::ProofInvalid.into());
        }

        debug!("Local proof verification passed ✓");
        Ok(())
    }
}

// ─────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_prover_missing_circuit() {
        let prover = ProverWorker::new(
            "/nonexistent/circuit.ezkl",
            "/nonexistent/pk.key",
            60,
        );
        let state = vec![0.0f32; 256]; // 8 * 32
        let result = prover.generate_proof(&state, 0);
        assert!(result.is_err(), "Should fail with missing circuit");
        let err = result.unwrap_err().to_string();
        assert!(err.contains("not found") || err.contains("Circuit"),
            "Error should mention missing circuit: {err}");
    }

    #[test]
    fn test_witness_write_read() {
        let prover = ProverWorker::new("x.ezkl", "pk.key", 60);
        let state  = vec![0.5f32; 32];
        let path   = prover.write_witness_input(&state).unwrap();
        assert!(Path::new(&path).exists(), "Witness file should be created");

        let contents = std::fs::read_to_string(&path).unwrap();
        let json: serde_json::Value = serde_json::from_str(&contents).unwrap();
        let data = &json["input_data"][0];
        assert_eq!(data.as_array().unwrap().len(), 32);

        let _ = std::fs::remove_file(&path);
    }
}
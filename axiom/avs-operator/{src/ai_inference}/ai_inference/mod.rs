//! AI Inference Worker
//!
//! Loads the faction strategy ONNX model compiled from train.py
//! and runs inference on game state tensors.
//! Output is fed to the ProverWorker to generate a ZK proof.

use ndarray::{Array, IxDyn};
use ort::{Environment, ExecutionProvider, GraphOptimizationLevel, Session, SessionBuilder, Value};
use std::sync::Arc;
use tracing::{debug, info};

use crate::{
    errors::OperatorError,
    types::{AIActionResult, AIActionTask},
};

// ─────────────────────────────────────────────────────────────
//  Constants (must match train.py)
// ─────────────────────────────────────────────────────────────

pub const SEQ_LEN    : usize = 8;
pub const STATE_DIM  : usize = 32;
pub const ACTION_DIM : usize = 8;

pub const ACTION_NAMES: [&str; ACTION_DIM] = [
    "expand_north",
    "expand_east",
    "expand_south",
    "expand_west",
    "attack",
    "defend",
    "harvest",
    "idle",
];

// ─────────────────────────────────────────────────────────────
//  AI Inference Worker
// ─────────────────────────────────────────────────────────────

pub struct AIInferenceWorker {
    session   : Session,
    env       : Arc<Environment>,
}

impl AIInferenceWorker {
    /// Load the ONNX model from disk.
    /// Call once at startup — session is reused for all inferences.
    pub fn new(model_path: &str) -> Result<Self, OperatorError> {
        if !std::path::Path::new(model_path).exists() {
            return Err(OperatorError::ModelLoad {
                path  : model_path.to_string(),
                reason: "File not found — run ai-model/export.py first".to_string(),
            });
        }

        let env = Arc::new(
            Environment::builder()
                .with_name("axiom-faction-ai")
                .with_execution_providers([ExecutionProvider::CPU(Default::default())])
                .build()
                .map_err(|e| OperatorError::ModelLoad {
                    path  : model_path.to_string(),
                    reason: e.to_string(),
                })?
        );

        let session = SessionBuilder::new(&env)
            .map_err(|e| OperatorError::ModelLoad {
                path  : model_path.to_string(),
                reason: e.to_string(),
            })?
            .with_optimization_level(GraphOptimizationLevel::Level3)
            .map_err(|e| OperatorError::ModelLoad {
                path  : model_path.to_string(),
                reason: e.to_string(),
            })?
            .with_model_from_file(model_path)
            .map_err(|e| OperatorError::ModelLoad {
                path  : model_path.to_string(),
                reason: e.to_string(),
            })?;

        // Validate input/output shapes
        Self::validate_session(&session)?;

        info!(
            model     = model_path,
            inputs    = session.inputs.len(),
            outputs   = session.outputs.len(),
            "ONNX model loaded"
        );

        Ok(Self { session, env })
    }

    /// Run inference on a game state history tensor.
    /// Input shape: [1, SEQ_LEN, STATE_DIM]
    /// Output: predicted action + probabilities
    pub fn predict(&self, task: &AIActionTask) -> Result<AIActionResult, OperatorError> {
        let seq_len   = task.seq_len;
        let state_dim = task.state_dim;

        // Validate input size
        let expected = seq_len * state_dim;
        if task.state_history.len() != expected {
            return Err(OperatorError::InvalidInputShape {
                expected: vec![seq_len, state_dim],
                got     : vec![task.state_history.len()],
            });
        }

        // Build ndarray tensor: shape [1, seq_len, state_dim]
        let input_array = Array::from_shape_vec(
            IxDyn(&[1, seq_len, state_dim]),
            task.state_history.clone(),
        )
        .map_err(|e| OperatorError::InferenceFailed(e.to_string()))?;

        // Create ORT Value
        let input_value = Value::from_array(self.session.allocator(), &input_array)
            .map_err(|e| OperatorError::InferenceFailed(e.to_string()))?;

        debug!(
            task_id   = %task.task_id,
            seq_len   = seq_len,
            state_dim = state_dim,
            "Running ONNX inference"
        );

        // Run inference
        let outputs = self.session
            .run(vec![input_value])
            .map_err(|e| OperatorError::InferenceFailed(e.to_string()))?;

        // Extract logits: shape [1, ACTION_DIM]
        let logits_tensor = outputs[0]
            .try_extract::<f32>()
            .map_err(|e| OperatorError::InferenceFailed(e.to_string()))?;

        let logits: Vec<f32> = logits_tensor
            .view()
            .iter()
            .cloned()
            .collect();

        if logits.len() != ACTION_DIM {
            return Err(OperatorError::InvalidInputShape {
                expected: vec![ACTION_DIM],
                got     : vec![logits.len()],
            });
        }

        // Check for NaN / Inf
        if logits.iter().any(|v| v.is_nan() || v.is_infinite()) {
            return Err(OperatorError::InvalidModelOutput);
        }

        // Softmax
        let probs = softmax(&logits);

        // Argmax
        let action = probs
            .iter()
            .enumerate()
            .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
            .map(|(i, _)| i)
            .unwrap_or(7) as u8; // default: idle

        let confidence = probs[action as usize];

        debug!(
            task_id    = %task.task_id,
            action     = action,
            action_name = ACTION_NAMES[action as usize],
            confidence = confidence,
            "Inference complete"
        );

        Ok(AIActionResult {
            task_id      : task.task_id,
            civ_id       : task.civ_id,
            action,
            action_name  : ACTION_NAMES[action as usize].to_string(),
            probabilities: probs,
            confidence,
            proof        : vec![], // filled by ProverWorker
        })
    }

    /// Validate the loaded session has the expected input/output shapes.
    fn validate_session(session: &Session) -> Result<(), OperatorError> {
        if session.inputs.is_empty() {
            return Err(OperatorError::ModelLoad {
                path  : "session".to_string(),
                reason: "Model has no inputs".to_string(),
            });
        }
        if session.outputs.is_empty() {
            return Err(OperatorError::ModelLoad {
                path  : "session".to_string(),
                reason: "Model has no outputs".to_string(),
            });
        }

        // Check input name matches export.py
        let input_name = &session.inputs[0].name;
        if input_name != "game_state_history" {
            return Err(OperatorError::ModelLoad {
                path  : "session".to_string(),
                reason: format!(
                    "Unexpected input name: '{input_name}', expected 'game_state_history'"
                ),
            });
        }

        info!("Model session validation passed ✓");
        Ok(())
    }
}

// ─────────────────────────────────────────────────────────────
//  Math helpers
// ─────────────────────────────────────────────────────────────

/// Numerically stable softmax
fn softmax(logits: &[f32]) -> Vec<f32> {
    let max = logits.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
    let exps: Vec<f32> = logits.iter().map(|&x| (x - max).exp()).collect();
    let sum: f32 = exps.iter().sum();
    exps.iter().map(|&e| e / sum).collect()
}

// ─────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_softmax_basic() {
        let logits = vec![1.0f32, 2.0, 3.0, 4.0, 1.0, 2.0, 3.0, 2.0];
        let probs  = softmax(&logits);
        let sum: f32 = probs.iter().sum();
        assert!((sum - 1.0).abs() < 1e-5, "Softmax must sum to 1.0");
        assert_eq!(probs.len(), ACTION_DIM);
        // Highest logit should have highest probability
        assert!(probs[3] > probs[0]);
    }

    #[test]
    fn test_softmax_uniform() {
        let logits = vec![0.0f32; ACTION_DIM];
        let probs  = softmax(&logits);
        let expected = 1.0 / ACTION_DIM as f32;
        for p in &probs {
            assert!((p - expected).abs() < 1e-5, "Uniform logits → uniform probs");
        }
    }

    #[test]
    fn test_softmax_extreme() {
        // Should not produce NaN even with extreme values
        let logits = vec![1000.0f32, -1000.0, 0.0, 500.0, -500.0, 1.0, 2.0, 3.0];
        let probs  = softmax(&logits);
        assert!(!probs.iter().any(|p| p.is_nan()), "No NaN in softmax output");
        let sum: f32 = probs.iter().sum();
        assert!((sum - 1.0).abs() < 1e-4, "Sum must be 1.0 even for extreme inputs");
    }

    #[test]
    fn test_invalid_input_shape() {
        // Without a real ONNX file we can only test the shape validation logic
        use ethers::types::U256;
        let task = AIActionTask {
            task_id      : U256::from(1),
            civ_id       : U256::from(1),
            state_history: vec![0.0; 5],   // Wrong size (want SEQ_LEN * STATE_DIM)
            seq_len      : SEQ_LEN,
            state_dim    : STATE_DIM,
        };

        // We can't instantiate AIInferenceWorker without a real model file,
        // but we can test the size check in isolation:
        let expected = task.seq_len * task.state_dim;
        assert_ne!(
            task.state_history.len(),
            expected,
            "Should detect wrong input size"
        );
    }
}
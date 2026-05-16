"""
AXIOM — PyTorch → ONNX Export
==============================
Loads the trained FactionStrategyNet and exports it to ONNX format.
ONNX is the bridge between PyTorch training and EZKL ZK compilation.

Must run AFTER train.py completes.

Usage:
    source .venv/bin/activate
    python export.py

Outputs:
    model.onnx        ← EZKL input
    sample_input.json ← Sample witness for EZKL calibration
"""

import json
import sys
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import torch
import torch.nn as nn
from onnxsim import simplify

# Import model definition from train.py
sys.path.insert(0, str(Path(__file__).parent))
from train import (
    ACTION_DIM,
    ACTION_NAMES,
    FEATURE_NAMES,
    HIDDEN_DIM,
    NUM_HEADS,
    NUM_LAYERS,
    SEQ_LEN,
    STATE_DIM,
    FactionStrategyNet,
)


# ─────────────────────────────────────────────
#  Config
# ─────────────────────────────────────────────

MODEL_CHECKPOINT = "faction_model.pt"
ONNX_OUTPUT = "model.onnx"
SAMPLE_INPUT_JSON = "sample_input.json"
ONNX_OPSET = 17       # EZKL supports up to opset 17


# ─────────────────────────────────────────────
#  Load Checkpoint
# ─────────────────────────────────────────────

def load_model(checkpoint_path: str) -> FactionStrategyNet:
    """Load trained model from .pt checkpoint."""
    print(f"\n[1/5] Loading checkpoint: {checkpoint_path}")

    if not Path(checkpoint_path).exists():
        raise FileNotFoundError(
            f"Checkpoint not found: {checkpoint_path}\n"
            f"Run train.py first: python train.py"
        )

    checkpoint = torch.load(checkpoint_path, map_location="cpu")
    config = checkpoint.get("config", {})

    model = FactionStrategyNet(
        state_dim=config.get("state_dim", STATE_DIM),
        action_dim=config.get("action_dim", ACTION_DIM),
        hidden_dim=config.get("hidden_dim", HIDDEN_DIM),
        seq_len=config.get("seq_len", SEQ_LEN),
        num_heads=NUM_HEADS,
        num_layers=NUM_LAYERS,
    )
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()

    epoch = checkpoint.get("epoch", "?")
    val_acc = checkpoint.get("val_acc", 0.0)
    print(f"      Loaded epoch {epoch} | val_acc={val_acc:.4f}")
    print(f"      Parameters: {sum(p.numel() for p in model.parameters()):,}")

    return model


# ─────────────────────────────────────────────
#  ONNX Export
# ─────────────────────────────────────────────

def export_onnx(model: FactionStrategyNet, output_path: str) -> None:
    """Export model to ONNX with EZKL-compatible settings."""
    print(f"\n[2/5] Exporting to ONNX (opset {ONNX_OPSET})...")

    # Dummy input — shape (batch=1, seq_len, state_dim)
    dummy_input = torch.randn(1, SEQ_LEN, STATE_DIM)

    torch.onnx.export(
        model,
        dummy_input,
        output_path,
        export_params=True,
        opset_version=ONNX_OPSET,
        do_constant_folding=True,     # Fold constants for smaller graph
        input_names=["game_state_history"],
        output_names=["action_logits"],
        dynamic_axes={
            # EZKL works best with fixed batch size = 1
            # Do NOT make batch dynamic
        },
        verbose=False,
    )
    print(f"      Exported → {output_path}")


# ─────────────────────────────────────────────
#  Simplify ONNX Graph
# ─────────────────────────────────────────────

def simplify_onnx(onnx_path: str) -> None:
    """
    Simplify the ONNX graph using onnxsim.
    Fewer ops = smaller ZK circuit = faster proving time.
    """
    print(f"\n[3/5] Simplifying ONNX graph...")

    model_onnx = onnx.load(onnx_path)

    # Check model is valid before simplifying
    try:
        onnx.checker.check_model(model_onnx)
        print("      ONNX model is valid ✓")
    except onnx.checker.ValidationError as e:
        print(f"      ONNX validation warning: {e}")

    # Simplify
    model_simplified, check = simplify(model_onnx)

    if check:
        onnx.save(model_simplified, onnx_path)
        orig_nodes = len(model_onnx.graph.node)
        simp_nodes = len(model_simplified.graph.node)
        print(f"      Simplified: {orig_nodes} → {simp_nodes} nodes")
    else:
        print("      Simplification check failed — keeping original graph")

    # Print graph summary
    print(f"\n      Graph inputs:")
    for inp in model_simplified.graph.input:
        shape = [d.dim_value for d in inp.type.tensor_type.shape.dim]
        print(f"        {inp.name}: {shape}")

    print(f"\n      Graph outputs:")
    for out in model_simplified.graph.output:
        shape = [d.dim_value for d in out.type.tensor_type.shape.dim]
        print(f"        {out.name}: {shape}")


# ─────────────────────────────────────────────
#  Validate with ONNX Runtime
# ─────────────────────────────────────────────

def validate_onnx(
    model: FactionStrategyNet,
    onnx_path: str,
    n_samples: int = 10,
    tol: float = 1e-4,
) -> None:
    """
    Run PyTorch and ONNX inference on same inputs.
    Assert outputs match within tolerance.
    """
    print(f"\n[4/5] Validating ONNX output vs PyTorch ({n_samples} samples)...")

    ort_session = ort.InferenceSession(
        onnx_path,
        providers=["CPUExecutionProvider"],
    )

    max_diff = 0.0
    for i in range(n_samples):
        test_input = torch.randn(1, SEQ_LEN, STATE_DIM)

        # PyTorch inference
        with torch.no_grad():
            pt_output = model(test_input).numpy()

        # ONNX Runtime inference
        ort_inputs = {"game_state_history": test_input.numpy()}
        ort_output = ort_session.run(None, ort_inputs)[0]

        diff = np.abs(pt_output - ort_output).max()
        max_diff = max(max_diff, diff)

    if max_diff < tol:
        print(f"      Outputs match ✓ (max_diff={max_diff:.6f} < {tol})")
    else:
        print(f"      ⚠ Output mismatch: max_diff={max_diff:.6f} > {tol}")
        print(f"        This may cause issues in EZKL — check model ops.")


# ─────────────────────────────────────────────
#  Generate Sample Input for EZKL Calibration
# ─────────────────────────────────────────────

def generate_sample_input(output_path: str, n_calibration: int = 20) -> None:
    """
    EZKL requires a sample_input.json for calibration.
    This sets the scale and quantization of the ZK circuit.
    More diverse samples = better calibration.
    """
    print(f"\n[5/5] Generating EZKL calibration inputs...")

    # Generate diverse game state scenarios
    scenarios = []

    # Aggressive faction (high territory, high threat)
    for _ in range(n_calibration // 4):
        state = np.random.rand(SEQ_LEN, STATE_DIM).astype(np.float32)
        state[:, 4] = np.random.uniform(50, 100, SEQ_LEN)   # high territory
        state[:, 9] = np.random.uniform(0.6, 1.0, SEQ_LEN)  # high threat
        scenarios.append(state)

    # Defensive faction (low territory, low energy)
    for _ in range(n_calibration // 4):
        state = np.random.rand(SEQ_LEN, STATE_DIM).astype(np.float32)
        state[:, 4] = np.random.uniform(1, 20, SEQ_LEN)     # low territory
        state[:, 5] = np.random.uniform(0, 200, SEQ_LEN)    # low energy
        scenarios.append(state)

    # Balanced faction (mid values)
    for _ in range(n_calibration // 2):
        state = np.random.rand(SEQ_LEN, STATE_DIM).astype(np.float32)
        scenarios.append(state)

    # EZKL expects format: {"input_data": [[flat_tensor_values], ...]}
    # Each entry is a flattened (seq_len * state_dim,) vector
    input_data = [s.flatten().tolist() for s in scenarios]

    sample = {
        "input_data": input_data,
        "input_shapes": [[SEQ_LEN, STATE_DIM]],
        "output_shapes": [[ACTION_DIM]],
    }

    with open(output_path, "w") as f:
        json.dump(sample, f)

    print(f"      {len(scenarios)} calibration samples → {output_path}")


# ─────────────────────────────────────────────
#  Entry Point
# ─────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  AXIOM — PyTorch → ONNX Export Pipeline")
    print("=" * 60)

    # Load trained model
    model = load_model(MODEL_CHECKPOINT)

    # Export to ONNX
    export_onnx(model, ONNX_OUTPUT)

    # Simplify graph
    simplify_onnx(ONNX_OUTPUT)

    # Validate correctness
    validate_onnx(model, ONNX_OUTPUT)

    # Generate EZKL calibration data
    generate_sample_input(SAMPLE_INPUT_JSON)

    # Final summary
    onnx_size = Path(ONNX_OUTPUT).stat().st_size / 1024
    print("\n" + "=" * 60)
    print("  Export complete!")
    print(f"  model.onnx      : {onnx_size:.1f} KB")
    print(f"  sample_input.json ready for EZKL calibration")
    print("\n  Next step → run: python ezkl_compile.py")
    print("=" * 60 + "\n")


if __name__ == "__main__":
    main()
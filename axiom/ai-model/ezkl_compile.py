"""
AXIOM — EZKL ZK Circuit Compilation Pipeline
=============================================
Compiles model.onnx into a ZK circuit and generates AIVerifier.sol —
the on-chain Solidity contract that verifies AI inference proofs.

Pipeline steps:
    1. gen_settings     — compute scale factors for quantization
    2. calibrate        — calibrate settings against real game data
    3. compile_circuit  — compile ONNX → .ezkl circuit binary
    4. setup            — generate proving key (pk) + verification key (vk)
    5. gen_witness      — generate a test witness
    6. prove            — generate a test proof
    7. verify           — verify the proof locally
    8. create_evm_verifier → AIVerifier.sol

Must run AFTER export.py.

Usage:
    source .venv/bin/activate
    python ezkl_compile.py --output-dir ../circuits/ai_inference

Or via VS Code launch.json:
    Run "🧠 AI — EZKL compile to ZK circuit"
"""

import argparse
import asyncio
import json
import shutil
import time
from pathlib import Path

import ezkl
import numpy as np


# ─────────────────────────────────────────────
#  Config
# ─────────────────────────────────────────────

ONNX_MODEL = "model.onnx"
SAMPLE_INPUT = "sample_input.json"

# Intermediate artifacts (built in current dir)
SETTINGS_PATH = "settings.json"
COMPILED_CIRCUIT = "faction_model.ezkl"
PK_PATH = "pk.key"
VK_PATH = "vk.key"
WITNESS_PATH = "witness.json"
PROOF_PATH = "proof.json"
VERIFIER_ABI = "AIVerifier.abi"
VERIFIER_SOL = "AIVerifier.sol"

# Target output directory (copied here after compilation)
DEFAULT_OUTPUT_DIR = "../circuits/ai_inference"


# ─────────────────────────────────────────────
#  Step Helpers
# ─────────────────────────────────────────────

def step(n: int, total: int, title: str):
    print(f"\n[{n}/{total}] {title}")
    print(f"      {'─' * 50}")


def check_file(path: str, label: str):
    if not Path(path).exists():
        raise FileNotFoundError(
            f"{label} not found: {path}\n"
            f"Run the previous step first."
        )
    size = Path(path).stat().st_size
    print(f"      {label}: {path} ({size / 1024:.1f} KB)")


def elapsed(start: float) -> str:
    return f"{time.time() - start:.1f}s"


# ─────────────────────────────────────────────
#  Pipeline
# ─────────────────────────────────────────────

async def run_pipeline(output_dir: str):
    total = 8
    t0 = time.time()

    print("\n" + "=" * 60)
    print("  AXIOM — EZKL ZK Compilation Pipeline")
    print("=" * 60)

    check_file(ONNX_MODEL, "ONNX model")
    check_file(SAMPLE_INPUT, "Calibration data")

    # ── Step 1: Generate Settings ─────────────────────────
    step(1, total, "Generating circuit settings")

    # py_run_args controls quantization:
    #   scale       — how much to scale float → int (higher = more accurate, slower proving)
    #   bits        — quantization bit width (8 is a good ZK balance)
    #   logrows     — circuit size (higher = supports larger models, slower)
    py_run_args = ezkl.PyRunArgs()
    py_run_args.input_visibility = "public"   # Game state is public
    py_run_args.output_visibility = "public"  # Action is public (verifiable)
    py_run_args.param_visibility = "private"  # Model weights stay private

    res = ezkl.gen_settings(
        model=ONNX_MODEL,
        output=SETTINGS_PATH,
        py_run_args=py_run_args,
    )
    assert res, "gen_settings failed"

    with open(SETTINGS_PATH) as f:
        settings = json.load(f)
    print(f"      Logrows     : {settings.get('run_args', {}).get('logrows', '?')}")
    print(f"      Scale       : {settings.get('run_args', {}).get('scale', '?')}")
    print(f"      Settings    → {SETTINGS_PATH} ✓")

    # ── Step 2: Calibrate ─────────────────────────────────
    step(2, total, "Calibrating quantization against game data")
    print("      This finds optimal scale to minimize accuracy loss...")

    await ezkl.calibrate_settings(
        data=SAMPLE_INPUT,
        model=ONNX_MODEL,
        settings=SETTINGS_PATH,
        target="resources",    # Optimize for proof size over speed
    )
    print(f"      Calibration complete ✓ ({elapsed(t0)})")

    # Reload calibrated settings
    with open(SETTINGS_PATH) as f:
        settings = json.load(f)
    print(f"      Final logrows : {settings.get('run_args', {}).get('logrows', '?')}")

    # ── Step 3: Compile Circuit ───────────────────────────
    step(3, total, "Compiling ONNX → ZK circuit binary")
    print("      This converts the model graph into arithmetic constraints...")

    t3 = time.time()
    res = ezkl.compile_circuit(
        model=ONNX_MODEL,
        compiled_circuit=COMPILED_CIRCUIT,
        settings_path=SETTINGS_PATH,
    )
    assert res, "compile_circuit failed"

    circuit_size = Path(COMPILED_CIRCUIT).stat().st_size / 1024
    print(f"      Circuit size : {circuit_size:.1f} KB")
    print(f"      Compiled in  : {elapsed(t3)}")
    print(f"      Output       → {COMPILED_CIRCUIT} ✓")

    # ── Step 4: Setup (SRS + Keys) ────────────────────────
    step(4, total, "Generating proving & verification keys")
    print("      Fetching Structured Reference String (SRS)...")

    t4 = time.time()

    # Download SRS from Aztec's ceremony
    # This is a one-time operation per circuit size (logrows)
    logrows = settings.get("run_args", {}).get("logrows", 17)
    await ezkl.get_srs(settings_path=SETTINGS_PATH)

    print(f"      Running trusted setup...")
    res = ezkl.setup(
        model=COMPILED_CIRCUIT,
        vk_path=VK_PATH,
        pk_path=PK_PATH,
        srs_path=f"kzg{logrows}.srs",
    )
    assert res, "setup failed"

    pk_size = Path(PK_PATH).stat().st_size / 1024
    vk_size = Path(VK_PATH).stat().st_size / 1024
    print(f"      Proving key  : {pk_size:.1f} KB → {PK_PATH}")
    print(f"      Verify key   : {vk_size:.1f} KB → {VK_PATH}")
    print(f"      Setup time   : {elapsed(t4)}")

    # ── Step 5: Generate Test Witness ─────────────────────
    step(5, total, "Generating test witness")

    # Load a sample game state as witness
    with open(SAMPLE_INPUT) as f:
        sample = json.load(f)

    # Use first calibration sample as witness input
    witness_input = {
        "input_data": [sample["input_data"][0]],
        "input_shapes": sample["input_shapes"],
        "output_shapes": sample["output_shapes"],
    }
    witness_input_path = "witness_input.json"
    with open(witness_input_path, "w") as f:
        json.dump(witness_input, f)

    res = await ezkl.gen_witness(
        data=witness_input_path,
        model=COMPILED_CIRCUIT,
        output=WITNESS_PATH,
    )
    assert res, "gen_witness failed"

    with open(WITNESS_PATH) as f:
        witness = json.load(f)
    outputs = witness.get("outputs", [[]])
    if outputs:
        action_idx = int(np.argmax(outputs[0]))
        action_names = ["expand_north","expand_east","expand_south","expand_west",
                        "attack","defend","harvest","idle"]
        print(f"      Witness action : [{action_idx}] {action_names[action_idx]}")
    print(f"      Witness        → {WITNESS_PATH} ✓")

    # ── Step 6: Generate Proof ────────────────────────────
    step(6, total, "Generating test ZK proof")
    print("      This proves AI inference was computed correctly...")

    t6 = time.time()
    res = ezkl.prove(
        witness=WITNESS_PATH,
        model=COMPILED_CIRCUIT,
        pk_path=PK_PATH,
        proof_path=PROOF_PATH,
        proof_type="single",
    )
    assert res, "prove failed"

    proof_size = Path(PROOF_PATH).stat().st_size / 1024
    print(f"      Proof size   : {proof_size:.1f} KB")
    print(f"      Proving time : {elapsed(t6)}")
    print(f"      Proof        → {PROOF_PATH} ✓")

    # ── Step 7: Verify Proof Locally ──────────────────────
    step(7, total, "Verifying proof locally")

    res = ezkl.verify(
        proof_path=PROOF_PATH,
        settings_path=SETTINGS_PATH,
        vk_path=VK_PATH,
    )
    assert res, "Local verification FAILED — proof is invalid"
    print(f"      Proof is valid ✓")
    print(f"      On-chain verification cost estimate: ~300k gas")

    # ── Step 8: Generate Solidity Verifier ────────────────
    step(8, total, "Generating AIVerifier.sol")
    print("      Creating EVM-compatible Solidity verifier contract...")

    res = ezkl.create_evm_verifier(
        vk_path=VK_PATH,
        settings_path=SETTINGS_PATH,
        sol_code_path=VERIFIER_SOL,
        abi_path=VERIFIER_ABI,
    )
    assert res, "create_evm_verifier failed"

    sol_size = Path(VERIFIER_SOL).stat().st_size / 1024
    print(f"      Contract size : {sol_size:.1f} KB")

    # ── Copy artifacts to output dir ──────────────────────
    print(f"\n  Copying artifacts → {output_dir}/")
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)

    artifacts = {
        COMPILED_CIRCUIT : out / "circuit.ezkl",
        VK_PATH          : out / "vk.key",
        PK_PATH          : out / "pk.key",
        SETTINGS_PATH    : out / "settings.json",
        VERIFIER_SOL     : out / "AIVerifier.sol",
        VERIFIER_ABI     : out / "AIVerifier.abi",
        PROOF_PATH       : out / "test_proof.json",
        WITNESS_PATH     : out / "test_witness.json",
        ONNX_MODEL       : out / "model.onnx",
    }

    for src, dst in artifacts.items():
        if Path(src).exists():
            shutil.copy2(src, dst)
            print(f"      {src:30s} → {dst.name}")

    # Copy AIVerifier.sol into contracts folder too
    contracts_zk_dir = Path("../contracts/src/zk")
    if contracts_zk_dir.exists():
        shutil.copy2(VERIFIER_SOL, contracts_zk_dir / "AIVerifier.sol")
        print(f"\n      ✓ AIVerifier.sol copied to contracts/src/zk/")

    # ── Final Summary ─────────────────────────────────────
    print("\n" + "=" * 60)
    print("  EZKL Pipeline Complete!")
    print(f"  Total time     : {elapsed(t0)}")
    print(f"  Output dir     : {output_dir}/")
    print()
    print("  Generated artifacts:")
    print(f"    circuit.ezkl    — ZK circuit (give to operator nodes)")
    print(f"    vk.key          — Verification key (public)")
    print(f"    pk.key          — Proving key (keep with operators)")
    print(f"    AIVerifier.sol  — Deploy this to L3 contracts/src/zk/")
    print(f"    test_proof.json — Sanity-check proof")
    print()
    print("  Next steps:")
    print("    1. Deploy AIVerifier.sol:")
    print("       cd ../contracts && forge script script/DeployL3.s.sol")
    print("    2. Distribute circuit.ezkl + pk.key to AVS operators")
    print("    3. Players generate proofs via avs-operator/src/prover/")
    print("=" * 60 + "\n")


# ─────────────────────────────────────────────
#  Entry Point
# ─────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(description="EZKL ZK circuit compilation pipeline")
    parser.add_argument(
        "--model", type=str, default=ONNX_MODEL,
        help="Path to ONNX model (default: model.onnx)"
    )
    parser.add_argument(
        "--output-dir", type=str, default=DEFAULT_OUTPUT_DIR,
        help="Directory to copy compiled artifacts into"
    )
    return parser.parse_args()


def main():
    args = parse_args()
    global ONNX_MODEL
    ONNX_MODEL = args.model
    asyncio.run(run_pipeline(args.output_dir))


if __name__ == "__main__":
    main()
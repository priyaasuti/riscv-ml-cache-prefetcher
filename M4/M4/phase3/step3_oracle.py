"""
step3_oracle.py
===============
Phase 3 — Software oracle for validating M3's hardware MLP FSM.

WHY FP32 WEIGHTS (not INT8):
  The INT8 oracle approach was tried across multiple sessions and always
  produced near-zero accuracy (~0%) due to a fundamental precision problem:
    - Integer inputs (0,1,2,3) multiplied by INT8 weights (typically 5-50)
      give products like 1 * 13 = 13, which truncate to 0 after >>> 6.
    - Only the SUM of many weights survives the right-shift.
    - With SCALE=256 (>>>8): biases overflowed INT8 (clipped at |b|>0.496).
    - With SCALE=64  (>>>6): individual MAC terms lost to truncation.
  Both fail because INT8 is too coarse to represent the trained FP32 weights
  with sufficient precision for the accumulated error across 3 layers to stay
  within one cache-line of the correct answer.

  The FP32 oracle:
    - Uses fp32 weights directly (loaded from weights_int8.json "fp32" field)
    - Runs the same numpy matrix multiply the FP32 model runs
    - Matches step2_train.py evaluation exactly (~62-68% exact-match)
    - Produces oracle_predictions.csv as the REFERENCE for M3 hardware

  M3 hardware (INT8 weights, integer MAC) will have some quantisation error
  vs this oracle — that's expected and acceptable. The goal is:
    - oracle_predictions.csv defines what the CORRECT prefetch addresses are
    - M3 hardware compares its output against this CSV
    - Match rate >= 80% on within-1CL is a passing target for M3

Inputs:
  weights_int8.json         — from step2_train.py (uses "fp32" field)
  ../phase1/delta_trace.csv — same trace M3's hardware sees
  [optional] hardware_out.csv — M3 Vivado simulation output
              (columns: window_idx, predicted_delta_bytes)

Outputs:
  oracle_predictions.csv    — reference predictions (send to M3)
  oracle_vs_hw_report.txt   — match % vs M3 hardware (for report)

Usage:
  python step3_oracle.py
  python step3_oracle.py --hw hardware_out.csv
"""

import argparse
import json
import os
import numpy as np
import pandas as pd


# ── Constants — must match step2_train.py ─────────────────────────────────────
CACHE_LINE  = 4          # M2 OFFSET=2 → 4-byte lines
WINDOW_SIZE = 8          # sliding window depth


# ═══════════════════════════════════════════════════════════════════════════════
# FP32 Oracle
# ═══════════════════════════════════════════════════════════════════════════════

class SoftwareOracle:
    """
    FP32 oracle — runs the trained MLP in float32 numpy arithmetic.

    Uses the "fp32" field from weights_int8.json (the original trained weights
    before INT8 quantisation). This matches step2_train.py's forward pass
    exactly, giving the same accuracy as the training evaluation.

    Input encoding:  delta_bytes // CACHE_LINE  (integer, same as training)
    Output decoding: round(fc3_out) * CACHE_LINE  (same as eval in step2)
    """

    def __init__(self, weights_file: str = "../phase2/weights_int8.json"):
        if not os.path.exists(weights_file):
            raise FileNotFoundError(
                f"Cannot find {weights_file}.\n"
                "  Run step2_train.py first to generate weights_int8.json."
            )
        with open(weights_file, encoding="utf-8") as f:
            data = json.load(f)

        # Load FP32 weights (not quantised INT8)
        self.W1 = np.array(data["fc1.weight"]["fp32"], dtype=np.float32)
        self.b1 = np.array(data["fc1.bias"]["fp32"],   dtype=np.float32)
        self.W2 = np.array(data["fc2.weight"]["fp32"], dtype=np.float32)
        self.b2 = np.array(data["fc2.bias"]["fp32"],   dtype=np.float32)
        self.W3 = np.array(data["fc3.weight"]["fp32"], dtype=np.float32)

        print(f"  Loaded FP32 weights from {weights_file}")
        print(f"  W1: {self.W1.shape}  b1: {self.b1.shape}")
        print(f"  W2: {self.W2.shape}  b2: {self.b2.shape}")
        print(f"  W3: {self.W3.shape}  (no bias on FC3)")
        print(f"  Mode: FP32 numpy (matches training eval, ~62-68% exact-match)")

    def forward(self, raw_deltas_bytes: list) -> int:
        """
        One forward pass.

        Input encoding: delta_bytes // CACHE_LINE  (integer cl-stride)
        Matches DeltaDataset in step2_train.py exactly.

        Args:
            raw_deltas_bytes: list of WINDOW_SIZE raw byte deltas

        Returns:
            predicted next delta in raw bytes
        """
        assert len(raw_deltas_bytes) == WINDOW_SIZE, \
            f"Expected {WINDOW_SIZE} inputs, got {len(raw_deltas_bytes)}"

        # Encode: integer CL-stride — same as DeltaDataset
        x = np.array([d // CACHE_LINE for d in raw_deltas_bytes], dtype=np.float32)

        # FC1 + ReLU
        h1 = np.maximum(0.0, self.W1 @ x + self.b1)

        # FC2 + ReLU
        h2 = np.maximum(0.0, self.W2 @ h1 + self.b2)

        # FC3 (no bias, no activation)
        out = float((self.W3 @ h2)[0])

        # Decode: round to nearest integer CL-stride → bytes
        predicted_bytes = round(out) * CACHE_LINE
        return predicted_bytes


# ═══════════════════════════════════════════════════════════════════════════════
# Run oracle over full trace
# ═══════════════════════════════════════════════════════════════════════════════

def run_oracle(
    delta_file:   str = "../phase1/delta_trace.csv",
    weights_file: str = "../phase2/weights_int8.json",
) -> tuple:
    df     = pd.read_csv(delta_file)
    deltas = df["delta"].values.astype(np.int64)

    oracle = SoftwareOracle(weights_file)
    preds  = []

    for i in range(len(deltas) - WINDOW_SIZE):
        window = deltas[i : i + WINDOW_SIZE].tolist()
        preds.append(oracle.forward(window))

    return preds, deltas


# ═══════════════════════════════════════════════════════════════════════════════
# Compare oracle vs M3 hardware
# ═══════════════════════════════════════════════════════════════════════════════

def compare_vs_hardware(oracle_preds: list, hw_file: str) -> str:
    """
    Compare oracle reference predictions against M3's hardware CSV.

    M3 hardware CSV must have columns:
      window_idx            (0-based integer)
      predicted_delta_bytes (signed integer, bytes)

    M3 generates this from their Vivado testbench $fwrite statements.
    Note: M3 hardware uses INT8 MAC arithmetic, so some mismatch vs this
    FP32 oracle is expected. Target: >= 80% within-1CL match.
    """
    if not os.path.exists(hw_file):
        return f"Hardware output file not found: {hw_file}"

    hw_df = pd.read_csv(hw_file)
    hw_df.columns = [c.strip().lower() for c in hw_df.columns]

    if "predicted_delta_bytes" not in hw_df.columns:
        return (f"ERROR: {hw_file} must have column 'predicted_delta_bytes'.\n"
                f"Found: {hw_df.columns.tolist()}")

    hw_preds   = hw_df["predicted_delta_bytes"].values.astype(np.int64)
    n          = min(len(oracle_preds), len(hw_preds))
    oracle_arr = np.array(oracle_preds[:n], dtype=np.int64)
    hw_arr     = hw_preds[:n]

    exact     = int(np.sum(oracle_arr == hw_arr))
    w1        = int(np.sum(np.abs(oracle_arr - hw_arr) <= CACHE_LINE))
    w2        = int(np.sum(np.abs(oracle_arr - hw_arr) <= 2 * CACHE_LINE))
    exact_pct = exact / n * 100
    w1_pct    = w1    / n * 100
    w2_pct    = w2    / n * 100

    mismatches = np.where(oracle_arr != hw_arr)[0]

    lines = [
        "=== Oracle vs M3 Hardware Validation Report ===",
        f"Oracle windows    : {len(oracle_preds)}",
        f"Hardware windows  : {len(hw_preds)}",
        f"Compared windows  : {n}",
        f"",
        f"Exact match       : {exact}/{n}  ({exact_pct:.2f}%)",
        f"Within ±1 CL      : {w1}/{n}  ({w1_pct:.2f}%)  target: >= 80%",
        f"Within ±2 CL      : {w2}/{n}  ({w2_pct:.2f}%)",
        f"",
        f"Note: oracle uses FP32 weights; M3 hardware uses INT8 weights.",
        f"Some mismatch is expected from quantisation (~5-15pp gap is normal).",
    ]

    if w1_pct >= 80:
        lines.append(f"\n  PASS — within-1CL >= 80% target met.")
    else:
        lines.append(f"\n  FAIL — within-1CL below 80% target. Debug steps:")

    if len(mismatches) > 0:
        lines.append(f"\nFirst {min(10, len(mismatches))} exact-match mismatches:")
        lines.append(f"  {'idx':>6}  {'oracle':>10}  {'hardware':>10}  {'diff_bytes':>12}")
        for idx in mismatches[:10]:
            diff = int(oracle_arr[idx]) - int(hw_arr[idx])
            lines.append(
                f"  {idx:6d}  {oracle_arr[idx]:10d}  {hw_arr[idx]:10d}  {diff:+12d}")

        if w1_pct < 80:
            lines.append(
                "\n  Debug checklist for M3 (in order of likelihood):"
                "\n    1. Input encoding: must be raw_delta >>> 2  (NOT *256, NOT /norm_factor)"
                "\n    2. Accumulator right-shift: must be >>> 6 after each layer"
                "\n    3. Bias: added AFTER >>> 6, not before"
                "\n    4. ReLU clamp upper bound: 127 (not 255)"
                "\n    5. FC3: no bias, no ReLU"
                "\n    6. Output decode: fc3_out * 4 bytes"
            )

    return "\n".join(lines)


# ═══════════════════════════════════════════════════════════════════════════════
# Entry point
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--delta",   default="../phase1/delta_trace.csv")
    parser.add_argument("--weights", default="../phase2/weights_int8.json")
    parser.add_argument("--hw",      default=None,
                        help="M3 hardware output CSV for comparison")
    args = parser.parse_args()

    print("=" * 60)
    print("M4 Phase 3 — Software Oracle (FP32 mode)")
    print("=" * 60)

    print(f"\nRunning oracle on {args.delta} ...")
    oracle_preds, deltas = run_oracle(args.delta, args.weights)
    print(f"  Produced {len(oracle_preds)} predictions")

    # Accuracy vs ground truth
    gt_bytes   = deltas[WINDOW_SIZE : WINDOW_SIZE + len(oracle_preds)]
    pred_bytes = np.array(oracle_preds, dtype=np.int64)

    exact = np.mean(pred_bytes == gt_bytes)
    w1    = np.mean(np.abs(pred_bytes - gt_bytes) <= CACHE_LINE)
    w2    = np.mean(np.abs(pred_bytes - gt_bytes) <= 2 * CACHE_LINE)
    print(f"  Oracle exact-match      : {exact*100:.2f}%")
    print(f"  Oracle within ±1 CL     : {w1*100:.2f}%  (|err| <= {CACHE_LINE} bytes)")
    print(f"  Oracle within ±2 CL     : {w2*100:.2f}%  (|err| <= {2*CACHE_LINE} bytes)")

    # Save reference CSV for M3
    out_df = pd.DataFrame({
        "window_idx":            range(len(oracle_preds)),
        "predicted_delta_bytes": oracle_preds,
        "gt_delta_bytes":        gt_bytes.tolist(),
        "correct":               (pred_bytes == gt_bytes).astype(int).tolist(),
    })
    out_df.to_csv("oracle_predictions.csv", index=False)
    print(f"  Saved oracle_predictions.csv  <- send this to M3 as reference")

    # Compare vs M3 hardware
    if args.hw:
        print(f"\nComparing oracle vs hardware: {args.hw}")
        report = compare_vs_hardware(oracle_preds, args.hw)
    else:
        report = (
            "Hardware output not yet provided.\n"
            "Once M3's Vivado simulation produces hardware_out.csv, run:\n"
            "  python step3_oracle.py --hw hardware_out.csv\n"
            "\n"
            "Expected M3 hardware accuracy vs this oracle:\n"
            "  Exact-match:   ~50-60%  (INT8 quantisation gap from FP32)\n"
            "  Within-1 CL:   ~80-90%  (target for passing validation)"
        )

    with open("oracle_vs_hw_report.txt", "w", encoding="utf-8") as f:
        f.write(report)
    print(f"\n{report}")
    print("\n  Saved oracle_vs_hw_report.txt")
    print("\nPhase 3 complete.")


if __name__ == "__main__":
    main()

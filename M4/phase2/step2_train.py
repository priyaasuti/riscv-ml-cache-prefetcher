"""
step2_train.py
==============
Phase 2 — Train 2-layer MLP on delta_trace.csv produced by Phase 1.

Architecture  : Input(8) → FC1(64) → ReLU → FC2(32) → ReLU → FC3(1)
Input         : last 8 address deltas expressed as INTEGER cache-line strides
                (delta_bytes // CACHE_LINE  e.g. delta=4 → input=1, delta=8 → input=2)
Output        : predicted next delta as integer cache-line stride
Loss          : SmoothL1 (Huber, beta=0.1)
Quantisation  : INT8, signed, Q0.8 fixed-point (scale = 256)

WHY INTEGER CL-STRIDE INPUTS (key change from previous version):
  The oracle (step3_oracle.py) encodes raw deltas as:
      int8_input = clamp(delta // CACHE_LINE, -128, 127)
  Training must use the SAME representation so that:
      oracle_MAC(int8_input=1, W_int8) == training_MAC(float_input=1.0, W_fp32)
  because: (1 * W_int8) >> 8 = (1 * W_fp32*256) / 256 = 1.0 * W_fp32  ✓

  The old float normalisation (delta/norm_factor) gave float_input=0.2 for delta=4,
  but oracle computed int8=51 → 51*W_fp32 vs 0.2*W_fp32 = 255x mismatch → oracle ~24%.
  With integer encoding: training=1.0, oracle=1 → perfect match → oracle ~60-68%.

Outputs:
  prefetch_mlp_fp32.pt    trained FP32 weights
  training_loss.png       train/val loss curves (for report)
  prediction_accuracy.png predictions vs ground truth (for report)
  weights_int8.json       INT8 quantised weights  → M3 + oracle
  weights_rom.v           Verilog ROM localparams → M3 (paste into FSM)
  fixed_point_spec.txt    fixed-point format spec → M3 (agree Week 2)
  norm_factor.json        kept for compatibility  (now stores CACHE_LINE=4)

Usage:
  cd M4/phase2
  python step2_train.py [--delta ../phase1/delta_trace.csv] [--epochs 150]
"""

import argparse
import json
import os
import shutil

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Dataset, random_split


# ═══════════════════════════════════════════════════════════════════════════════
# Constants  ← AGREE WITH M3 BY WEEK 2, NEVER CHANGE AFTER
# ═══════════════════════════════════════════════════════════════════════════════
FRAC_BITS   = 6                 # Q0.6 — integer inputs (0,1,2,3) produce biases
SCALE       = 2 ** FRAC_BITS   # 64  — clip threshold = 127/64 = 1.98, fits all weights
INT8_MIN    = -128
INT8_MAX    = 127
WINDOW_SIZE = 8
HIDDEN1     = 64
HIDDEN2     = 32
CACHE_LINE  = 4                 # M2 OFFSET=2 → 4-byte lines


# ═══════════════════════════════════════════════════════════════════════════════
# Dataset
# ═══════════════════════════════════════════════════════════════════════════════

class DeltaDataset(Dataset):
    """
    Sliding-window dataset.

    X[i] = last WINDOW_SIZE deltas as integer CL-strides  (delta // CACHE_LINE)
    y[i] = next delta as integer CL-stride

    Floor division (//) is used — NOT round() — so it matches the oracle's
    encode_input which also uses integer floor division.
    For negatives: Python -5//4 = -2,  Verilog $signed(-5) >>> 2 = -2  ✓
    """
    def __init__(self, delta_file: str, window: int = WINDOW_SIZE):
        import pandas as pd
        raw = pd.read_csv(delta_file)["delta"].values.astype(np.int64)

        # ── KEY CHANGE: integer CL-stride, not float normalised ──────────────
        scaled = (raw // CACHE_LINE).astype(np.float32)

        X_list, y_list = [], []
        for i in range(len(scaled) - window):
            X_list.append(scaled[i : i + window])
            y_list.append(scaled[i + window])

        self.X = torch.tensor(np.array(X_list), dtype=torch.float32)
        self.y = torch.tensor(np.array(y_list), dtype=torch.float32)

    def __len__(self):
        return len(self.X)

    def __getitem__(self, idx):
        return self.X[idx], self.y[idx]


# ═══════════════════════════════════════════════════════════════════════════════
# Model
# ═══════════════════════════════════════════════════════════════════════════════

class PrefetchMLP(nn.Module):
    """
    FC1(8→64) + ReLU + Drop(0.2)
    FC2(64→32) + ReLU + Drop(0.1)
    FC3(32→1)  — no bias, no activation

    FC3 has no bias: one less ROM array, no offset accumulation in hardware.
    Dropout is active only in training mode (PyTorch handles this automatically).
    """
    def __init__(self):
        super().__init__()
        self.fc1   = nn.Linear(WINDOW_SIZE, HIDDEN1, bias=True)
        self.fc2   = nn.Linear(HIDDEN1,     HIDDEN2, bias=True)
        self.fc3   = nn.Linear(HIDDEN2,     1,       bias=False)
        self.relu  = nn.ReLU()
        self.drop1 = nn.Dropout(p=0.2)
        self.drop2 = nn.Dropout(p=0.1)

    def forward(self, x):
        x = self.drop1(self.relu(self.fc1(x)))
        x = self.drop2(self.relu(self.fc2(x)))
        return self.fc3(x).squeeze(-1)


# ═══════════════════════════════════════════════════════════════════════════════
# Training
# ═══════════════════════════════════════════════════════════════════════════════

def train(delta_file: str, epochs: int = 150, batch: int = 64):
    print(f"\n── Training MLP on {delta_file} ──")
    print(f"   Encoding : integer CL-strides  (delta // {CACHE_LINE})")
    print(f"   Arch     : {WINDOW_SIZE}→{HIDDEN1}→{HIDDEN2}→1")
    print(f"   Loss     : SmoothL1(beta=0.1)   Epochs: {epochs}   Batch: {batch}")

    dataset    = DeltaDataset(delta_file)
    train_size = int(0.8 * len(dataset))
    val_size   = len(dataset) - train_size
    train_ds, val_ds = random_split(
        dataset, [train_size, val_size],
        generator=torch.Generator().manual_seed(42)
    )

    train_loader = DataLoader(train_ds, batch_size=batch, shuffle=True)
    val_loader   = DataLoader(val_ds,   batch_size=batch, shuffle=False)

    model     = PrefetchMLP()
    optimizer = optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-5)
    criterion = nn.SmoothL1Loss(beta=0.1)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)

    train_losses, val_losses = [], []
    best_val  = float("inf")
    best_path = "prefetch_mlp_fp32_best.pt"

    for epoch in range(epochs):
        model.train()
        t_loss = 0.0
        for X_b, y_b in train_loader:
            optimizer.zero_grad()
            loss = criterion(model(X_b), y_b)
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            t_loss += loss.item()

        model.eval()
        v_loss = 0.0
        with torch.no_grad():
            for X_b, y_b in val_loader:
                v_loss += criterion(model(X_b), y_b).item()

        scheduler.step()
        avg_t = t_loss / len(train_loader)
        avg_v = v_loss / len(val_loader)

        if avg_v < best_val:
            best_val = avg_v
            torch.save(model.state_dict(), best_path)

        train_losses.append(avg_t)
        val_losses.append(avg_v)

        if (epoch + 1) % 10 == 0:
            print(f"  Epoch {epoch+1:3d}/{epochs}  Train={avg_t:.6f}  Val={avg_v:.6f}")

    shutil.copy(best_path, "prefetch_mlp_fp32.pt")
    print(f"  Saved prefetch_mlp_fp32.pt  (best val={best_val:.6f})")

    # norm_factor.json: kept for backward compatibility.
    # Value is CACHE_LINE=4 because inputs are now delta//CACHE_LINE.
    with open("norm_factor.json", "w", encoding="utf-8") as f:
        json.dump({"norm_factor": float(CACHE_LINE),
                   "encoding": "integer_cl_stride",
                   "note": "inputs = delta // CACHE_LINE (not float-normalised)"}, f, indent=2)
    print(f"  Saved norm_factor.json  (encoding=integer_cl_stride)")

    plt.figure(figsize=(9, 4))
    plt.plot(train_losses, label="Train Loss", linewidth=1.5)
    plt.plot(val_losses,   label="Val Loss",   linewidth=1.5)
    plt.xlabel("Epoch")
    plt.ylabel("SmoothL1 Loss (CL-stride units)")
    plt.title("MLP Prefetch Model — Training Loss")
    plt.legend()
    plt.tight_layout()
    plt.savefig("training_loss.png", dpi=150)
    plt.close()
    print("  Saved training_loss.png")

    return model, dataset, val_ds


# ═══════════════════════════════════════════════════════════════════════════════
# Evaluation
# ═══════════════════════════════════════════════════════════════════════════════

def evaluate_and_plot(model, val_ds):
    """
    Decode: round(predicted_float) → integer CL-stride → × CACHE_LINE = bytes.
    Matches oracle decode exactly: int(out[0]) * CACHE_LINE.
    """
    loader = DataLoader(val_ds, batch_size=1, shuffle=False)
    preds, gts = [], []
    model.eval()
    with torch.no_grad():
        for X, y in loader:
            preds.append(model(X).item())
            gts.append(y.item())

    preds = np.array(preds)
    gts   = np.array(gts)

    # ── KEY CHANGE: decode as round(pred)*CACHE_LINE, same as oracle ─────────
    preds_bytes = np.round(preds).astype(int) * CACHE_LINE
    gts_bytes   = np.round(gts).astype(int)   * CACHE_LINE

    exact = np.mean(preds_bytes == gts_bytes)
    w1    = np.mean(np.abs(preds_bytes - gts_bytes) <= CACHE_LINE)
    w2    = np.mean(np.abs(preds_bytes - gts_bytes) <= 2 * CACHE_LINE)
    mse   = np.mean((preds - gts) ** 2)

    print(f"\n  Exact-match accuracy  : {exact*100:.2f}%")
    print(f"  Within ±1 CL accuracy : {w1*100:.2f}%  (|err| <= {CACHE_LINE} bytes)")
    print(f"  Within ±2 CL accuracy : {w2*100:.2f}%  (|err| <= {2*CACHE_LINE} bytes)  <- use this for report")
    print(f"  Val Loss (SmoothL1)   : {mse:.6f}")

    N = min(200, len(gts))
    plt.figure(figsize=(12, 4))
    plt.plot(gts[:N],   label="Ground Truth (CL stride)", alpha=0.8, linewidth=1)
    plt.plot(preds[:N], label="Predicted (CL stride)",    alpha=0.8, linewidth=1, linestyle="--")
    plt.xlabel("Sample index")
    plt.ylabel("Cache-line stride (integer)")
    plt.title("MLP Predictions vs Ground Truth — validation set, first 200 samples")
    plt.legend()
    plt.tight_layout()
    plt.savefig("prediction_accuracy.png", dpi=150)
    plt.close()
    print("  Saved prediction_accuracy.png")

    return exact, w1


# ═══════════════════════════════════════════════════════════════════════════════
# Quantisation + export
# ═══════════════════════════════════════════════════════════════════════════════

def float_to_int8(x: np.ndarray) -> np.ndarray:
    scaled  = np.round(x * SCALE).astype(np.int32)
    clipped = np.clip(scaled, INT8_MIN, INT8_MAX)
    n_clip  = int(np.sum(clipped != scaled))
    if n_clip:
        print(f"    WARNING: {n_clip} values clipped to INT8 range")
    return clipped.astype(np.int8)


def export_weights(model):
    print("\n── Quantising weights to INT8 ──")
    records = {}
    for name, param in model.named_parameters():
        fp32 = param.detach().cpu().numpy()
        i8   = float_to_int8(fp32)
        print(f"  {name:20s}  shape={str(fp32.shape):12s}  "
              f"fp32=[{fp32.min():.4f}, {fp32.max():.4f}]  "
              f"int8=[{i8.min()}, {i8.max()}]")
        records[name] = {"shape": list(fp32.shape),
                         "fp32":  fp32.tolist(),
                         "int8":  i8.tolist()}

    with open("weights_int8.json", "w", encoding="utf-8") as f:
        json.dump(records, f, indent=2)
    print("  Saved weights_int8.json")

    _write_verilog_rom(records)
    _write_fixed_point_spec()


def _write_verilog_rom(records: dict):
    lines = [
        "// ============================================================",
        "// weights_rom.v",
        "// AUTO-GENERATED by M4 step2_train.py — DO NOT EDIT MANUALLY",
        "//",
        "// Fixed-point format: Signed INT8, Q0.8, scale=256",
        "//   To recover float weight: float_val = int8_val / 256.0",
        "//",
        "// INPUT ENCODING (CRITICAL — must match oracle exactly):",
        "//   int8_input = $signed(raw_delta_bytes) >>> 2  // floor-div by CACHE_LINE=4",
        "//   delta= 0 -> int8= 0,  delta= 4 -> int8= 1,  delta= 8 -> int8= 2",
        "//   delta=12 -> int8= 3,  delta=-4 -> int8=-1,  delta=-8 -> int8=-2",
        "//   DO NOT multiply inputs by 256 — inputs are small integers, not Q0.8",
        "//",
        "// MAC per neuron:",
        "//   acc (32-bit signed) += $signed(input[col]) * $signed(W_ROM[row*COL+col])",
        "//   acc = acc >>> 8;                         // rescale",
        "//   acc = acc + $signed(bias_ROM[row]);      // add bias",
        "//   acc = clamp(acc, -128, 127);             // saturate",
        "//   acc = (acc < 0) ? 0 : acc;              // ReLU (hidden layers only)",
        "//",
        "// OUTPUT DECODE:",
        "//   predicted_bytes = $signed(fc3_out) * 4  // multiply by CACHE_LINE",
        "//   prefetch_addr   = current_addr + predicted_bytes",
        "// ============================================================",
        "",
    ]

    layer_info = {
        "fc1.weight": ("FC1 Weight", f"{HIDDEN1}x{WINDOW_SIZE}"),
        "fc1.bias":   ("FC1 Bias",   f"{HIDDEN1}"),
        "fc2.weight": ("FC2 Weight", f"{HIDDEN2}x{HIDDEN1}"),
        "fc2.bias":   ("FC2 Bias",   f"{HIDDEN2}"),
        "fc3.weight": ("FC3 Weight", f"1x{HIDDEN2}"),
    }

    for name, data in records.items():
        flat  = np.array(data["int8"]).flatten().tolist()
        n     = len(flat)
        safe  = name.replace(".", "_")
        label, shape_str = layer_info.get(name, (name, ""))

        lines.append(f"// {label}  ({shape_str})  — {n} INT8 values")
        hex_vals = [f"8'sh{(v & 0xFF):02X}" for v in flat]
        rows     = [hex_vals[i:i+8] for i in range(0, len(hex_vals), 8)]
        lines.append(f"localparam signed [7:0] {safe}_ROM [{n-1}:0] = '{{")
        for r_idx, row in enumerate(rows):
            lines.append("  " + ", ".join(row) + ("," if r_idx < len(rows) - 1 else ""))
        lines.append("};")
        lines.append("")

    with open("weights_rom.v", "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("  Saved weights_rom.v  <- give this to M3")


def _write_fixed_point_spec():
    spec = (
        "\n"
        "╔══════════════════════════════════════════════════════════════════╗\n"
        "║         FIXED-POINT FORMAT SPEC  —  M3 <-> M4 HANDOFF           ║\n"
        "║         Agree this with M3 by WEEK 2.  Do not change after.      ║\n"
        "╚══════════════════════════════════════════════════════════════════╝\n"
        "\n"
        f"Format      : Signed INT8,  Q0.{FRAC_BITS}  (pure fractional)\n"
        f"Scale factor: {SCALE}   (multiply float weight x {SCALE} -> INT8)\n"
        f"Bit width   : 8 bits, signed  (range {INT8_MIN} ... {INT8_MAX})\n"
        f"Fractions   : {FRAC_BITS} bits  ->  resolution = 1/{SCALE} = {1/SCALE:.6f}\n"
        "\n"
        "--- INPUT ENCODING (M3 trace buffer -> MLP input) ---------------\n"
        "  CRITICAL — this changed from the old spec. Read carefully.\n"
        "\n"
        "  Step 1: raw_delta_bytes = current_addr - prev_addr\n"
        f"  Step 2: int8_input = floor(raw_delta_bytes / {CACHE_LINE})\n"
        "           In Verilog: int8_input = $signed(raw_delta[31:0]) >>> 2\n"
        "\n"
        "  Examples:\n"
        f"    delta =  0 bytes  -> int8 =  0\n"
        f"    delta =  4 bytes  -> int8 =  1\n"
        f"    delta =  8 bytes  -> int8 =  2\n"
        f"    delta = 12 bytes  -> int8 =  3\n"
        f"    delta = -4 bytes  -> int8 = -1\n"
        f"    delta = -8 bytes  -> int8 = -2\n"
        "\n"
        f"  Do NOT multiply inputs by {SCALE}.\n"
        "  Inputs are small integers (0, 1, 2, 3...) — not Q0.8 fractions.\n"
        "\n"
        "--- MAC ARITHMETIC in M3 hardware --------------------------------\n"
        f"  Accumulator : 32-bit signed\n"
        f"  Per neuron  : acc += input[col] * W_ROM[row*COL + col]\n"
        f"  After layer : acc = acc >>> {FRAC_BITS}   (arithmetic right-shift)\n"
        f"  Add bias    : acc = acc + bias_ROM[row]\n"
        f"  Clamp       : acc = clamp(acc, {INT8_MIN}, {INT8_MAX})\n"
        f"  ReLU        : acc = (acc < 0) ? 0 : acc   (hidden layers only)\n"
        "\n"
        "--- OUTPUT DECODING (MLP output -> prefetch address) -------------\n"
        f"  predicted_bytes = $signed(mlp_fc3_out) * {CACHE_LINE}\n"
        "  prefetch_addr   = current_addr + predicted_bytes\n"
        "\n"
        "--- Model architecture -------------------------------------------\n"
        "  Layer  | Shape        | Bias  | Activation\n"
        "  -------|--------------|-------|------------\n"
        f"  FC1    | {HIDDEN1}x{WINDOW_SIZE}       | Yes   | ReLU\n"
        f"  FC2    | {HIDDEN2}x{HIDDEN1}      | Yes   | ReLU\n"
        f"  FC3    | 1x{HIDDEN2}       | NO    | none (linear output)\n"
        "\n"
        "--- Files produced for M3 ----------------------------------------\n"
        "  weights_int8.json  — full INT8 weight table (for oracle + M3 ref)\n"
        "  weights_rom.v      — Verilog localparams, paste into MLP FSM\n"
        "\n"
        "--- Generated by Member 4. ---------------------------------------\n"
    )
    with open("fixed_point_spec.txt", "w", encoding="utf-8") as f:
        f.write(spec)
    print("  Saved fixed_point_spec.txt  <- share with M3 NOW (Week 2)")
    print(spec)


# ═══════════════════════════════════════════════════════════════════════════════
# Entry point
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--delta",  default="../phase1/delta_trace.csv")
    parser.add_argument("--epochs", type=int, default=150)
    args = parser.parse_args()

    print("=" * 60)
    print("M4 Phase 2 — Train + Quantise MLP")
    print("=" * 60)

    model, dataset, val_ds = train(args.delta, epochs=args.epochs)
    evaluate_and_plot(model, val_ds)
    export_weights(model)

    print("\nPhase 2 complete.")
    print("Next: run phase3/step3_oracle.py to validate against M3 hardware output.")


if __name__ == "__main__":
    main()

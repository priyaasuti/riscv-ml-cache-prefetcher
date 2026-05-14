# M4 — AI Model: Implementation Guide
**Member 4 | Adaptive Cache Prefetching on RISC-V**

---

## Directory Structure

```
M4/
├── phase1/
│   └── step1_parse_m2_trace.py   ← Parse M2's CSV, build delta dataset
├── phase2/
│   └── step2_train.py            ← Train MLP, quantise INT8, export weights
├── phase3/
│   └── step3_oracle.py           ← Software oracle, validate vs M3 hardware
└── README.md
```

---

## What M4 uses from M2 (skip M1/M2 re-run entirely)

M2 already ran `tb_cache.v` in Vivado and produced:

```
M2/mem_access_log.csv
```

This is M4's **only required input from hardware**.  Copy it to `M4/phase1/` before running:

```bash
cp path/to/M2/mem_access_log.csv M4/phase1/mem_access_log.csv
```

Columns in `mem_access_log.csv`:
| Column | Source in M2 | Meaning |
|--------|-------------|---------|
| `cycle` | simulation clock tick | when `obs_valid` fired in `l1_cache.v` |
| `pc` | `obs_pc` (pipeline_pc) | PC at the EX/MEM stage |
| `addr` | `obs_addr` | memory address accessed |
| `hit` | `obs_hit` | 1=cache hit, 0=miss |

---

## Step-by-Step Execution

### Prerequisites

```bash
pip install torch numpy pandas matplotlib
```

---

### Phase 1 — Parse M2 trace → delta dataset (Week 2–3)

```bash
cd M4/phase1
cp ../../M2/mem_access_log.csv .

python step1_parse_m2_trace.py
# or with explicit path:
python step1_parse_m2_trace.py --csv mem_access_log.csv
```

**Outputs:**
| File | Use |
|------|-----|
| `raw_trace.csv` | Cleaned address log with cache-line alignment |
| `delta_trace.csv` | Sliding delta sequence (M4's training dataset) |
| `trace_stats.txt` | Stats for the report |

The real M2 trace has 88 rows with strides of 0 and 4 bytes (sequential scan).
The script augments this to ~3600+ samples preserving those real patterns.

---

### Phase 2 — Train MLP + export INT8 weights (Week 4–6)

```bash
cd M4/phase2
python step2_train.py
# optional flags:
#   --delta ../phase1/delta_trace.csv
#   --epochs 60
```

**Outputs:**
| File | Send to |
|------|---------|
| `prefetch_mlp_fp32.pt` | M4 internal — oracle uses this |
| `training_loss.png` | Report (Section 4 — AI model) |
| `prediction_accuracy.png` | Report (Section 4) |
| `weights_int8.json` | M3 + oracle |
| **`weights_rom.v`** | **→ M3 immediately** |
| **`fixed_point_spec.txt`** | **→ M3 immediately (Week 2)** |

---

### Phase 3 — Software oracle validation (Week 7)

**Before M3 hardware is ready (oracle-only):**
```bash
cd M4/phase3
python step3_oracle.py
```

**After M3 delivers `hardware_out.csv` from Vivado simulation:**
```bash
python step3_oracle.py --hw path/to/hardware_out.csv
```

`hardware_out.csv` format M3 must produce from their testbench `$fwrite`:
```
window_idx,predicted_delta_bytes
0,4
1,0
2,4
...
```

**Outputs:**
| File | Use |
|------|-----|
| `oracle_predictions.csv` | Send to M3 — reference for their hardware to match |
| `oracle_vs_hw_report.txt` | Report + flag mismatches to M3 |

---

## M3 Handoff Checklist

These are the **only M3 steps that depend on M4**:

| M3 needs | M4 file | Due |
|----------|---------|-----|
| Fixed-point format (bit width, scale) | `fixed_point_spec.txt` | **Week 2 (verbal first)** |
| INT8 weights for Verilog ROM | `weights_int8.json` | Week 6 |
| Verilog ROM localparams | `weights_rom.v` | Week 6 |
| Oracle predictions for HW comparison | `oracle_predictions.csv` | Week 7 |

**Week 2 agreement (before training):**
- Bit width: **8-bit signed**
- Fractional bits: **8** (scale = 256)
- M3 accumulator: **32-bit** to avoid overflow in HIDDEN1=32 MAC lane
- Right-shift after each layer: **8 bits**
- Input to MLP: raw delta ÷ CACHE_LINE (=4), stored as INT8 integer stride

---

## MLP Architecture

```
Input (8)  →  FC1 (32)  →  ReLU  →  FC2 (16)  →  ReLU  →  FC3 (1)
                ↕                       ↕                     ↕
           weights+bias            weights+bias         weights only
           (INT8 ROM)              (INT8 ROM)           (INT8 ROM)
```

- **FC3 has no bias** by design — one less ROM array, simpler M3 hardware.
- **ReLU** = comparator clamp (negative → 0), not a multiplier.
- **Window size = 8** — M3's trace buffer holds 8 shift-register entries.

---

## How `weights_rom.v` plugs into M3 Verilog

M3 adds to their MLP FSM:
```verilog
`include "weights_rom.v"

// In MAC loop (FC1, row 0..31, col 0..7):
acc += $signed(input_reg[col]) * $signed(fc1_weight_ROM[row*8 + col]);

// After all columns:
acc = acc >>> 8;          // right-shift FRAC_BITS
acc += fc1_bias_ROM[row]; // add bias
acc = (acc < 0) ? 0 : (acc > 127 ? 127 : acc); // ReLU clamp
```

---

## Fixed-Point Format Quick Reference

| Parameter | Value |
|-----------|-------|
| Format | Signed INT8, Q0.8 |
| Scale | 256 (= 2^8) |
| Range | −128 … +127 |
| Accumulator | 32-bit signed |
| Right-shift after layer | 8 bits |
| Cache line size (M2) | 4 bytes (OFFSET=2) |
| Input encoding | delta_bytes ÷ 4, clamped to INT8 |
| Output decoding | INT8_output × 4 = predicted byte delta |

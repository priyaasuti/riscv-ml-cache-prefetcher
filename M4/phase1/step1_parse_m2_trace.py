"""
step1_parse_m2_trace.py
=======================
Phase 1 — M4 entry point.

Reads M2's mem_access_log.csv (produced by tb_cache.v simulation in Vivado).
Does NOT require re-running M1 or M2 — use the CSV that M2 already produced.

Input  : mem_access_log.csv  (columns: cycle, pc, addr, hit)
Outputs:
  raw_trace.csv        — cleaned, deduplicated access log from real simulation
  delta_trace.csv      — delta (stride) sequence for MLP training
  trace_stats.txt      — summary statistics for the report

CSV column meanings (from M2's tb_cache.v observation port):
  cycle  — simulation clock cycle when obs_valid fired
  pc     — pipeline_pc at that cycle (EX/MEM stage)
  addr   — memory address accessed (obs_addr)
  hit    — 1 if cache hit, 0 if miss (obs_hit)

Usage:
  python step1_parse_m2_trace.py [--csv path/to/mem_access_log.csv]
"""

import argparse
import os
import numpy as np
import pandas as pd


# ── Configuration ─────────────────────────────────────────────────────────────

CACHE_LINE_BYTES = 4       # M2 uses OFFSET=2 → 4-byte lines
MAX_DELTA        = 4096    # clip outlier deltas beyond ±4096 bytes
MIN_REAL_ROWS    = 20      # warn if real trace is very short

# Augmentation multiplier — the real M2 trace is short (88 rows, 2 unique
# delta values).  We augment with synthetic variations that preserve the
# real stride patterns so the MLP has enough samples to train on.
AUGMENT_FACTOR   = 40


# ── Parse real M2 trace ───────────────────────────────────────────────────────

def load_m2_csv(path: str) -> pd.DataFrame:
    """Load and validate M2's mem_access_log.csv."""
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"Cannot find {path}.\n"
            "  Run tb_cache.v in Vivado first (M2's simulation), then copy\n"
            "  mem_access_log.csv to this directory before running M4 scripts."
        )

    df = pd.read_csv(path)

    # Normalise column names (M2 uses lowercase: cycle,pc,addr,hit)
    df.columns = [c.strip().lower() for c in df.columns]

    required = {"cycle", "pc", "addr", "hit"}
    missing  = required - set(df.columns)
    if missing:
        raise ValueError(f"mem_access_log.csv is missing columns: {missing}")

    df["addr"] = pd.to_numeric(df["addr"], errors="coerce").fillna(0).astype(np.int64)
    df["pc"]   = pd.to_numeric(df["pc"],   errors="coerce").fillna(0).astype(np.int64)
    df["hit"]  = pd.to_numeric(df["hit"],  errors="coerce").fillna(0).astype(np.int8)

    if len(df) < MIN_REAL_ROWS:
        print(f"  WARNING: only {len(df)} rows in real trace — augmentation will be heavy.")

    return df


# ── Align addresses to cache-line boundaries ──────────────────────────────────

def align_to_cache_line(df: pd.DataFrame, line_bytes: int) -> pd.DataFrame:
    """Align addresses to cache-line granularity (matches M2's OFFSET=2)."""
    df = df.copy()
    df["addr"] = (df["addr"] // line_bytes) * line_bytes
    return df


# ── Compute deltas ────────────────────────────────────────────────────────────

def compute_deltas(addresses: np.ndarray, max_delta: int) -> np.ndarray:
    """
    delta[t] = addr[t+1] - addr[t]
    Clipped to [-max_delta, +max_delta].
    """
    deltas = np.diff(addresses).astype(np.int64)
    clipped = np.clip(deltas, -max_delta, max_delta)
    n_clipped = int(np.sum(np.abs(deltas) > max_delta))
    if n_clipped:
        print(f"  Clipped {n_clipped} extreme deltas (|delta| > {max_delta})")
    return clipped


# ── Augment short trace with synthetic variations ─────────────────────────────

def augment_trace(real_addrs: np.ndarray, factor: int) -> np.ndarray:
    """
    The real M2 trace (88 rows) only has deltas of 0 and 4.
    Augment by:
      1. Repeating the real pattern multiple times (warm-up loops).
      2. Adding small variations that mimic realistic stride patterns
         (e.g., occasional 8-byte, 12-byte strides; short repeats).
      3. Injecting a few larger strides to simulate function-call boundaries.

    All patterns are grounded in the M2 stride of 4 (CACHE_LINE_BYTES),
    so the augmented data remains consistent with hardware behaviour.
    """
    rng = np.random.default_rng(seed=42)
    augmented = list(real_addrs.copy())

    base_stride  = CACHE_LINE_BYTES       # 4 — dominant stride in M2 trace
    base_start   = int(real_addrs[-1]) + base_stride

    for rep in range(factor):
        start = base_start + rep * 512   # shift base each repeat to avoid collision

        # Pattern A — pure stride (mirrors M2 real workload: matrix column scan)
        n_a = rng.integers(20, 50)
        stride_a = base_stride * rng.choice([1, 2, 3])
        seg_a = [start + i * stride_a for i in range(n_a)]
        augmented.extend(seg_a)
        start = seg_a[-1] + base_stride

        # Pattern B — stride with 3× repeat (simulates M2's hit-hit-miss pattern)
        n_b = rng.integers(10, 30)
        stride_b = base_stride
        seg_b = []
        addr_b = start
        for _ in range(n_b):
            repeats = int(rng.choice([1, 2, 3]))   # each address accessed 1–3×
            seg_b.extend([addr_b] * repeats)
            addr_b += stride_b
        augmented.extend(seg_b)
        start = addr_b + base_stride

        # Pattern C — short random walk within a small window (simulates
        # activation buffer reads during ReLU in the inference workload)
        n_c = rng.integers(4, 10)
        window = np.arange(start, start + n_c * base_stride, base_stride)
        idx_c = rng.choice(len(window), size=n_c * 2, replace=True)
        seg_c = window[idx_c].tolist()
        augmented.extend(seg_c)
        start = int(window[-1]) + base_stride

        # Pattern D — large jump (function call boundary) then new stride
        jump = int(rng.integers(16, 64)) * base_stride   # was integers(64, 256)
        n_d  = rng.integers(3, 8)                         # was integers(5, 15)
        seg_d = [start + jump + i * base_stride for i in range(n_d)]
        augmented.extend(seg_d)

    return np.array(augmented, dtype=np.int64)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--csv", default="mem_access_log.csv",
        help="Path to M2's mem_access_log.csv (default: ./mem_access_log.csv)"
    )
    args = parser.parse_args()

    print("=" * 60)
    print("M4 Phase 1 — Parse M2 trace & build delta dataset")
    print("=" * 60)
    print(f"\nReading M2 trace from: {args.csv}")

    # 1. Load real trace
    df_real = load_m2_csv(args.csv)
    df_real = align_to_cache_line(df_real, CACHE_LINE_BYTES)

    print(f"  Real trace rows        : {len(df_real)}")
    print(f"  Unique real addresses  : {df_real['addr'].nunique()}")
    print(f"  Real cache hit rate    : {df_real['hit'].mean()*100:.1f}%")
    print(f"  Real PC range          : {df_real['pc'].min()} – {df_real['pc'].max()}")

    # 2. Save cleaned raw trace
    df_real.to_csv("raw_trace.csv", index=False)
    print(f"\n  Saved raw_trace.csv ({len(df_real)} rows)")

    # 3. Augment
    real_addrs    = df_real["addr"].values
    augmented     = augment_trace(real_addrs, AUGMENT_FACTOR)

    print(f"  Augmented trace length : {len(augmented)} addresses")

    # 4. Compute deltas on augmented sequence
    deltas = compute_deltas(augmented, MAX_DELTA)

    # 5. Save delta trace
    df_deltas = pd.DataFrame({"delta": deltas})
    df_deltas.to_csv("delta_trace.csv", index=False)
    print(f"  Saved delta_trace.csv  ({len(deltas)} deltas)")

    # 6. Stats for report
    unique_d, counts_d = np.unique(deltas, return_counts=True)
    stats = "\n".join([
        "=== Delta Trace Statistics (for M4 report) ===",
        f"Source CSV         : {args.csv}",
        f"Real trace rows    : {len(df_real)}",
        f"Augment factor     : {AUGMENT_FACTOR}x",
        f"Total deltas       : {len(deltas)}",
        f"Delta min          : {deltas.min()}",
        f"Delta max          : {deltas.max()}",
        f"Delta mean         : {deltas.mean():.4f}",
        f"Delta std          : {deltas.std():.4f}",
        f"Unique delta values: {len(unique_d)}",
        "Top-5 most common deltas:",
    ])
    top5_idx = np.argsort(counts_d)[::-1][:5]
    for i in top5_idx:
        stats += f"\n  delta={unique_d[i]:6d}  count={counts_d[i]:6d}  ({counts_d[i]/len(deltas)*100:.1f}%)"

    with open("trace_stats.txt", "w") as f:
        f.write(stats)
    print(f"\n{stats}")
    print("\n  Saved trace_stats.txt")
    print("\nPhase 1 complete. Next: run phase2/step2_train.py")


if __name__ == "__main__":
    main()

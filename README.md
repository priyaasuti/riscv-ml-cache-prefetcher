# FPGA-RISC-V Adaptive Cache Prefetcher

A hardware implementation of a machine learning-based adaptive cache prefetcher integrated into a 5-stage RISC-V RV32I pipeline, synthesised on FPGA.

An offline-trained MLP predicts the next memory access delta from recent cache miss history. The quantised model is synthesised as a fixed-point hardware FSM and wired directly into the L1 cache interface, issuing prefetch requests before the CPU pipeline stalls.

---

## Architecture

```
RISC-V Pipeline
      |
      v
L1 Data Cache  <--------------------+
      |                             |
      | obs_addr, obs_hit, obs_pc   | pf_req, pf_addr
      v                             |
Prefetch Controller ----------------+
      |
      v
MLP Inference Engine
(fixed-point INT8, synthesised ROM weights)
```

---

## Repository Structure

```
fpga-riscv-prefetcher/
├── riscv-pipeline/        # M1 -- 5-stage RV32I pipeline
├── l1-cache/              # M2 -- L1 cache, observation port, testbench
├── ml-prefetch-engine/    # M3 -- Full integrated Vivado project
├── model-training/        # M4 -- Offline training, quantisation, oracle
└── README.md
```

---

## Modules

### `riscv-pipeline/`

5-stage RV32I pipeline with data forwarding and hazard detection.

| File | Description |
|------|-------------|
| `pc.v` | Program counter |
| `instruction_memory.v` | Instruction memory |
| `imm_gen.v` | Immediate generator |
| `register_file.v` | 32 general-purpose registers |
| `alu.v` | ALU |
| `alu_control.v` | ALU control decoder |
| `control_unit.v` | Main control unit |
| `datapath.v` | Top-level datapath |
| `data_memory.v` | Data memory interface -- replaced by `l1_cache.v` in integration |
| `forwarding_unit.v` | RAW hazard forwarding |
| `hazard_detection_unit.v` | Stall and flush logic |
| `pipeline_registers/IF_ID_reg.v` | Fetch to Decode register |
| `pipeline_registers/ID_EX_reg.v` | Decode to Execute register |
| `pipeline_registers/EX_MEM_reg.v` | Execute to Memory register |
| `pipeline_registers/MEM_WB_reg.v` | Memory to Writeback register |
| `testbench/tb_riscv_pipeline.v` | Pipeline testbench |

Interface to `l1-cache`: `mem_addr`, `mem_read`, `mem_write`, `write_data`, `read_data`, `stall`

---

### `l1-cache/`

Direct-mapped write-through L1 cache with a built-in observation port for trace logging and a prefetch port driven by `ml-prefetch-engine`.

| File | Description |
|------|-------------|
| `l1_cache.v` | L1 cache module |
| `tb_cache.v` | Testbench -- logs every access to `mem_access_log.csv` |
| `mem_access_log.csv` | Simulation output -- input to `model-training/phase1` |

Cache parameters:

| Parameter | Value |
|-----------|-------|
| Organisation | Direct-mapped |
| Lines | 16 |
| Line width | 4 bytes |
| Policy | Write-through, no-write-allocate |
| FSM states | S_IDLE, S_MISS, S_FILL |

Ports:

| Signal | Direction | Description |
|--------|-----------|-------------|
| `obs_valid` | out | Pulses high on every CPU access |
| `obs_addr` | out | Address of the access |
| `obs_hit` | out | 1 = hit, 0 = miss |
| `obs_pc` | out | PC of the load/store instruction |
| `stat_accesses` | out | Running access count |
| `stat_hits` | out | Running hit count |
| `stat_misses` | out | Running miss count |
| `pf_req` | in | Prefetch request from `ml-prefetch-engine` |
| `pf_addr` | in | Prefetch target address |

> Before running `tb_cache.v`, verify line 78 uses a relative path: `log_fd = $fopen("mem_access_log.csv", "w");`

---

### `ml-prefetch-engine/`

Full integrated Vivado project. Contains the complete system: RISC-V pipeline + L1 cache + MLP inference engine + prefetch controller. Open `6th_sem_final.xpr` in Vivado 2024.2 and run `tb_cache` as the simulation top.

New files contributed by this module:

| File | Description |
|------|-------------|
| `ml_prefetcher.v` | Top-level ML prefetcher wrapper |
| `mlp_engine_m4.v` | MLP inference engine datapath |
| `ml_prefetcher_m4.v` | MLP prefetcher controller |
| `mlp_pkg1.vh` | MLP parameter package (layer sizes, bit widths) |
| `weights_rom_functions.vh` | INT8 weights as Verilog ROM constants |
| `fixed_mac.v` | Fixed-point multiply-accumulate unit |
| `hidden_neuron.v` | Hidden layer neuron |
| `mlp_hidden_layer.v` | Full hidden layer |
| `output_neuron.v` | Output neuron |
| `relu.v` | ReLU activation |
| `neuron.v` | Generic neuron primitive |
| `prefetch_controller.v` | Issues prefetch requests to cache |
| `prefetch_buffer.v` | Holds pending prefetch addresses |
| `prefetch_filter.v` | Filters redundant or invalid prefetch requests |

Fixed-point specification -- must match `model-training/phase2/fixed_point_spec.txt`:

| Parameter | Value |
|-----------|-------|
| Format | Signed INT8 |
| Representation | Q0.6 |
| Scale factor | 64 |
| Accumulator width | 32-bit signed |
| Post-layer shift | arithmetic right shift by 6 |
| Input encoding | raw delta divided by 4 |
| Output decoding | mlp output multiplied by 4, added to current address |

---

### `model-training/`

Three-phase Python pipeline that produces the INT8 weights loaded into `ml-prefetch-engine`.

```
model-training/
├── phase1/
│   ├── step1_parse_m2_trace.py    # Parses mem_access_log.csv into delta sequence
│   ├── mem_access_log.csv         # Input -- copy from l1-cache/ simulation output
│   ├── raw_trace.csv              # Output
│   ├── delta_trace.csv            # Output -- training dataset
│   └── trace_stats.txt            # Output
├── phase2/
│   ├── step2_train.py             # Trains MLP, quantises to INT8, exports weights
│   ├── prefetch_mlp_fp32.pt       # Full-precision trained weights
│   ├── prefetch_mlp_fp32_best.pt  # Best validation checkpoint
│   ├── weights_int8.json          # INT8 weights -- values go into weights_rom_functions.vh
│   ├── weights_rom.v              # Ready-to-paste Verilog ROM snippet
│   ├── norm_factor.json           # Normalisation factor used at inference time
│   ├── fixed_point_spec.txt       # Fixed-point spec -- must match mlp_pkg1.vh
│   ├── training_loss.png          # Training loss curve
│   └── prediction_accuracy.png   # Prediction accuracy plot
└── phase3/
    ├── step3_oracle.py            # Runs trained model as software oracle
    ├── oracle_predictions.csv     # Oracle prediction log
    └── oracle_vs_hw_report.txt    # Comparison report between oracle and hardware output
```

---

## Setup

**Prerequisites:**
- Vivado 2024.2
- Python 3.9 or later
- PyTorch 2.x, numpy, pandas, matplotlib
- Target part: xc7z010clg400-1 (simulation works without hardware)

**Install Python dependencies:**
```bash
pip install torch numpy pandas matplotlib
```

---

## Reproducing Results

**Step 1: Generate memory trace**
```
1. Open l1-cache Vivado project
2. Run tb_cache simulation
3. mem_access_log.csv is written to the simulation working directory
4. Copy it to model-training/phase1/
```

**Step 2: Train the model**
```bash
python model-training/phase1/step1_parse_m2_trace.py
python model-training/phase2/step2_train.py
python model-training/phase3/step3_oracle.py
```

**Step 3: Update hardware weights**
```
Copy the contents of model-training/phase2/weights_rom.v
into ml-prefetch-engine/weights_rom_functions.vh
```

**Step 4: Run full system simulation**
```
1. Open ml-prefetch-engine/6th_sem_final.xpr in Vivado 2024.2
2. Run tb_cache simulation
3. Console output shows cache statistics and prefetch event counts
```

---

## Module Handoffs

| Source | Destination | Content |
|--------|-------------|---------|
| `l1-cache/mem_access_log.csv` | `model-training/phase1/` | Memory access trace for training |
| `model-training/phase2/weights_rom.v` | `ml-prefetch-engine/weights_rom_functions.vh` | Quantised INT8 weights |
| `riscv-pipeline/data_memory.v` interface | `ml-prefetch-engine/` | Replaced by `l1_cache.v` in integration |
| `ml-prefetch-engine/` pf_req, pf_addr | `l1-cache/l1_cache.v` | Prefetch signals |

---

## Results

| Configuration | Cache Miss Rate | IPC | Estimated Energy |
|---------------|----------------|-----|-----------------|
| No prefetcher | -- | -- | -- |
| Stride prefetcher | -- | -- | -- |
| MLP prefetcher (this work) | -- | -- | -- |

Results to be updated after final simulation run.

---

## Related Work

| Paper | Venue | Relation |
|-------|-------|----------|
| Hashemi et al., "Learning Memory Access Patterns" | ICML 2018 | Foundational LSTM prefetcher |
| Shi et al., "Voyager" | ASPLOS 2021 | Hierarchical neural prefetcher, simulation only |
| Duong et al., "Twilight" | ISCA 2024 | Neural prefetch reformulation, simulation only |
| Wang et al., "LSTM-CRP" | MDPI 2024 | LSTM on RISC-V/FPGA, cache replacement not prefetching |
| Yuan et al., "Joint Learning for Caching and Prefetching" | arXiv 2025 | Joint training approach, simulation only |
| FarSight, "Deep-Learning-Driven Prefetching" | arXiv 2025 | Far memory, microsecond latency constraint |

This project is the first to synthesise a trained neural prefetcher as fixed-point hardware on a RISC-V pipeline targeting nanosecond L1 cache latency constraints.

---

## License

MIT

# M2 — L1 Data Cache

**Owner:** Member 2
**Role:** L1 direct-mapped write-through cache with observation port and prefetch interface

---

## New Files Added by M2

| File | Location | Description |
|------|----------|-------------|
| `l1_cache.v` | `riscv_cache.srcs/sources_1/new/` | L1 cache module |
| `tb_cache.v` | `riscv_cache.srcs/sim_1/new/` | Cache testbench |
| `mem_access_log.csv` | root | CSV trace log — M4's training dataset input |
| `dfx_runtime.txt` | root | Vivado runtime log |
| `vivado.jou` | root | Vivado journal |
| `vivado.log` | root | Vivado log |
| `tb_cache.tcl` | `riscv_cache.sim/sim_1/behav/xsim/` | Simulation TCL script |
| `tb_cache.vcd` | `riscv_cache.sim/sim_1/behav/xsim/` | Waveform dump |
| `tb_cache_behav.wdb` | `riscv_cache.sim/sim_1/behav/xsim/` | Vivado waveform database |

---

## Key Features in l1_cache.v

| Feature | Status |
|---------|--------|
| Direct-mapped cache (16 lines, 4-byte lines) | ✅ Done |
| Write-through, no-write-allocate | ✅ Done |
| Hit/miss FSM (S_IDLE → S_MISS → S_FILL) | ✅ Done |
| Stall signal to pipeline | ✅ Done |
| Observation port (obs_valid, obs_addr, obs_hit, obs_pc) | ✅ Done — feeds M4 trace |
| Performance counters (stat_accesses, stat_hits, stat_misses) | ✅ Done |
| Prefetch port (pf_req, pf_addr) | ✅ Ready — tie pf_req=0 until M3 connects |

---

## Interface to M1 (Pipeline)

| Signal | Direction | Description |
|--------|-----------|-------------|
| `clk`, `rst` | in | Clock and reset |
| `mem_read` | in | Read enable from pipeline |
| `mem_write` | in | Write enable from pipeline |
| `addr` | in | 32-bit memory address |
| `write_data` | in | Data to write |
| `pipeline_pc` | in | PC from EX/MEM stage |
| `read_data` | out | Data returned to pipeline |
| `stall` | out | Stall signal to pipeline hazard unit |

---

## Interface to M3 (Prefetch Engine)

| Signal | Direction | Description |
|--------|-----------|-------------|
| `pf_req` | in | Prefetch request from M3 FSM |
| `pf_addr` | in | Prefetch target address from M3 |

Tie `pf_req = 0` until M3 is ready. Prefetch is silent — no stall on prefetch miss.

---

## Interface to M4 (Trace Dataset)

`mem_access_log.csv` is logged by `tb_cache.v` during simulation.
M4 uses this CSV directly as training data for the MLP model.

Columns: `cycle, pc, addr, hit`

---

## Note on Testbench File Path

Before running `tb_cache.v`, update the hardcoded path to a relative one:
```verilog
// Change this:
log_fd = $fopen("C:/Users/LENOVO/.../mem_access_log.csv", "w");
// To this:
log_fd = $fopen("mem_access_log.csv", "w");
```

## How to Open

Open `riscv_cache.xpr` in Vivado to load the full M2 project.

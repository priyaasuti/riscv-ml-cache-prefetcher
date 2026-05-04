# M1 — RISC-V 5-Stage Pipeline

**Owner:** Member 1
**Role:** Implements the 5-stage RISC-V RV32I pipeline in Verilog

---

## Source Files

Located in `riscv_cache.srcs/sources_1/imports/`

| File | Description |
|------|-------------|
| `pc.v` | Program counter |
| `instruction_memory.v` | Instruction memory (ROM) |
| `imm_gen.v` | Immediate value generator |
| `register_file.v` | 32 general-purpose registers |
| `alu.v` | Arithmetic logic unit |
| `alu_control.v` | ALU control signal decoder |
| `data_memory.v` | Data memory — **handoff point to M2** |
| `forwarding_unit.v` | Data forwarding for RAW hazards |
| `hazard_detection_unit.v` | Stall and flush logic |
| `filesss/control_unit.v` | Main control unit |
| `filesss/datapath.v` | Top-level datapath |
| `filesss/IF_ID_reg.v` | Fetch → Decode pipeline register |
| `filesss/ID_EX_reg.v` | Decode → Execute pipeline register |
| `filesss/EX_MEM_reg.v` | Execute → Memory pipeline register |
| `filesss/MEM_WB_reg.v` | Memory → Writeback pipeline register |

## Testbench

Located in `riscv_cache.srcs/sim_1/imports/tb_riscv_pipeline.v`

## Simulation Outputs

Located in `riscv_cache.sim/sim_1/behav/xsim/`

## Vivado Project

Open `riscv_cache.xpr` in Vivado to load the full project.

---

## Interface to M2

`data_memory.v` is the handoff point to M2.
M2 will wrap this with the L1 cache module.

Signals M2 needs:
- `mem_addr` — address requested by pipeline
- `mem_write_data` — data to write
- `mem_read` — read enable
- `mem_write` — write enable
- `mem_read_data` — data returned to pipeline (M2 drives this)

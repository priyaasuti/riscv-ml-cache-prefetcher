module datapath(input clk, input rst);

// ── WB wiring ─────────────────────────────────────────────
wire [4:0]  MEM_WB_rd;
wire        MEM_WB_reg_write;
wire [31:0] MEM_WB_alu_result, MEM_WB_mem_data;
wire        MEM_WB_mem_to_reg;
wire        MEM_WB_jal, MEM_WB_jalr;
wire [31:0] MEM_WB_pc_plus4;

wire [31:0] wb_write_data =
    (MEM_WB_jal | MEM_WB_jalr) ? MEM_WB_pc_plus4  :
    MEM_WB_mem_to_reg          ? MEM_WB_mem_data  :
                                 MEM_WB_alu_result;

// ── Stall / flush control ─────────────────────────────────
wire pc_write_haz, IF_ID_write_en, load_use_flush;
wire jump_taken, branch_taken;
wire any_taken = jump_taken | branch_taken;

wire cache_stall;

wire global_stall = ~IF_ID_write_en | cache_stall;
wire IF_ID_stall  = global_stall;
wire IF_ID_flush  = any_taken & ~cache_stall;
wire ID_EX_flush  = (load_use_flush | any_taken) & ~cache_stall;
wire EX_MEM_stall = cache_stall;

wire pc_write = pc_write_haz & ~cache_stall;

// ── IF stage ──────────────────────────────────────────────
wire [31:0] next_pc, pc;

pc pc_inst(
    .clk(clk),
    .rst(rst),
    .pc_write(pc_write),
    .next_pc(next_pc),
    .pc_out(pc)
);

wire [31:0] instruction;

instruction_memory imem(
    .addr(pc),
    .instruction(instruction)
);

wire [31:0] IF_ID_pc, IF_ID_instr;

IF_ID_reg ifid(
    .clk(clk),
    .rst(rst),
    .stall(IF_ID_stall),
    .flush(IF_ID_flush),
    .pc_in(pc),
    .instr_in(instruction),
    .pc_out(IF_ID_pc),
    .instr_out(IF_ID_instr)
);

// ── ID stage ──────────────────────────────────────────────
wire [4:0] IF_ID_rs1 = IF_ID_instr[19:15];
wire [4:0] IF_ID_rs2 = IF_ID_instr[24:20];
wire [4:0] IF_ID_rd  = IF_ID_instr[11:7];

wire [31:0] reg_data1, reg_data2;

register_file rf(
    .clk(clk),
    .rst(rst),
    .rs1(IF_ID_rs1),
    .rs2(IF_ID_rs2),
    .rd(MEM_WB_rd),
    .write_data(wb_write_data),
    .reg_write(MEM_WB_reg_write),
    .read_data1(reg_data1),
    .read_data2(reg_data2)
);

wire [31:0] imm_id;

imm_gen ig(
    .instr(IF_ID_instr),
    .imm(imm_id)
);

wire reg_write_id, alu_src_id, mem_read_id, mem_write_id, mem_to_reg_id;
wire branch_id, jal_id, jalr_id, lui_id, auipc_id;
wire beq_id, bne_id, blt_id, bge_id, bltu_id, bgeu_id;
wire [1:0] alu_op_id;

control_unit cu(
    .opcode(IF_ID_instr[6:0]),
    .funct3(IF_ID_instr[14:12]),
    .reg_write(reg_write_id),
    .alu_src(alu_src_id),
    .mem_read(mem_read_id),
    .mem_write(mem_write_id),
    .mem_to_reg(mem_to_reg_id),
    .branch(branch_id),
    .jal(jal_id),
    .jalr(jalr_id),
    .lui(lui_id),
    .auipc(auipc_id),
    .beq(beq_id),
    .bne(bne_id),
    .blt(blt_id),
    .bge(bge_id),
    .bltu(bltu_id),
    .bgeu(bgeu_id),
    .alu_op(alu_op_id)
);

wire [31:0] ID_EX_pc, ID_EX_rs1_data, ID_EX_rs2_data, ID_EX_imm;
wire [4:0]  ID_EX_rd, ID_EX_rs1, ID_EX_rs2;
wire [2:0]  ID_EX_funct3;
wire [6:0]  ID_EX_funct7;

wire ID_EX_reg_write, ID_EX_alu_src, ID_EX_mem_read, ID_EX_mem_write, ID_EX_mem_to_reg;
wire ID_EX_branch, ID_EX_jal, ID_EX_jalr, ID_EX_lui, ID_EX_auipc;
wire ID_EX_beq, ID_EX_bne, ID_EX_blt, ID_EX_bge, ID_EX_bltu, ID_EX_bgeu;
wire [1:0] ID_EX_alu_op;

// ML prefetch wires
wire        ml_pf_req;
wire [31:0] ml_pf_addr;
wire        filtered_pf_req;
wire [31:0] filtered_pf_addr;
wire        cache_pf_req;
wire [31:0] cache_pf_addr;
wire        pf_hit;
wire [31:0] stored_pf_addr;

hazard_detection_unit1 hdu(
    .IF_ID_rs1(IF_ID_rs1),
    .IF_ID_rs2(IF_ID_rs2),
    .ID_EX_rd(ID_EX_rd),
    .ID_EX_mem_read(ID_EX_mem_read),
    .pc_write(pc_write_haz),
    .IF_ID_write(IF_ID_write_en),
    .ID_EX_flush(load_use_flush)
);

ID_EX_reg idex(
    .clk(clk),
    .rst(rst),
    .flush(ID_EX_flush),
    .pc_in(IF_ID_pc),
    .rs1_data_in(reg_data1),
    .rs2_data_in(reg_data2),
    .imm_in(imm_id),
    .rd_in(IF_ID_rd),
    .rs1_in(IF_ID_rs1),
    .rs2_in(IF_ID_rs2),
    .funct3_in(IF_ID_instr[14:12]),
    .funct7_in(IF_ID_instr[31:25]),
    .reg_write_in(reg_write_id),
    .alu_src_in(alu_src_id),
    .mem_read_in(mem_read_id),
    .mem_write_in(mem_write_id),
    .mem_to_reg_in(mem_to_reg_id),
    .branch_in(branch_id),
    .jal_in(jal_id),
    .jalr_in(jalr_id),
    .lui_in(lui_id),
    .auipc_in(auipc_id),
    .beq_in(beq_id),
    .bne_in(bne_id),
    .blt_in(blt_id),
    .bge_in(bge_id),
    .bltu_in(bltu_id),
    .bgeu_in(bgeu_id),
    .alu_op_in(alu_op_id),
    .pc_out(ID_EX_pc),
    .rs1_data_out(ID_EX_rs1_data),
    .rs2_data_out(ID_EX_rs2_data),
    .imm_out(ID_EX_imm),
    .rd_out(ID_EX_rd),
    .rs1_out(ID_EX_rs1),
    .rs2_out(ID_EX_rs2),
    .funct3_out(ID_EX_funct3),
    .funct7_out(ID_EX_funct7),
    .reg_write_out(ID_EX_reg_write),
    .alu_src_out(ID_EX_alu_src),
    .mem_read_out(ID_EX_mem_read),
    .mem_write_out(ID_EX_mem_write),
    .mem_to_reg_out(ID_EX_mem_to_reg),
    .branch_out(ID_EX_branch),
    .jal_out(ID_EX_jal),
    .jalr_out(ID_EX_jalr),
    .lui_out(ID_EX_lui),
    .auipc_out(ID_EX_auipc),
    .beq_out(ID_EX_beq),
    .bne_out(ID_EX_bne),
    .blt_out(ID_EX_blt),
    .bge_out(ID_EX_bge),
    .bltu_out(ID_EX_bltu),
    .bgeu_out(ID_EX_bgeu),
    .alu_op_out(ID_EX_alu_op)
);

// ── EX stage ──────────────────────────────────────────────
wire [4:0]  EX_MEM_rd;
wire        EX_MEM_reg_write;
wire [31:0] EX_MEM_alu_result;

wire [1:0] forwardA, forwardB;

forwarding_unit fwd(
    .ID_EX_rs1(ID_EX_rs1),
    .ID_EX_rs2(ID_EX_rs2),
    .EX_MEM_rd(EX_MEM_rd),
    .EX_MEM_reg_write(EX_MEM_reg_write),
    .MEM_WB_rd(MEM_WB_rd),
    .MEM_WB_reg_write(MEM_WB_reg_write),
    .forwardA(forwardA),
    .forwardB(forwardB)
);

wire [31:0] alu_A_fwd =
    (forwardA == 2'b10) ? EX_MEM_alu_result :
    (forwardA == 2'b01) ? wb_write_data      :
                          ID_EX_rs1_data;

wire [31:0] rs2_fwd =
    (forwardB == 2'b10) ? EX_MEM_alu_result :
    (forwardB == 2'b01) ? wb_write_data      :
                          ID_EX_rs2_data;

wire [31:0] alu_A =
    ID_EX_lui   ? 32'd0    :
    ID_EX_auipc ? ID_EX_pc :
                  alu_A_fwd;

wire [31:0] alu_B = ID_EX_alu_src ? ID_EX_imm : rs2_fwd;

wire [3:0] alu_ctrl;

alu_control alu_ctrlU(
    .alu_op(ID_EX_alu_op),
    .funct3(ID_EX_funct3),
    .funct7(ID_EX_funct7),
    .alu_ctrl(alu_ctrl)
);

wire [31:0] alu_result;
wire        alu_zero;

alu alu_inst(
    .A(alu_A),
    .B(alu_B),
    .alu_ctrl(alu_ctrl),
    .result(alu_result),
    .zero(alu_zero)
);

wire [31:0] pc_plus4    = ID_EX_pc + 32'd4;
wire [31:0] jal_target  = ID_EX_pc + ID_EX_imm;
wire [31:0] jalr_target = {alu_result[31:1], 1'b0};

assign jump_taken = ID_EX_jal | ID_EX_jalr;

// ── EX/MEM register ───────────────────────────────────────
wire [31:0] EX_MEM_rs2_data, EX_MEM_pc_branch, EX_MEM_pc_plus4;
wire [31:0] EX_MEM_jalr_target;
wire        EX_MEM_zero, EX_MEM_mem_read, EX_MEM_mem_write, EX_MEM_mem_to_reg;
wire        EX_MEM_branch, EX_MEM_jal, EX_MEM_jalr;
wire        EX_MEM_beq, EX_MEM_bne, EX_MEM_blt, EX_MEM_bge, EX_MEM_bltu, EX_MEM_bgeu;
wire [31:0] EX_MEM_pc;

EX_MEM_reg exmem(
    .clk(clk),
    .rst(rst),
    .flush(1'b0),
    .stall(EX_MEM_stall),
    .alu_result_in(alu_result),
    .rs2_data_in(rs2_fwd),
    .pc_in(ID_EX_pc),
    .pc_branch_in(jal_target),
    .pc_plus4_in(pc_plus4),
    .jalr_target_in(jalr_target),
    .rd_in(ID_EX_rd),
    .zero_in(alu_zero),
    .reg_write_in(ID_EX_reg_write),
    .mem_read_in(ID_EX_mem_read),
    .mem_write_in(ID_EX_mem_write),
    .mem_to_reg_in(ID_EX_mem_to_reg),
    .branch_in(ID_EX_branch),
    .jal_in(ID_EX_jal),
    .jalr_in(ID_EX_jalr),
    .beq_in(ID_EX_beq),
    .bne_in(ID_EX_bne),
    .blt_in(ID_EX_blt),
    .bge_in(ID_EX_bge),
    .bltu_in(ID_EX_bltu),
    .bgeu_in(ID_EX_bgeu),
    .alu_result_out(EX_MEM_alu_result),
    .rs2_data_out(EX_MEM_rs2_data),
    .pc_out(EX_MEM_pc),
    .pc_branch_out(EX_MEM_pc_branch),
    .pc_plus4_out(EX_MEM_pc_plus4),
    .jalr_target_out(EX_MEM_jalr_target),
    .rd_out(EX_MEM_rd),
    .zero_out(EX_MEM_zero),
    .reg_write_out(EX_MEM_reg_write),
    .mem_read_out(EX_MEM_mem_read),
    .mem_write_out(EX_MEM_mem_write),
    .mem_to_reg_out(EX_MEM_mem_to_reg),
    .branch_out(EX_MEM_branch),
    .jal_out(EX_MEM_jal),
    .jalr_out(EX_MEM_jalr),
    .beq_out(EX_MEM_beq),
    .bne_out(EX_MEM_bne),
    .blt_out(EX_MEM_blt),
    .bge_out(EX_MEM_bge),
    .bltu_out(EX_MEM_bltu),
    .bgeu_out(EX_MEM_bgeu)
);

// ── MEM stage ─────────────────────────────────────────────
wire branch_cond =
    (EX_MEM_beq  &&  EX_MEM_zero)          ||
    (EX_MEM_bne  && !EX_MEM_zero)          ||
    (EX_MEM_blt  &&  EX_MEM_alu_result[0]) ||
    (EX_MEM_bge  && !EX_MEM_alu_result[0]) ||
    (EX_MEM_bltu &&  EX_MEM_alu_result[0]) ||
    (EX_MEM_bgeu && !EX_MEM_alu_result[0]);

assign branch_taken = EX_MEM_branch && branch_cond;

assign next_pc =
    ID_EX_jalr   ? jalr_target      :
    ID_EX_jal    ? jal_target       :
    branch_taken ? EX_MEM_pc_branch :
                   (pc + 32'd4);

// ── ML Prefetcher ─────────────────────────────────────────
ml_prefetcher_m4 ML_PREFETCHER (
    .clk(clk),
    .reset(rst),

    .obs_valid(obs_valid_w),
    .current_addr(EX_MEM_alu_result),

    .pf_req(ml_pf_req),
    .pf_addr(ml_pf_addr),

    .ml_busy(),
    .ml_done(),
    .ml_delta_out()
);

prefetch_filter PREF_FILTER (
    .pf_req_in(ml_pf_req),
    .pf_addr_in(ml_pf_addr),
    .current_addr(EX_MEM_alu_result),
    .pf_req_out(filtered_pf_req),
    .pf_addr_out(filtered_pf_addr)
);

prefetch_controller PREF_CTRL (
    .clk(clk),
    .reset(rst),
    .ml_pf_req(filtered_pf_req),
    .ml_pf_addr(filtered_pf_addr),
    .cache_busy(cache_stall),
    .cache_pf_req(cache_pf_req),
    .cache_pf_addr(cache_pf_addr)
);

prefetch_buffer PREF_BUFFER (
    .clk(clk),
    .reset(rst),
    .pf_req(cache_pf_req),
    .pf_addr(cache_pf_addr),
    .cpu_addr(EX_MEM_alu_result),
    .pf_hit(pf_hit),
    .stored_pf_addr(stored_pf_addr)
);

// ── CACHE: L1 data cache instance ─────────────────────────
wire [31:0] cache_read_data;

wire [31:0] dmem_addr_w;
wire        dmem_read_w, dmem_write_w;
wire [31:0] dmem_write_data_w;
wire [31:0] dmem_read_data_w;

wire        obs_valid_w;
wire [31:0] obs_addr_w, obs_pc_w;
wire        obs_hit_w;

wire [31:0] stat_accesses_w, stat_hits_w, stat_misses_w;
wire        pf_accepted_w;
wire        pf_filled_w;
wire [31:0] pf_filled_addr_w;
l1_cache #(.LINES(16), .OFFSET(2)) dcache (
    .clk(clk),
    .rst(rst),

    .mem_read(EX_MEM_mem_read),
    .mem_write(EX_MEM_mem_write),
    .addr(EX_MEM_alu_result),
    .write_data(EX_MEM_rs2_data),
    .read_data(cache_read_data),
    .stall(cache_stall),

    .dmem_addr(dmem_addr_w),
    .dmem_read(dmem_read_w),
    .dmem_write(dmem_write_w),
    .dmem_write_data(dmem_write_data_w),
    .dmem_read_data(dmem_read_data_w),

    .obs_valid(obs_valid_w),
    .obs_addr(obs_addr_w),
    .obs_hit(obs_hit_w),
    .obs_pc(obs_pc_w),

    // ML prefetch connected here
    .pf_req(cache_pf_req),
    .pf_addr(cache_pf_addr),

    // Prefetch debug proof signals
    .pf_accepted(pf_accepted_w),
    .pf_filled(pf_filled_w),
    .pf_filled_addr(pf_filled_addr_w),

    .stat_accesses(stat_accesses_w),
    .stat_hits(stat_hits_w),
    .stat_misses(stat_misses_w),

    .pipeline_pc(EX_MEM_pc)
);

// ── Backing data memory ───────────────────────────────────
data_memory dmem(
    .clk(clk),
    .mem_read(dmem_read_w),
    .mem_write(dmem_write_w),
    .addr(dmem_addr_w),
    .write_data(dmem_write_data_w),
    .read_data(dmem_read_data_w)
);

// ── MEM/WB register ───────────────────────────────────────
MEM_WB_reg memwb(
    .clk(clk),
    .rst(rst),
    .stall(cache_stall),
    .alu_result_in(EX_MEM_alu_result),
    .mem_data_in(cache_read_data),
    .rd_in(EX_MEM_rd),
    .pc_plus4_in(EX_MEM_pc_plus4),
    .jal_in(EX_MEM_jal),
    .jalr_in(EX_MEM_jalr),
    .reg_write_in(EX_MEM_reg_write),
    .mem_to_reg_in(EX_MEM_mem_to_reg),
    .alu_result_out(MEM_WB_alu_result),
    .mem_data_out(MEM_WB_mem_data),
    .rd_out(MEM_WB_rd),
    .pc_plus4_out(MEM_WB_pc_plus4),
    .jal_out(MEM_WB_jal),
    .jalr_out(MEM_WB_jalr),
    .reg_write_out(MEM_WB_reg_write),
    .mem_to_reg_out(MEM_WB_mem_to_reg)
);

endmodule
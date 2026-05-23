// ============================================================
// datapath.v  -  Complete 5-stage RISC-V pipeline datapath
//
// FIXES applied vs original:
//   FIX 1 – JAL/JALR write PC+4 to rd (return address)
//   FIX 2 – JALR uses alu_result (rs1+imm) as target, not PC+imm
//   FIX 3 – LUI/AUIPC: lui forces alu_A=0; auipc forces alu_A=PC
//   FIX 4 – JAL/JALR resolved in EX stage (not MEM)
//            → exactly 2 flush cycles, no self-defeating flush of EX/MEM
// ============================================================
module datapath(input clk, input rst);

wire [4:0]  MEM_WB_rd;
wire        MEM_WB_reg_write;
wire [31:0] MEM_WB_alu_result, MEM_WB_mem_data;
wire        MEM_WB_mem_to_reg;
wire        MEM_WB_jal, MEM_WB_jalr;
wire [31:0] MEM_WB_pc_plus4;

// FIX 1: three-way WB mux
wire [31:0] wb_write_data =
    (MEM_WB_jal | MEM_WB_jalr) ? MEM_WB_pc_plus4  :
    MEM_WB_mem_to_reg           ? MEM_WB_mem_data  :
                                  MEM_WB_alu_result;

wire pc_write, IF_ID_write_en, load_use_flush;
wire jump_taken, branch_taken;
wire any_taken    = jump_taken | branch_taken;
wire IF_ID_stall  = ~IF_ID_write_en;
wire IF_ID_flush  = any_taken;
wire ID_EX_flush  = load_use_flush | any_taken;

// ---- IF ----
wire [31:0] next_pc, pc;
pc pc_inst(.clk(clk),.rst(rst),.pc_write(pc_write),.next_pc(next_pc),.pc_out(pc));

wire [31:0] instruction;
instruction_memory imem(.addr(pc),.instruction(instruction));

wire [31:0] IF_ID_pc, IF_ID_instr;
IF_ID_reg ifid(
    .clk(clk),.rst(rst),.stall(IF_ID_stall),.flush(IF_ID_flush),
    .pc_in(pc),.instr_in(instruction),.pc_out(IF_ID_pc),.instr_out(IF_ID_instr));

// ---- ID ----
wire [4:0] IF_ID_rs1 = IF_ID_instr[19:15];
wire [4:0] IF_ID_rs2 = IF_ID_instr[24:20];
wire [4:0] IF_ID_rd  = IF_ID_instr[11:7];

wire [31:0] reg_data1, reg_data2;
register_file rf(
    .clk(clk),.rst(rst),
    .rs1(IF_ID_rs1),.rs2(IF_ID_rs2),
    .rd(MEM_WB_rd),.write_data(wb_write_data),.reg_write(MEM_WB_reg_write),
    .read_data1(reg_data1),.read_data2(reg_data2));

wire [31:0] imm_id;
imm_gen ig(.instr(IF_ID_instr),.imm(imm_id));

wire reg_write_id,alu_src_id,mem_read_id,mem_write_id,mem_to_reg_id;
wire branch_id,jal_id,jalr_id,lui_id,auipc_id;
wire beq_id,bne_id,blt_id,bge_id,bltu_id,bgeu_id;
wire [1:0] alu_op_id;
control_unit cu(
    .opcode(IF_ID_instr[6:0]),.funct3(IF_ID_instr[14:12]),
    .reg_write(reg_write_id),.alu_src(alu_src_id),
    .mem_read(mem_read_id),.mem_write(mem_write_id),.mem_to_reg(mem_to_reg_id),
    .branch(branch_id),.jal(jal_id),.jalr(jalr_id),
    .lui(lui_id),.auipc(auipc_id),
    .beq(beq_id),.bne(bne_id),.blt(blt_id),
    .bge(bge_id),.bltu(bltu_id),.bgeu(bgeu_id),
    .alu_op(alu_op_id));

wire [31:0] ID_EX_pc,ID_EX_rs1_data,ID_EX_rs2_data,ID_EX_imm;
wire [4:0]  ID_EX_rd,ID_EX_rs1,ID_EX_rs2;
wire [2:0]  ID_EX_funct3;
wire [6:0]  ID_EX_funct7;
wire ID_EX_reg_write,ID_EX_alu_src,ID_EX_mem_read,ID_EX_mem_write,ID_EX_mem_to_reg;
wire ID_EX_branch,ID_EX_jal,ID_EX_jalr,ID_EX_lui,ID_EX_auipc;
wire ID_EX_beq,ID_EX_bne,ID_EX_blt,ID_EX_bge,ID_EX_bltu,ID_EX_bgeu;
wire [1:0] ID_EX_alu_op;

hazard_detection_unit1 hdu(
    .IF_ID_rs1(IF_ID_rs1),.IF_ID_rs2(IF_ID_rs2),
    .ID_EX_rd(ID_EX_rd),.ID_EX_mem_read(ID_EX_mem_read),
    .pc_write(pc_write),.IF_ID_write(IF_ID_write_en),.ID_EX_flush(load_use_flush));

ID_EX_reg idex(
    .clk(clk),.rst(rst),.flush(ID_EX_flush),
    .pc_in(IF_ID_pc),.rs1_data_in(reg_data1),.rs2_data_in(reg_data2),
    .imm_in(imm_id),.rd_in(IF_ID_rd),.rs1_in(IF_ID_rs1),.rs2_in(IF_ID_rs2),
    .funct3_in(IF_ID_instr[14:12]),.funct7_in(IF_ID_instr[31:25]),
    .reg_write_in(reg_write_id),.alu_src_in(alu_src_id),
    .mem_read_in(mem_read_id),.mem_write_in(mem_write_id),.mem_to_reg_in(mem_to_reg_id),
    .branch_in(branch_id),.jal_in(jal_id),.jalr_in(jalr_id),
    .lui_in(lui_id),.auipc_in(auipc_id),
    .beq_in(beq_id),.bne_in(bne_id),.blt_in(blt_id),
    .bge_in(bge_id),.bltu_in(bltu_id),.bgeu_in(bgeu_id),
    .alu_op_in(alu_op_id),
    .pc_out(ID_EX_pc),.rs1_data_out(ID_EX_rs1_data),.rs2_data_out(ID_EX_rs2_data),
    .imm_out(ID_EX_imm),.rd_out(ID_EX_rd),.rs1_out(ID_EX_rs1),.rs2_out(ID_EX_rs2),
    .funct3_out(ID_EX_funct3),.funct7_out(ID_EX_funct7),
    .reg_write_out(ID_EX_reg_write),.alu_src_out(ID_EX_alu_src),
    .mem_read_out(ID_EX_mem_read),.mem_write_out(ID_EX_mem_write),.mem_to_reg_out(ID_EX_mem_to_reg),
    .branch_out(ID_EX_branch),.jal_out(ID_EX_jal),.jalr_out(ID_EX_jalr),
    .lui_out(ID_EX_lui),.auipc_out(ID_EX_auipc),
    .beq_out(ID_EX_beq),.bne_out(ID_EX_bne),.blt_out(ID_EX_blt),
    .bge_out(ID_EX_bge),.bltu_out(ID_EX_bltu),.bgeu_out(ID_EX_bgeu),
    .alu_op_out(ID_EX_alu_op));

// ---- EX ----
wire [4:0]  EX_MEM_rd;
wire        EX_MEM_reg_write;
wire [31:0] EX_MEM_alu_result;

wire [1:0] forwardA, forwardB;
forwarding_unit fwd(
    .ID_EX_rs1(ID_EX_rs1),.ID_EX_rs2(ID_EX_rs2),
    .EX_MEM_rd(EX_MEM_rd),.EX_MEM_reg_write(EX_MEM_reg_write),
    .MEM_WB_rd(MEM_WB_rd),.MEM_WB_reg_write(MEM_WB_reg_write),
    .forwardA(forwardA),.forwardB(forwardB));

wire [31:0] alu_A_fwd =
    (forwardA==2'b10) ? EX_MEM_alu_result :
    (forwardA==2'b01) ? wb_write_data      : ID_EX_rs1_data;

wire [31:0] rs2_fwd =
    (forwardB==2'b10) ? EX_MEM_alu_result :
    (forwardB==2'b01) ? wb_write_data      : ID_EX_rs2_data;

// FIX 3
wire [31:0] alu_A =
    ID_EX_lui   ? 32'd0     :
    ID_EX_auipc ? ID_EX_pc  : alu_A_fwd;

wire [31:0] alu_B = ID_EX_alu_src ? ID_EX_imm : rs2_fwd;

wire [3:0]  alu_ctrl;
alu_control alu_ctrlU(.alu_op(ID_EX_alu_op),.funct3(ID_EX_funct3),.funct7(ID_EX_funct7),.alu_ctrl(alu_ctrl));

wire [31:0] alu_result;
wire        alu_zero;
alu alu_inst(.A(alu_A),.B(alu_B),.alu_ctrl(alu_ctrl),.result(alu_result),.zero(alu_zero));

wire [31:0] pc_plus4    = ID_EX_pc + 32'd4;           // FIX 1: return addr
wire [31:0] jal_target  = ID_EX_pc + ID_EX_imm;       // FIX 4: JAL  in EX
wire [31:0] jalr_target = {alu_result[31:1], 1'b0};   // FIX 2: JALR in EX

// FIX 4: jumps resolved here in EX
assign jump_taken = ID_EX_jal | ID_EX_jalr;

wire [31:0] EX_MEM_rs2_data, EX_MEM_pc_branch, EX_MEM_pc_plus4;
wire [31:0] EX_MEM_jalr_target;
wire EX_MEM_zero,EX_MEM_mem_read,EX_MEM_mem_write,EX_MEM_mem_to_reg;
wire EX_MEM_branch,EX_MEM_jal,EX_MEM_jalr;
wire EX_MEM_beq,EX_MEM_bne,EX_MEM_blt,EX_MEM_bge,EX_MEM_bltu,EX_MEM_bgeu;

EX_MEM_reg exmem(
    .clk(clk),.rst(rst),.flush(1'b0),  // FIX 4: never flush EX/MEM
    .alu_result_in(alu_result),.rs2_data_in(rs2_fwd),
    .pc_branch_in(jal_target),         // branch target (reused for JAL in EX, branches use their own)
    .pc_plus4_in(pc_plus4),            // FIX 1
    .jalr_target_in(jalr_target),      // FIX 2
    .rd_in(ID_EX_rd),.zero_in(alu_zero),
    .reg_write_in(ID_EX_reg_write),.mem_read_in(ID_EX_mem_read),
    .mem_write_in(ID_EX_mem_write),.mem_to_reg_in(ID_EX_mem_to_reg),
    .branch_in(ID_EX_branch),.jal_in(ID_EX_jal),.jalr_in(ID_EX_jalr),
    .beq_in(ID_EX_beq),.bne_in(ID_EX_bne),.blt_in(ID_EX_blt),
    .bge_in(ID_EX_bge),.bltu_in(ID_EX_bltu),.bgeu_in(ID_EX_bgeu),
    .alu_result_out(EX_MEM_alu_result),.rs2_data_out(EX_MEM_rs2_data),
    .pc_branch_out(EX_MEM_pc_branch),.pc_plus4_out(EX_MEM_pc_plus4),
    .jalr_target_out(EX_MEM_jalr_target),
    .rd_out(EX_MEM_rd),.zero_out(EX_MEM_zero),
    .reg_write_out(EX_MEM_reg_write),.mem_read_out(EX_MEM_mem_read),
    .mem_write_out(EX_MEM_mem_write),.mem_to_reg_out(EX_MEM_mem_to_reg),
    .branch_out(EX_MEM_branch),.jal_out(EX_MEM_jal),.jalr_out(EX_MEM_jalr),
    .beq_out(EX_MEM_beq),.bne_out(EX_MEM_bne),.blt_out(EX_MEM_blt),
    .bge_out(EX_MEM_bge),.bltu_out(EX_MEM_bltu),.bgeu_out(EX_MEM_bgeu));

// ---- MEM ----
wire branch_cond =
    (EX_MEM_beq  &&  EX_MEM_zero)          ||
    (EX_MEM_bne  && !EX_MEM_zero)          ||
    (EX_MEM_blt  &&  EX_MEM_alu_result[0]) ||
    (EX_MEM_bge  && !EX_MEM_alu_result[0]) ||
    (EX_MEM_bltu &&  EX_MEM_alu_result[0]) ||
    (EX_MEM_bgeu && !EX_MEM_alu_result[0]);

assign branch_taken = EX_MEM_branch && branch_cond;

// FIX 4: PC next-value priority
assign next_pc =
    ID_EX_jalr   ? jalr_target      :   // JALR in EX
    ID_EX_jal    ? jal_target       :   // JAL  in EX
    branch_taken ? EX_MEM_pc_branch :   // branch in MEM
                   (pc + 32'd4);

wire [31:0] mem_data;
data_memory dmem(
    .clk(clk),.mem_read(EX_MEM_mem_read),.mem_write(EX_MEM_mem_write),
    .addr(EX_MEM_alu_result),.write_data(EX_MEM_rs2_data),.read_data(mem_data));

MEM_WB_reg memwb(
    .clk(clk),.rst(rst),
    .alu_result_in(EX_MEM_alu_result),.mem_data_in(mem_data),.rd_in(EX_MEM_rd),
    .pc_plus4_in(EX_MEM_pc_plus4),.jal_in(EX_MEM_jal),.jalr_in(EX_MEM_jalr),
    .reg_write_in(EX_MEM_reg_write),.mem_to_reg_in(EX_MEM_mem_to_reg),
    .alu_result_out(MEM_WB_alu_result),.mem_data_out(MEM_WB_mem_data),.rd_out(MEM_WB_rd),
    .pc_plus4_out(MEM_WB_pc_plus4),.jal_out(MEM_WB_jal),.jalr_out(MEM_WB_jalr),
    .reg_write_out(MEM_WB_reg_write),.mem_to_reg_out(MEM_WB_mem_to_reg));

endmodule

// ============================================================
// ID_EX_reg.v  -  ID/EX pipeline register
//   flush=1 : insert bubble (zero all control sigs)
//
// CHANGES vs original:
//   Added lui_in/lui_out and auipc_in/auipc_out  (FIX 3)
// ============================================================
module ID_EX_reg(
    input         clk,
    input         rst,
    input         flush,
    // ---- datapath inputs ----
    input  [31:0] pc_in,
    input  [31:0] rs1_data_in,
    input  [31:0] rs2_data_in,
    input  [31:0] imm_in,
    input  [4:0]  rd_in,
    input  [4:0]  rs1_in,
    input  [4:0]  rs2_in,
    input  [2:0]  funct3_in,
    input  [6:0]  funct7_in,
    // ---- control inputs ----
    input         reg_write_in,
    input         alu_src_in,
    input         mem_read_in,
    input         mem_write_in,
    input         mem_to_reg_in,
    input         branch_in,
    input         jal_in,
    input         jalr_in,
    input         lui_in,    // FIX 3
    input         auipc_in,  // FIX 3
    input         beq_in, bne_in, blt_in, bge_in, bltu_in, bgeu_in,
    input  [1:0]  alu_op_in,
    // ---- datapath outputs ----
    output reg [31:0] pc_out,
    output reg [31:0] rs1_data_out,
    output reg [31:0] rs2_data_out,
    output reg [31:0] imm_out,
    output reg [4:0]  rd_out,
    output reg [4:0]  rs1_out,
    output reg [4:0]  rs2_out,
    output reg [2:0]  funct3_out,
    output reg [6:0]  funct7_out,
    // ---- control outputs ----
    output reg        reg_write_out,
    output reg        alu_src_out,
    output reg        mem_read_out,
    output reg        mem_write_out,
    output reg        mem_to_reg_out,
    output reg        branch_out,
    output reg        jal_out,
    output reg        jalr_out,
    output reg        lui_out,    // FIX 3
    output reg        auipc_out,  // FIX 3
    output reg        beq_out, bne_out, blt_out, bge_out, bltu_out, bgeu_out,
    output reg [1:0]  alu_op_out
);

always @(posedge clk or posedge rst) begin
    if (rst || flush) begin
        pc_out        <= 0; rs1_data_out <= 0; rs2_data_out <= 0;
        imm_out       <= 0; rd_out       <= 0;
        rs1_out       <= 0; rs2_out      <= 0;
        funct3_out    <= 0; funct7_out   <= 0;
        reg_write_out <= 0; alu_src_out  <= 0;
        mem_read_out  <= 0; mem_write_out <= 0; mem_to_reg_out <= 0;
        branch_out    <= 0; jal_out      <= 0; jalr_out  <= 0;
        lui_out       <= 0; auipc_out    <= 0;  // FIX 3
        beq_out  <= 0; bne_out  <= 0; blt_out  <= 0;
        bge_out  <= 0; bltu_out <= 0; bgeu_out <= 0;
        alu_op_out <= 0;
    end else begin
        pc_out        <= pc_in;
        rs1_data_out  <= rs1_data_in;
        rs2_data_out  <= rs2_data_in;
        imm_out       <= imm_in;
        rd_out        <= rd_in;
        rs1_out       <= rs1_in;
        rs2_out       <= rs2_in;
        funct3_out    <= funct3_in;
        funct7_out    <= funct7_in;
        reg_write_out <= reg_write_in;
        alu_src_out   <= alu_src_in;
        mem_read_out  <= mem_read_in;
        mem_write_out <= mem_write_in;
        mem_to_reg_out<= mem_to_reg_in;
        branch_out    <= branch_in;
        jal_out       <= jal_in;
        jalr_out      <= jalr_in;
        lui_out       <= lui_in;    // FIX 3
        auipc_out     <= auipc_in;  // FIX 3
        beq_out  <= beq_in;  bne_out  <= bne_in;  blt_out  <= blt_in;
        bge_out  <= bge_in;  bltu_out <= bltu_in; bgeu_out <= bgeu_in;
        alu_op_out <= alu_op_in;
    end
end

endmodule

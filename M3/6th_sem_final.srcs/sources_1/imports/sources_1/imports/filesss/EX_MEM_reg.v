//// ============================================================
//// EX_MEM_reg.v  -  EX/MEM pipeline register
////
//// CHANGES vs original:
////   Added pc_plus4_in/out  (FIX 1: carry return address)
////   Added jalr_target_in/out (FIX 2: carry JALR target)
////   flush input kept for compatibility but tied to 0 in datapath
////   (FIX 4: datapath connects flush=1'b0 so this reg is never
////    flushed — flushing it was killing jal/jalr signals)
//// ============================================================
//module EX_MEM_reg(
//    input         clk,
//    input         rst,
//    input         flush,
//    // ---- datapath inputs ----
//    input  [31:0] alu_result_in,
//    input  [31:0] rs2_data_in,
//    input  [31:0] pc_branch_in,
//    input  [31:0] pc_plus4_in,      // FIX 1
//    input  [31:0] jalr_target_in,   // FIX 2
//    input  [4:0]  rd_in,
//    input         zero_in,
//    // ---- control inputs ----
//    input         reg_write_in,
//    input         mem_read_in,
//    input         mem_write_in,
//    input         mem_to_reg_in,
//    input         branch_in,
//    input         jal_in,
//    input         jalr_in,
//    input         beq_in, bne_in, blt_in, bge_in, bltu_in, bgeu_in,
//    // ---- datapath outputs ----
//    output reg [31:0] alu_result_out,
//    output reg [31:0] rs2_data_out,
//    output reg [31:0] pc_branch_out,
//    output reg [31:0] pc_plus4_out,     // FIX 1
//    output reg [31:0] jalr_target_out,  // FIX 2
//    output reg [4:0]  rd_out,
//    output reg        zero_out,
//    // ---- control outputs ----
//    output reg        reg_write_out,
//    output reg        mem_read_out,
//    output reg        mem_write_out,
//    output reg        mem_to_reg_out,
//    output reg        branch_out,
//    output reg        jal_out,
//    output reg        jalr_out,
//    output reg        beq_out, bne_out, blt_out, bge_out, bltu_out, bgeu_out
//);

//always @(posedge clk or posedge rst) begin
//    if (rst || flush) begin
//        alu_result_out  <= 0; rs2_data_out    <= 0;
//        pc_branch_out   <= 0; pc_plus4_out    <= 0;  // FIX 1
//        jalr_target_out <= 0;                         // FIX 2
//        rd_out          <= 0; zero_out        <= 0;
//        reg_write_out   <= 0; mem_read_out    <= 0;
//        mem_write_out   <= 0; mem_to_reg_out  <= 0;
//        branch_out <= 0; jal_out <= 0; jalr_out <= 0;
//        beq_out  <= 0; bne_out  <= 0; blt_out  <= 0;
//        bge_out  <= 0; bltu_out <= 0; bgeu_out <= 0;
//    end else begin
//        alu_result_out  <= alu_result_in;
//        rs2_data_out    <= rs2_data_in;
//        pc_branch_out   <= pc_branch_in;
//        pc_plus4_out    <= pc_plus4_in;      // FIX 1
//        jalr_target_out <= jalr_target_in;   // FIX 2
//        rd_out          <= rd_in;
//        zero_out        <= zero_in;
//        reg_write_out   <= reg_write_in;
//        mem_read_out    <= mem_read_in;
//        mem_write_out   <= mem_write_in;
//        mem_to_reg_out  <= mem_to_reg_in;
//        branch_out  <= branch_in;
//        jal_out     <= jal_in;
//        jalr_out    <= jalr_in;
//        beq_out  <= beq_in;  bne_out  <= bne_in;  blt_out  <= blt_in;
//        bge_out  <= bge_in;  bltu_out <= bltu_in; bgeu_out <= bgeu_in;
//    end
//end

//endmodule
// ============================================================
// EX_MEM_reg.v  -  EX/MEM pipeline register
//
// CACHE CHANGE: Added stall input port.
//   stall=1  → hold all outputs (freeze the register)
//   flush=1  → clear all outputs to zero/NOP
//   Flush takes priority over stall.
//
// All other signals unchanged from original.
// ============================================================
module EX_MEM_reg(
    input         clk,
    input         rst,
    input         flush,
    input         stall,     // CACHE: new - freeze on cache miss

    // ---- datapath inputs ----
    input  [31:0] alu_result_in,
    input  [31:0] rs2_data_in,
    input  [31:0] pc_in,          // CACHE: PC of instruction
    input  [31:0] pc_branch_in,
    input  [31:0] pc_plus4_in,
    input  [31:0] jalr_target_in,
    input  [4:0]  rd_in,
    input         zero_in,

    // ---- control inputs ----
    input         reg_write_in,
    input         mem_read_in,
    input         mem_write_in,
    input         mem_to_reg_in,
    input         branch_in,
    input         jal_in,
    input         jalr_in,
    input         beq_in, bne_in, blt_in, bge_in, bltu_in, bgeu_in,

    // ---- datapath outputs ----
    output reg [31:0] alu_result_out,
    output reg [31:0] rs2_data_out,
    output reg [31:0] pc_out,         // CACHE: PC of instruction
    output reg [31:0] pc_branch_out,
    output reg [31:0] pc_plus4_out,
    output reg [31:0] jalr_target_out,
    output reg [4:0]  rd_out,
    output reg        zero_out,

    // ---- control outputs ----
    output reg        reg_write_out,
    output reg        mem_read_out,
    output reg        mem_write_out,
    output reg        mem_to_reg_out,
    output reg        branch_out,
    output reg        jal_out,
    output reg        jalr_out,
    output reg        beq_out, bne_out, blt_out, bge_out, bltu_out, bgeu_out
);

always @(posedge clk or posedge rst) begin
    if (rst || flush) begin
        alu_result_out  <= 0; rs2_data_out    <= 0;
        pc_out          <= 0;                       // CACHE
        pc_branch_out   <= 0; pc_plus4_out    <= 0;
        jalr_target_out <= 0;
        rd_out          <= 0; zero_out        <= 0;
        reg_write_out   <= 0; mem_read_out    <= 0;
        mem_write_out   <= 0; mem_to_reg_out  <= 0;
        branch_out      <= 0; jal_out         <= 0; jalr_out <= 0;
        beq_out  <= 0; bne_out  <= 0; blt_out  <= 0;
        bge_out  <= 0; bltu_out <= 0; bgeu_out <= 0;
    end else if (!stall) begin   // CACHE: only advance when not stalling
        alu_result_out  <= alu_result_in;
        rs2_data_out    <= rs2_data_in;
        pc_out          <= pc_in;                   // CACHE
        pc_branch_out   <= pc_branch_in;
        pc_plus4_out    <= pc_plus4_in;
        jalr_target_out <= jalr_target_in;
        rd_out          <= rd_in;
        zero_out        <= zero_in;
        reg_write_out   <= reg_write_in;
        mem_read_out    <= mem_read_in;
        mem_write_out   <= mem_write_in;
        mem_to_reg_out  <= mem_to_reg_in;
        branch_out      <= branch_in;
        jal_out         <= jal_in;
        jalr_out        <= jalr_in;
        beq_out  <= beq_in;  bne_out  <= bne_in;  blt_out  <= blt_in;
        bge_out  <= bge_in;  bltu_out <= bltu_in; bgeu_out <= bgeu_in;
    end
    // else stall=1, flush=0: hold all outputs unchanged
end

endmodule
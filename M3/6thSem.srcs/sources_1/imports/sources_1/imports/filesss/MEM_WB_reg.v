//// ============================================================
//// MEM_WB_reg.v  -  MEM/WB pipeline register
////
//// CHANGES vs original:
////   Added pc_plus4_in/out  (FIX 1: carry return address to WB)
////   Added jal_in/out and jalr_in/out  (FIX 1: WB mux selector)
//// ============================================================
//module MEM_WB_reg(
//    input         clk,
//    input         rst,
//    // ---- datapath inputs ----
//    input  [31:0] alu_result_in,
//    input  [31:0] mem_data_in,
//    input  [4:0]  rd_in,
//    input  [31:0] pc_plus4_in,   // FIX 1
//    // ---- control inputs ----
//    input         reg_write_in,
//    input         mem_to_reg_in,
//    input         jal_in,        // FIX 1
//    input         jalr_in,       // FIX 1
//    // ---- datapath outputs ----
//    output reg [31:0] alu_result_out,
//    output reg [31:0] mem_data_out,
//    output reg [4:0]  rd_out,
//    output reg [31:0] pc_plus4_out,  // FIX 1
//    // ---- control outputs ----
//    output reg        reg_write_out,
//    output reg        mem_to_reg_out,
//    output reg        jal_out,       // FIX 1
//    output reg        jalr_out       // FIX 1
//);

//always @(posedge clk or posedge rst) begin
//    if (rst) begin
//        alu_result_out <= 0; mem_data_out  <= 0;
//        rd_out         <= 0; pc_plus4_out  <= 0;  // FIX 1
//        reg_write_out  <= 0; mem_to_reg_out <= 0;
//        jal_out        <= 0; jalr_out      <= 0;  // FIX 1
//    end else begin
//        alu_result_out <= alu_result_in;
//        mem_data_out   <= mem_data_in;
//        rd_out         <= rd_in;
//        pc_plus4_out   <= pc_plus4_in;   // FIX 1
//        reg_write_out  <= reg_write_in;
//        mem_to_reg_out <= mem_to_reg_in;
//        jal_out        <= jal_in;        // FIX 1
//        jalr_out       <= jalr_in;       // FIX 1
//    end
//end

//endmodule
// ============================================================
// MEM_WB_reg.v  -  MEM/WB pipeline register
//
// CACHE CHANGE: Added stall input.
//   stall=1  → hold all outputs (freeze during cache miss)
//   rst=1    → clear all outputs
//
// Original signals (pc_plus4, jal, jalr) unchanged.
// ============================================================
module MEM_WB_reg(
    input         clk,
    input         rst,
    input         stall,         // CACHE: new - freeze on cache miss

    // ---- datapath inputs ----
    input  [31:0] alu_result_in,
    input  [31:0] mem_data_in,
    input  [4:0]  rd_in,
    input  [31:0] pc_plus4_in,

    // ---- control inputs ----
    input         reg_write_in,
    input         mem_to_reg_in,
    input         jal_in,
    input         jalr_in,

    // ---- datapath outputs ----
    output reg [31:0] alu_result_out,
    output reg [31:0] mem_data_out,
    output reg [4:0]  rd_out,
    output reg [31:0] pc_plus4_out,

    // ---- control outputs ----
    output reg        reg_write_out,
    output reg        mem_to_reg_out,
    output reg        jal_out,
    output reg        jalr_out
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        alu_result_out <= 0; mem_data_out  <= 0;
        rd_out         <= 0; pc_plus4_out  <= 0;
        reg_write_out  <= 0; mem_to_reg_out <= 0;
        jal_out        <= 0; jalr_out      <= 0;
    end else if (!stall) begin   // CACHE: only advance when not stalling
        alu_result_out <= alu_result_in;
        mem_data_out   <= mem_data_in;
        rd_out         <= rd_in;
        pc_plus4_out   <= pc_plus4_in;
        reg_write_out  <= reg_write_in;
        mem_to_reg_out <= mem_to_reg_in;
        jal_out        <= jal_in;
        jalr_out       <= jalr_in;
    end
    // else stall=1: hold all outputs unchanged
end

endmodule
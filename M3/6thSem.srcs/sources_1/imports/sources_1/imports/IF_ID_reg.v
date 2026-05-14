// ============================================================
// IF_ID_reg.v  —  IF/ID pipeline register
//   stall=1 : hold current values (freeze)
//   flush=1 : insert NOP (branch/jump taken)
// ============================================================
module IF_ID_reg(
    input         clk,
    input         rst,
    input         stall,   // from hazard unit
    input         flush,   // from branch/jump logic
    input  [31:0] pc_in,
    input  [31:0] instr_in,
    output reg [31:0] pc_out,
    output reg [31:0] instr_out
);

always @(posedge clk or posedge rst) begin
    if (rst || flush) begin
        pc_out    <= 32'd0;
        instr_out <= 32'h00000013; // NOP  (addi x0,x0,0)
    end else if (!stall) begin
        pc_out    <= pc_in;
        instr_out <= instr_in;
    end
    // stall: keep outputs unchanged
end

endmodule

// ============================================================
// register_file.v  —  32 x 32-bit register file
// Write on negedge so WB data is visible to ID in same cycle
// x0 is hardwired to 0
// ============================================================
module register_file(
    input         clk,
    input         rst,
    input  [4:0]  rs1,
    input  [4:0]  rs2,
    input  [4:0]  rd,
    input  [31:0] write_data,
    input         reg_write,
    output [31:0] read_data1,
    output [31:0] read_data2
);

reg [31:0] regs [0:31];
integer i;

always @(negedge clk or posedge rst) begin
    if (rst) begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] <= 32'd0;
    end else if (reg_write && rd != 5'd0) begin
        regs[rd] <= write_data;
    end
end

// Combinational read; x0 always 0
assign read_data1 = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
assign read_data2 = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

endmodule

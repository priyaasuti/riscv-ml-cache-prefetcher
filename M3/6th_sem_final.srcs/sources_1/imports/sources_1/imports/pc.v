// ============================================================
// pc.v  —  Program Counter
// Supports stall (pc_write=0 holds PC) and flush/branch load
// ============================================================
module pc(
    input         clk,
    input         rst,
    input         pc_write,    // 0 = stall (hold current PC)
    input  [31:0] next_pc,
    output reg [31:0] pc_out
);

always @(posedge clk or posedge rst) begin
    if (rst)
        pc_out <= 32'd0;
    else if (pc_write)
        pc_out <= next_pc;
    // else: stall — keep pc_out unchanged
end

endmodule

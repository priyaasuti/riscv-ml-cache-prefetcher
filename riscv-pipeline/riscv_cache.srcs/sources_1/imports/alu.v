// ============================================================
// alu.v  —  32-bit ALU
// ============================================================
module alu(
    input  [31:0] A,
    input  [31:0] B,
    input  [3:0]  alu_ctrl,
    output reg [31:0] result,
    output        zero
);

always @(*) begin
    case (alu_ctrl)
        4'b0000: result = A + B;
        4'b0001: result = A - B;
        4'b0010: result = A & B;
        4'b0011: result = A | B;
        4'b0100: result = A ^ B;
        4'b0101: result = A << B[4:0];
        4'b0110: result = A >> B[4:0];
        4'b0111: result = $signed(A) >>> B[4:0];
        4'b1000: result = ($signed(A) < $signed(B)) ? 32'd1 : 32'd0;
        4'b1001: result = (A < B)                  ? 32'd1 : 32'd0;
        default: result = 32'd0;
    endcase
end

assign zero = (result == 32'd0);

endmodule

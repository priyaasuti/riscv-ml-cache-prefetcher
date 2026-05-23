// ============================================================
// alu_control.v  —  ALU operation decoder
// ============================================================
module alu_control(
    input  [1:0] alu_op,
    input  [2:0] funct3,
    input  [6:0] funct7,
    output reg [3:0] alu_ctrl
);

always @(*) begin
    alu_ctrl = 4'b0000; // default ADD
    case (alu_op)
        2'b00: alu_ctrl = 4'b0000; // LOAD/STORE → ADD
        2'b01: alu_ctrl = 4'b0001; // BRANCH  → SUB
        2'b10: begin               // R / I -type
            case (funct3)
                3'b000: alu_ctrl = (funct7 == 7'b0100000) ? 4'b0001 : 4'b0000; // SUB / ADD
                3'b111: alu_ctrl = 4'b0010; // AND
                3'b110: alu_ctrl = 4'b0011; // OR
                3'b100: alu_ctrl = 4'b0100; // XOR
                3'b001: alu_ctrl = 4'b0101; // SLL
                3'b101: alu_ctrl = (funct7[5]) ? 4'b0111 : 4'b0110; // SRA / SRL
                3'b010: alu_ctrl = 4'b1000; // SLT
                3'b011: alu_ctrl = 4'b1001; // SLTU
                default: alu_ctrl = 4'b0000;
            endcase
        end
        default: alu_ctrl = 4'b0000;
    endcase
end

endmodule

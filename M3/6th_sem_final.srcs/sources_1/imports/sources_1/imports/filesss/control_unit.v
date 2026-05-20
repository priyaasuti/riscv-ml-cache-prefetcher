// ============================================================
// control_unit.v  -  Main decoder (ID stage)
//
// FIXES vs original:
//   - Added lui, auipc output signals (FIX 3)
//   - LUI  : alu_op left as 2'b00 (ADD); alu_A will be forced to
//             0 in datapath so ALU computes 0+imm = imm  (FIX 3)
//   - AUIPC: same alu_op 2'b00; alu_A will be forced to PC       (FIX 3)
//   - JAL / JALR: alu_src=1 so ALU can compute rs1+imm for JALR  (FIX 2)
// ============================================================
module control_unit(
    input  [6:0] opcode,
    input  [2:0] funct3,

    output reg       reg_write,
    output reg       alu_src,
    output reg       mem_read,
    output reg       mem_write,
    output reg       mem_to_reg,
    output reg       branch,
    output reg       jal,
    output reg       jalr,
    output reg       lui,      // FIX 3
    output reg       auipc,    // FIX 3
    output reg       beq, bne, blt, bge, bltu, bgeu,
    output reg [1:0] alu_op
);

always @(*) begin
    // --- safe defaults ---
    reg_write  = 0; alu_src   = 0;
    mem_read   = 0; mem_write = 0; mem_to_reg = 0;
    branch     = 0; jal       = 0; jalr       = 0;
    lui        = 0; auipc     = 0;                // FIX 3
    beq  = 0; bne  = 0; blt  = 0;
    bge  = 0; bltu = 0; bgeu = 0;
    alu_op = 2'b00;

    case (opcode)
        7'b0110011: begin  // R-type
            reg_write = 1; alu_op = 2'b10;
        end
        7'b0010011: begin  // I-type ALU (ADDI, ANDI, ORI …)
            reg_write = 1; alu_src = 1; alu_op = 2'b10;
        end
        7'b0000011: begin  // LOAD (LW …)
            reg_write = 1; alu_src = 1;
            mem_read  = 1; mem_to_reg = 1; alu_op = 2'b00;
        end
        7'b0100011: begin  // STORE (SW …)
            alu_src = 1; mem_write = 1; alu_op = 2'b00;
        end
        7'b1100011: begin  // BRANCH (BEQ, BNE, BLT …)
            branch = 1; alu_op = 2'b01;
            case (funct3)
                3'b000: beq  = 1;
                3'b001: bne  = 1;
                3'b100: blt  = 1;
                3'b101: bge  = 1;
                3'b110: bltu = 1;
                3'b111: bgeu = 1;
            endcase
        end
        7'b1101111: begin  // JAL
            reg_write = 1; jal = 1;
            // alu_src=0, alu_op=2'b00  (ALU not used for JAL target)
        end
        7'b1100111: begin  // JALR
            reg_write = 1; alu_src = 1; jalr = 1;
            // alu_op=2'b00 → ADD → ALU computes rs1+imm = JALR target  (FIX 2)
        end
        7'b0110111: begin  // LUI
            reg_write = 1; alu_src = 1; lui = 1;  // FIX 3
            // alu_op=2'b00 → ADD; datapath forces alu_A=0 → result=imm
        end
        7'b0010111: begin  // AUIPC
            reg_write = 1; alu_src = 1; auipc = 1;  // FIX 3
            // alu_op=2'b00 → ADD; datapath forces alu_A=PC → result=PC+imm
        end
    endcase
end

endmodule

// ============================================================
// forwarding_unit.v  —  Data Forwarding (bypass) Unit
//
// PURPOSE: Eliminates RAW (Read-After-Write) data hazards
// by forwarding computed results from later pipeline stages
// back to the ALU inputs of the EX stage, without stalling.
//
// It checks:
//   1. EX/MEM → EX forward  (result of 1-cycle-old instruction)
//   2. MEM/WB → EX forward  (result of 2-cycle-old instruction)
//
// forwardA / forwardB encoding:
//   2'b00 — no forward: use register-file value from ID/EX
//   2'b10 — forward from EX/MEM alu_result  (higher priority)
//   2'b01 — forward from MEM/WB write_data
// ============================================================
module forwarding_unit(
    // Source registers of the instruction currently in EX stage
    input [4:0] ID_EX_rs1,
    input [4:0] ID_EX_rs2,

    // Destination + write-enable of instruction in EX/MEM stage
    input [4:0] EX_MEM_rd,
    input       EX_MEM_reg_write,

    // Destination + write-enable of instruction in MEM/WB stage
    input [4:0] MEM_WB_rd,
    input       MEM_WB_reg_write,

    output reg [1:0] forwardA,  // mux select for ALU input A
    output reg [1:0] forwardB   // mux select for ALU input B
);

always @(*) begin
    // ---------- Forward A ----------
    // EX/MEM has higher priority (more recent value)
    if (EX_MEM_reg_write && (EX_MEM_rd != 5'd0) &&
        (EX_MEM_rd == ID_EX_rs1))
        forwardA = 2'b10;

    else if (MEM_WB_reg_write && (MEM_WB_rd != 5'd0) &&
             (MEM_WB_rd == ID_EX_rs1))
        forwardA = 2'b01;

    else
        forwardA = 2'b00;

    // ---------- Forward B ----------
    if (EX_MEM_reg_write && (EX_MEM_rd != 5'd0) &&
        (EX_MEM_rd == ID_EX_rs2))
        forwardB = 2'b10;

    else if (MEM_WB_reg_write && (MEM_WB_rd != 5'd0) &&
             (MEM_WB_rd == ID_EX_rs2))
        forwardB = 2'b01;

    else
        forwardB = 2'b00;
end

endmodule

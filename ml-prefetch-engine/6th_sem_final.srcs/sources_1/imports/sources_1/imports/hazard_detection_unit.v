// ============================================================
// hazard_detection_unit.v  â€”  Hazard Detection Unit
//
// PURPOSE: Detects the ONE case that forwarding cannot solve:
//   LOAD-USE HAZARD â€” a LW instruction followed immediately by
//   an instruction that needs the loaded value.
//
//   Example:
//       lw  x1, 0(x2)     â†? memory read finishes at end of MEM
//       add x3, x1, x4    â†? needs x1 at start of EX (too early)
//
//   Forwarding cannot help here because the data does not exist
//   yet when the second instruction enters EX. The fix is to:
//     1. Stall the PC      (pc_write = 0)
//     2. Stall IF/ID reg   (IF_ID_write = 0)
//     3. Flush ID/EX reg   (insert one bubble / NOP)
//
// This inserts exactly ONE stall cycle, after which the normal
// MEM/WB â†’ EX forwarding path delivers the correct value.
// ============================================================
module hazard_detection_unit1(
    // Instruction currently in ID stage (just decoded)
    input [4:0] IF_ID_rs1,
    input [4:0] IF_ID_rs2,

    // Instruction currently in EX stage
    input [4:0] ID_EX_rd,
    input       ID_EX_mem_read,  // high only for LOAD instructions

    // Control outputs
    output reg pc_write,       // 0 = stall PC
    output reg IF_ID_write,    // 0 = freeze IF/ID register
    output reg ID_EX_flush     // 1 = flush ID/EX (bubble)
);

always @(*) begin
    // Default: no stall
    pc_write    = 1'b1;
    IF_ID_write = 1'b1;
    ID_EX_flush = 1'b0;

    // Load-use hazard detection
    if (ID_EX_mem_read &&
        (ID_EX_rd != 5'd0) &&
        ((ID_EX_rd == IF_ID_rs1) || (ID_EX_rd == IF_ID_rs2)))
    begin
        pc_write    = 1'b0; // freeze PC
        IF_ID_write = 1'b0; // freeze IF/ID
        ID_EX_flush = 1'b1; // inject bubble into EX
    end
end

endmodule

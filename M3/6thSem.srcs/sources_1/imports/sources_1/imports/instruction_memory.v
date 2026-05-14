// ============================================================
// instruction_memory.v  -  Read-only instruction memory
//
// Test sequence (PC = word_index * 4):
//
//  [0]  PC=  0  addi x1, x0, 5       x1 = 5
//  [1]  PC=  4  addi x2, x0, 3       x2 = 3
//  [2]  PC=  8  add  x3, x1, x2      x3 = 8   (forwarding test)
//  [3]  PC= 12  sub  x4, x1, x2      x4 = 2
//  [4]  PC= 16  add  x6, x1, x2      x6 = 8   (scratch for SW)
//  [5]  PC= 20  sw   x6, 0(x0)       mem[0] = 8
//  [6]  PC= 24  lw   x5, 0(x0)       x5 = 8   (load-use stall)
//  [7]  PC= 28  nop
//  [8]  PC= 32  beq  x1, x2, +8      NOT taken (5 != 3) -> PC=36
//  [9]  PC= 36  addi x6, x0, 1       x6 = 1   (executed, not skipped)
//  [10] PC= 40  nop
//  [11] PC= 44  nop
//  [12] PC= 48  beq  x1, x1, +8      TAKEN (5 == 5) -> PC=56
//  [13] PC= 52  addi x6, x0, 99      SKIPPED
//  [14] PC= 56  addi x6, x0, 2       x6 = 2   <- beq target
//  [15] PC= 60  nop
//  [16] PC= 64  bne  x1, x2, +8      TAKEN (5 != 3) -> PC=72
//  [17] PC= 68  addi x7, x0, 99      SKIPPED
//  [18] PC= 72  addi x7, x0, 3       x7 = 3   <- bne target
//  [19] PC= 76  nop
//  [20] PC= 80  jal  x9, +16         TAKEN -> PC=96, x9=84 (return addr)
//  [21] PC= 84  addi x8, x0, 99      SKIPPED (jal skips 3 instrs)
//  [22] PC= 88  addi x8, x0, 99      SKIPPED
//  [23] PC= 92  addi x8, x0, 99      SKIPPED
//  [24] PC= 96  addi x8, x0, 4       x8 = 4   <- jal target
//  [25] PC=100  addi x9, x9, 24      x9 = 84+24 = 108
//  [26] PC=104  jalr x10, x9, 0      TAKEN -> PC=108, x10=108 (return addr)
//  [27] PC=108  nop                  <- jalr target (no loop)
//  [28..31]     nop
//
// Expected register file after all WBs drain (need ~60+ cycles):
//   x1=5  x2=3  x3=8  x4=2  x5=8  x6=2  x7=3
//   x8=4  x9=108  x10=108
// ============================================================
module instruction_memory(
    input  [31:0] addr,
    output [31:0] instruction
);

reg [31:0] memory [0:63];

integer i;
initial begin
//    for (i = 0; i < 64; i = i + 1)
//        memory[i] = 32'h00000013; // default NOP

//    //  [0]  addi x1, x0, 5
//    memory[0]  = 32'h00500093;
//    //  [1]  addi x2, x0, 3
//    memory[1]  = 32'h00300113;
//    //  [2]  add  x3, x1, x2  -> x3=8
//    memory[2]  = 32'h002081b3;
//    //  [3]  sub  x4, x1, x2  -> x4=2
//    memory[3]  = 32'h40208233;
//    //  [4]  add  x6, x1, x2  -> x6=8  (scratch value for SW)
//    memory[4]  = 32'h00208333;
//    //  [5]  sw   x6, 0(x0)   -> mem[0]=8
//    memory[5]  = 32'h00602023;
//    //  [6]  lw   x5, 0(x0)   -> x5=8  (load-use stall triggered here)
//    memory[6]  = 32'h00002283;
//    //  [7]  nop
//// // Existing
//memory[5]  = 32'h00602023; // sw x6, 0(x0)
//memory[6]  = 32'h00002283; // lw x5, 0(x0)

//// 🔽 ADD THESE 🔽

//// Store to different addresses
//memory[7]  = 32'h00602223; // sw x6, 4(x0)
//memory[8]  = 32'h00402303; // lw x6, 4(x0)

//memory[9]  = 32'h00602423; // sw x6, 8(x0)
//memory[10] = 32'h00802483; // lw x9, 8(x0)

//// Repeated loads (to test hits)
//memory[11] = 32'h01002183; // lw x3, 16(x0)
//memory[12] = 32'h00002283; // lw x5, 0(x0)
//    //  [12] beq x1,x1,+8 - TAKEN (x1==x1); target = PC+8 = 48+8 = 56 = mem[14]
//    //       Encoding: B-type, rs1=x1, rs2=x1, imm=+8, funct3=000
//   // memory[12] = 32'h00108463;
//    //  [13] addi x6, x0, 99  -> SKIPPED (in shadow of taken branch)
//    memory[13] = 32'h06300313;
//    //  [14] addi x6, x0, 2  -> x6=2   (beq target; overwrites x6=1)
//    memory[14] = 32'h00200313;
//    //  [15] nop
//    memory[15] = 32'h00000013;

//    //  [16] bne x1,x2,+8 - TAKEN (x1=5, x2=3, 5?3); target = PC+8 = 64+8 = 72 = mem[18]
//    //       Encoding: B-type, rs1=x1, rs2=x2, imm=+8, funct3=001
//    memory[16] = 32'h00209463;
//    //  [17] addi x7, x0, 99  -> SKIPPED
//    memory[17] = 32'h06300393;
//    //  [18] addi x7, x0, 3  -> x7=3   (bne target)
//    memory[18] = 32'h00300393;
//    //  [19] nop
//    memory[19] = 32'h00000013;

//    //  [20] jal x9, +16 - TAKEN; target = PC+16 = 80+16 = 96 = mem[24]
//    //       x9 = 80+4 = 84 (return address)
//    //       J-type encoding: rd=x9(9), imm=+16
//    memory[20] = 32'h010004ef;
//    //  [21] addi x8, x0, 99  -> SKIPPED (jal shadow)
//    memory[21] = 32'h06300413;
//    //  [22] addi x8, x0, 99  -> SKIPPED
//    memory[22] = 32'h06300413;
//    //  [23] addi x8, x0, 99  -> SKIPPED
//    memory[23] = 32'h06300413;

//    //  [24] addi x8, x0, 4  -> x8=4  (jal target at PC=96)
//    memory[24] = 32'h00400413;
//    //  [25] addi x9, x9, 24 -> x9 = 84+24 = 108
//    //       I-type: rd=x9(9), rs1=x9(9), imm=24
//    memory[25] = 32'h01848493;
//    //  [26] jalr x10, x9, 0 - TAKEN; target = x9 = 108 = mem[27]
//    //       x10 = 104+4 = 108 (return address)
//    //       I-type: rd=x10(10), rs1=x9(9), imm=0, funct3=000
//    memory[26] = 32'h00048567;
//    //  [27] nop  <- jalr target (PC=108); no loop
//    memory[27] = 32'h00000013;
//    //  [28..31] nop  (pipeline drain)
//    memory[28] = 32'h00000013;
//    memory[29] = 32'h00000013;
//    memory[30] = 32'h00000013;
//    memory[31] = 32'h00000013;
// Initialize a register with a value
memory[0] = 32'h00500093; // addi x1, x0, 5

// Store value to different addresses
memory[1] = 32'h00102023; // sw x1, 0(x0)
memory[2] = 32'h00102223; // sw x1, 4(x0)
memory[3] = 32'h00102423; // sw x1, 8(x0)
memory[4] = 32'h00102623; // sw x1, 12(x0)
memory[5] = 32'h00102823; // sw x1, 16(x0)

// Load from different addresses (first time → MISS)
memory[6] = 32'h00002103; // lw x2, 0(x0)
memory[7] = 32'h00402183; // lw x3, 4(x0)
memory[8] = 32'h00802203; // lw x4, 8(x0)
memory[9] = 32'h00c02283; // lw x5, 12(x0)
memory[10]= 32'h01002303; // lw x6, 16(x0)

// Repeat loads (should be HITS)
memory[11]= 32'h00002103; // lw x2, 0(x0)
memory[12]= 32'h00402183; // lw x3, 4(x0)
memory[13]= 32'h00802203; // lw x4, 8(x0)
memory[14]= 32'h00c02283; // lw x5, 12(x0)
memory[15]= 32'h01002303; // lw x6, 16(x0)

// NOPs to drain pipeline
memory[16]= 32'h00000013;
memory[17]= 32'h00000013;
memory[18]= 32'h00000013;
memory[19]= 32'h00000013;

// ==========================================
// LOOP-HEAVY MEMORY ACCESS PROGRAM
// ==========================================

//// x1 = base address = 0
//memory[0] = 32'h00000093; // addi x1, x0, 0

//// x2 = loop counter = 16 (number of accesses)
//memory[1] = 32'h01000113; // addi x2, x0, 16

//// x3 = stride offset = 0
//memory[2] = 32'h00000193; // addi x3, x0, 0

//// x4 = data to store
//memory[3] = 32'h00100213; // addi x4, x0, 1

//// ---------- LOOP START (PC = 16) ----------
//memory[4] = 32'h0041a023; // sw x4, 0(x3 + x1)  → store at addr

//memory[5] = 32'h0001a283; // lw x5, 0(x3 + x1)  → load same addr

//memory[6] = 32'h00418193; // addi x3, x3, 4     → next address (+4)

//memory[7] = 32'hfff10113; // addi x2, x2, -1    → decrement counter

//// branch if not zero → go back to loop start
//memory[8] = 32'hfe011ae3; // bne x2, x0, -16 (to PC=16)

//// ---------- END ----------
//memory[9]  = 32'h00000013; // nop
//memory[10] = 32'h00000013;
//memory[11] = 32'h00000013;
//// After first loop

//memory[12] = 32'h00000193; // reset x3 = 0
//memory[13] = 32'h01000113; // reset counter

//// LOOP 2 (stride = 8)
//memory[14] = 32'h0041a023; // sw
//memory[15] = 32'h0001a283; // lw
//memory[16] = 32'h00818193; // addi x3, x3, 8  ← stride 8
//memory[17] = 32'hfff10113;
//memory[18] = 32'hfe011ae3;
//for (i = 20; i < 64; i = i + 1)
//    memory[i] = 32'h00000013; // NOP
end

assign instruction = memory[addr[9:2]];

endmodule
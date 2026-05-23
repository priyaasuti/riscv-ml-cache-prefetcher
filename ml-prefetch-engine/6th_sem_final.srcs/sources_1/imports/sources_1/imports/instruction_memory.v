`timescale 1ns/1ps
module instruction_memory(
    input  [31:0] addr,
    output [31:0] instruction
);

reg [31:0] memory [0:63];
integer i;

initial begin
    for (i = 0; i < 64; i = i + 1)
        memory[i] = 32'h00000013;

    // Pattern A: pure stride loads
    memory[0]  = 32'h00000093; // addi x1, x0, 0
    memory[1]  = 32'h00800113; // addi x2, x0, 8
    memory[2]  = 32'h0000a283; // lw   x5, 0(x1)
    memory[3]  = 32'h00408093; // addi x1, x1, 4
    memory[4]  = 32'hfff10113; // addi x2, x2, -1
    memory[5]  = 32'hfe011ae3; // bne  x2, x0, -12

    // Pattern B: hit-hit-miss repeat
    memory[6]  = 32'h00000093; // addi x1, x0, 0
    memory[7]  = 32'h00400113; // addi x2, x0, 4
    memory[8]  = 32'h0000a283; // lw   x5, 0(x1)
    memory[9]  = 32'h00408093; // addi x1, x1, 4
    memory[10] = 32'h0000a283; // lw   x5, 0(x1)
    memory[11] = 32'h00408093; // addi x1, x1, 4
    memory[12] = 32'h0000a283; // lw   x5, 0(x1)
    memory[13] = 32'h00000093; // addi x1, x0, 0
    memory[14] = 32'hfff10113; // addi x2, x2, -1
    memory[15] = 32'hfe0112e3; // bne  x2, x0, -28

    // Pattern C: random-window reread
    memory[16] = 32'h00000093; // addi x1, x0, 0
    memory[17] = 32'h00400113; // addi x2, x0, 4
    memory[18] = 32'h0000a283; // lw   x5, 0(x1)
    memory[19] = 32'h01008093; // addi x1, x1, 16
    memory[20] = 32'h0000a283; // lw   x5, 0(x1)
    memory[21] = 32'hff408093; // addi x1, x1, -12
    memory[22] = 32'h0000a283; // lw   x5, 0(x1)
    memory[23] = 32'hffc08093; // addi x1, x1, -4
    memory[24] = 32'h0000a283; // lw   x5, 0(x1)
    memory[25] = 32'hfff10113; // addi x2, x2, -1
    memory[26] = 32'hfe0110e3; // bne  x2, x0, -32

    // Pattern D: function-call jump
    memory[27] = 32'h00000093; // addi x1, x0, 0
    memory[28] = 32'h02000113; // addi x2, x0, 32
    memory[29] = 32'h00300193; // addi x3, x0, 3
    memory[30] = 32'h0000a283; // lw   x5, 0(x1)
    memory[31] = 32'h01c0036f; // jal  x6, 28
    memory[32] = 32'h00408093; // addi x1, x1, 4
    memory[33] = 32'hfff18193; // addi x3, x3, -1
    memory[34] = 32'hfe0198e3; // bne  x3, x0, -16
    memory[35] = 32'h00000013; // nop
    memory[36] = 32'h00000013; // nop
    memory[37] = 32'h00000013; // nop
    memory[38] = 32'h00012283; // lw   x5, 0(x2)
    memory[39] = 32'h00410113; // addi x2, x2, 4
    memory[40] = 32'h00012283; // lw   x5, 0(x2)
    memory[41] = 32'h00030067; // jalr x0, x6, 0
end

assign instruction = memory[addr[9:2]];
endmodule
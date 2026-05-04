// ============================================================
// tb_riscv_pipeline.v  -  Testbench: JAL / JALR / Branch / ALU / MEM
//
// Strategy: Run 80 cycles (enough for all instructions to drain
// through all 5 stages with stalls/flushes), then snapshot and
// check every expected register value in one place.
//
// Expected final register values (see instruction_memory.v):
//   x1  =   5   addi x1,x0,5
//   x2  =   3   addi x2,x0,3
//   x3  =   8   add x3,x1,x2
//   x4  =   2   sub x4,x1,x2
//   x5  =   8   lw x5,0(x0)  (mem[0]=8 from SW)
//   x6  =   2   beq-taken skips 99, lands on addi x6,0,2
//   x7  =   3   bne-taken skips 99, lands on addi x7,0,3
//   x8  =   4   jal skips 99x3, lands on addi x8,0,4
//   x9  = 108   x9=84 (jal retaddr) + 24 = 108
//   x10 = 108   jalr retaddr = PC_jalr+4 = 104+4 = 108
//
// Hazards exercised:
//   - EX/MEM?EX forwarding   (add x3 uses x1,x2 from just-before)
//   - Load-use stall          (lw x5 followed immediately by nop gives stall)
//   - BEQ not-taken           (no flush; instruction after BEQ executes)
//   - BEQ taken               (2-cycle flush of IF+ID shadow)
//   - BNE taken               (2-cycle flush)
//   - JAL                     (2-cycle flush; rd gets PC+4)
//   - JALR                    (2-cycle flush; rd gets PC+4; target=rs1+imm&~1)
// ============================================================
`timescale 1ns/1ps
module tb_riscv_pipeline;

// ?? Clock & reset ????????????????????????????????????????????
reg clk, rst;
initial clk = 0;
always #5 clk = ~clk;   // 10 ns period

// ?? DUT ??????????????????????????????????????????????????????
datapath dut(.clk(clk), .rst(rst));

// ?? Cycle counter + per-cycle trace ??????????????????????????
integer cycle;
initial cycle = 0;
always @(posedge clk) begin
    cycle = cycle + 1;
    if (!rst)
        $display("CYC %3d | PC=%3d | IF_ID=%08h | ID_EX_rd=x%0d | EX_MEM_rd=x%0d | MEM_WB_rd=x%0d | fwdA=%b fwdB=%b | stall=%b | bt=%b",
            cycle,
            dut.pc,
            dut.IF_ID_instr,
            dut.ID_EX_rd,
            dut.EX_MEM_rd,
            dut.MEM_WB_rd,
            dut.forwardA, dut.forwardB,
            ~dut.pc_write,
            dut.branch_taken);
end

// ?? Checker task ?????????????????????????????????????????????
integer pass_cnt, fail_cnt;

task check;
    input [255:0] name;       // register name string
    input [31:0]  got;
    input [31:0]  expected;
    input [255:0] desc;
    begin
        if (got === expected) begin
            $display("  PASS  %-8s = %3d  (%0s)", name, got, desc);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  %-8s = %3d  expected %3d  (%0s)", name, got, expected, desc);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// ?? Main stimulus ?????????????????????????????????????????????
initial begin
    $dumpfile("pipeline_jal_test.vcd");
    $dumpvars(0, tb_riscv_pipeline);

    pass_cnt = 0;
    fail_cnt = 0;

    // Hold reset for 3 cycles
    rst = 1;
    repeat(3) @(posedge clk);
    rst = 0;

    // Run 80 cycles - covers 32 instructions + pipeline flush latency
    repeat(80) @(posedge clk);
    @(negedge clk);   // sample after last posedge WB

    $display("\n============================================================");
    $display("  REGISTER FILE SNAPSHOT  (after 80 cycles)");
    $display("============================================================");

    // ?? Arithmetic & forwarding ???????????????????????????????
    $display("\n--- ALU & Forwarding ---");
    check("x1",  dut.rf.regs[1],   5,  "addi x1,x0,5");
    check("x2",  dut.rf.regs[2],   3,  "addi x2,x0,3");
    check("x3",  dut.rf.regs[3],   8,  "add  x3,x1,x2  (EX/MEM?EX fwd)");
    check("x4",  dut.rf.regs[4],   2,  "sub  x4,x1,x2");

    // ?? Load / Store ??????????????????????????????????????????
    $display("\n--- Load / Store ---");
    check("x5",  dut.rf.regs[5],   8,  "lw x5,0(x0)  (load-use stall)");
    $display("  INFO  dmem[0] = %0d  (expect 8 from SW)", dut.dmem.memory[0]);

    // ?? Branch: BEQ not taken ?????????????????????????????????
    $display("\n--- BEQ not taken (x1=5 != x2=3) ---");
    // x6 goes: 8(scratch) -> 1(addi after BEQ-not-taken) -> 2(BEQ-taken target)
    // Final x6 must be 2
    check("x6",  dut.rf.regs[6],   2,  "x6=1 after BEQ-NT then x6=2 after BEQ-T");

    // ?? Branch: BEQ taken ?????????????????????????????????????
    $display("\n--- BEQ taken (x1==x1) -> skip addi 99, land on addi x6,2 ---");
    // Already checked above; add a memory-content sanity display
    $display("  INFO  x6 final = %0d (1 from BEQ-NT path then 2 from BEQ-T path)", dut.rf.regs[6]);

    // ?? Branch: BNE taken ?????????????????????????????????????
    $display("\n--- BNE taken (x1=5 != x2=3) -> skip addi 99, land on addi x7,3 ---");
    check("x7",  dut.rf.regs[7],   3,  "addi x7,x0,3  (bne target)");

    // ?? JAL ???????????????????????????????????????????????????
    $display("\n--- JAL x9,+16 at PC=80 -> target=96, retaddr=84 ---");
    check("x8",  dut.rf.regs[8],   4,   "addi x8,x0,4 at jal target PC=96");
    check("x9",  dut.rf.regs[9],   108, "x9=84(retaddr)+24=108");

    // ?? JALR ??????????????????????????????????????????????????
    $display("\n--- JALR x10,x9,0 at PC=104 -> target=108, retaddr=108 ---");
    check("x10", dut.rf.regs[10],  108, "jalr retaddr = 104+4 = 108");

    // ?? Summary ???????????????????????????????????????????????
    $display("\n============================================================");
    $display("  TOTAL=%0d  PASS=%0d  FAIL=%0d",
             pass_cnt+fail_cnt, pass_cnt, fail_cnt);
    $display("============================================================\n");

    $finish;
end

endmodule
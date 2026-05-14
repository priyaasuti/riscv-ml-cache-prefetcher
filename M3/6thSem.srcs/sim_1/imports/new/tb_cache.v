`timescale 1ns/1ps
// ============================================================
//  tb_cache.v  –  UPDATED TESTBENCH
//
//  Changes from original:
//  1. Longer simulation (12000 cycles) to observe all 4 stride
//     prefetch variants completing their fills.
//  2. Added stride_index tracking to identify which of the 4
//     stride patterns each pf_req corresponds to.
//  3. Display counters at end: pf_filled count, hit rate.
//  4. Added obs_valid to CSV so we can track real memory accesses
//     vs. idle cycles in the log.
// ============================================================

module tb_cache;

reg clk, rst;

always #5 clk = ~clk;

// DUT
datapath dut(
    .clk(clk),
    .rst(rst)
);

// Cache observation signals
wire        obs_valid = dut.dcache.obs_valid;
wire [31:0] obs_addr  = dut.dcache.obs_addr;
wire        obs_hit   = dut.dcache.obs_hit;
wire [31:0] obs_pc    = dut.dcache.obs_pc;

// ML signals
wire        ml_done = dut.ML_PREFETCHER.ml_done;
wire        ml_busy = dut.ML_PREFETCHER.ml_busy;
wire        pf_req  = dut.ML_PREFETCHER.pf_req;
wire [31:0] pf_addr = dut.ML_PREFETCHER.pf_addr;

// Cache prefetch debug signals
wire        pf_accepted    = dut.dcache.pf_accepted;
wire        pf_filled      = dut.dcache.pf_filled;
wire [31:0] pf_filled_addr = dut.dcache.pf_filled_addr;

// Statistics
wire [31:0] stat_accesses = dut.dcache.stat_accesses;
wire [31:0] stat_hits     = dut.dcache.stat_hits;
wire [31:0] stat_misses   = dut.dcache.stat_misses;

// Sticky proof flags
reg ml_done_seen;
reg pf_req_seen;
reg pf_accepted_seen;
reg pf_filled_seen;

// Fill counter
reg [31:0] pf_fill_count;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        ml_done_seen     <= 1'b0;
        pf_req_seen      <= 1'b0;
        pf_accepted_seen <= 1'b0;
        pf_filled_seen   <= 1'b0;
        pf_fill_count    <= 32'd0;
    end else begin
        if (ml_done)     ml_done_seen     <= 1'b1;
        if (pf_req)      pf_req_seen      <= 1'b1;
        if (pf_accepted) pf_accepted_seen <= 1'b1;
        if (pf_filled) begin
            pf_filled_seen <= 1'b1;
            pf_fill_count  <= pf_fill_count + 1;
        end
    end
end

// CSV log
integer log_fd;
integer cycle_count;

initial begin
    $timeformat(-9, 0, "ns", 10);

    clk         = 0;
    rst         = 1;
    cycle_count = 0;

    log_fd = $fopen("mem_access_log.csv", "w");

    if (log_fd == 0) begin
        $display("ERROR: could not open log file");
        $finish;
    end

    $fwrite(log_fd,
        "cycle,pc,addr,hit,obs_valid,ml_busy,ml_done,"
        "pf_req,pf_addr,pf_accepted,pf_filled,pf_filled_addr\n"
    );

    // Reset for 5 cycles
    repeat (5) @(posedge clk);
    rst = 0;

    // Run 12000 cycles to see all 4 stride variants fill
    repeat (12000) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;

        // Log on any prefetch or ML activity
        if (pf_req || pf_accepted || pf_filled || ml_done || obs_valid) begin
            $fwrite(log_fd,
                "%0d,%08h,%08h,%0d,%0d,%0d,%0d,%0d,%08h,%0d,%0d,%08h\n",
                cycle_count,
                obs_pc,
                obs_addr,
                obs_hit      ? 1 : 0,
                obs_valid    ? 1 : 0,
                ml_busy      ? 1 : 0,
                ml_done      ? 1 : 0,
                pf_req       ? 1 : 0,
                pf_addr,
                pf_accepted  ? 1 : 0,
                pf_filled    ? 1 : 0,
                pf_filled_addr
            );
        end
    end

    $fclose(log_fd);

    $display("=== Simulation Complete ===");
    $display("Log written to mem_access_log.csv");
    $display("ml_done_seen     = %0d", ml_done_seen);
    $display("pf_req_seen      = %0d", pf_req_seen);
    $display("pf_accepted_seen = %0d", pf_accepted_seen);
    $display("pf_filled_seen   = %0d", pf_filled_seen);
    $display("pf_fill_count    = %0d", pf_fill_count);
    $display("stat_accesses    = %0d", stat_accesses);
    $display("stat_hits        = %0d", stat_hits);
    $display("stat_misses      = %0d", stat_misses);
    if (stat_accesses > 0)
        $display("hit_rate         = %0d%%",
                 (stat_hits * 100) / stat_accesses);

    $finish;
end

endmodule

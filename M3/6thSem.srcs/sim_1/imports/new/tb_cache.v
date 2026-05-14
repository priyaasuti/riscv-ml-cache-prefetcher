`timescale 1ns/1ps

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
wire        pf_accepted     = dut.dcache.pf_accepted;
wire        pf_filled       = dut.dcache.pf_filled;
wire [31:0] pf_filled_addr  = dut.dcache.pf_filled_addr;

// Sticky proof flags
reg ml_done_seen;
reg pf_req_seen;
reg pf_accepted_seen;
reg pf_filled_seen;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        ml_done_seen     <= 1'b0;
        pf_req_seen      <= 1'b0;
        pf_accepted_seen <= 1'b0;
        pf_filled_seen   <= 1'b0;
    end else begin
        if (ml_done)
            ml_done_seen <= 1'b1;

        if (pf_req)
            pf_req_seen <= 1'b1;

        if (pf_accepted)
            pf_accepted_seen <= 1'b1;

        if (pf_filled)
            pf_filled_seen <= 1'b1;
    end
end

// CSV
integer log_fd;
integer cycle_count;

initial begin
    $timeformat(-9, 0, "ns", 10);

    clk = 0;
    rst = 1;
    cycle_count = 0;

    log_fd = $fopen("mem_access_log.csv", "w");

    if (log_fd == 0) begin
        $display("ERROR: could not open log file");
        $finish;
    end

    $fwrite(log_fd,
        "cycle,pc,addr,hit,ml_busy,ml_done,pf_req,pf_addr,pf_accepted,pf_filled,pf_filled_addr\n"
    );

    // Reset
    repeat (5) @(posedge clk);
    rst = 0;

    // Enough for M4 sequential engine, but not too slow
    repeat (8000) begin
        @(posedge clk);

        cycle_count = cycle_count + 1;

        // Log only useful prefetch activity
        if (pf_req || pf_accepted || pf_filled || ml_done) begin
            $fwrite(log_fd,
                "%0d,%08h,%08h,%0d,%0d,%0d,%0d,%08h,%0d,%0d,%08h\n",
                cycle_count,
                obs_pc,
                obs_addr,
                obs_hit ? 1 : 0,
                ml_busy ? 1 : 0,
                ml_done ? 1 : 0,
                pf_req ? 1 : 0,
                pf_addr,
                pf_accepted ? 1 : 0,
                pf_filled ? 1 : 0,
                pf_filled_addr
            );
        end
    end

    $fclose(log_fd);

    $display("Log written to mem_access_log.csv");
    $display("ml_done_seen     = %0d", ml_done_seen);
    $display("pf_req_seen      = %0d", pf_req_seen);
    $display("pf_accepted_seen = %0d", pf_accepted_seen);
    $display("pf_filled_seen   = %0d", pf_filled_seen);

    $finish;
end

endmodule
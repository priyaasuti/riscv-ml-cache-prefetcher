`timescale 1ns/1ps
module tb_cache;

reg clk, rst;
always #5 clk = ~clk;

datapath dut(.clk(clk), .rst(rst));

wire        obs_valid      = dut.dcache.obs_valid;
wire [31:0] obs_addr       = dut.dcache.obs_addr;
wire        obs_hit        = dut.dcache.obs_hit;
wire [31:0] obs_pc         = dut.dcache.obs_pc;

wire               ml_done   = dut.ML_PREFETCHER.ml_done;
wire               ml_busy   = dut.ML_PREFETCHER.ml_busy;
wire               pf_req    = dut.ML_PREFETCHER.pf_req;
wire [31:0]        pf_addr   = dut.ML_PREFETCHER.pf_addr;
wire signed [7:0]  ml_delta  = dut.ML_PREFETCHER.engine_out;
wire [31:0]        last_addr = dut.ML_PREFETCHER.last_addr_for_prediction;

wire        pf_accepted    = dut.dcache.pf_accepted;
wire        pf_filled      = dut.dcache.pf_filled;
wire [31:0] pf_filled_addr = dut.dcache.pf_filled_addr;
wire [31:0] if_pc        = dut.pc;
wire        cache_stall  = dut.cache_stall;
wire        cache_pf_req = dut.PREF_CTRL.cache_pf_req;
wire [31:0] cache_pf_addr = dut.PREF_CTRL.cache_pf_addr;
wire [1:0]  pattern_id   = (if_pc < 32'd24)  ? 2'd1 :
                            (if_pc < 32'd64)  ? 2'd2 :
                            (if_pc < 32'd108) ? 2'd3 :
                                                 2'd4;

reg ml_done_seen, pf_req_seen, pf_accepted_seen, pf_filled_seen;
reg [31:0] ml_done_cnt_1, ml_done_cnt_2, ml_done_cnt_3, ml_done_cnt_4;
reg [31:0] pf_req_cnt_1, pf_req_cnt_2, pf_req_cnt_3, pf_req_cnt_4;
reg [31:0] pf_accepted_cnt_1, pf_accepted_cnt_2, pf_accepted_cnt_3, pf_accepted_cnt_4;
reg [31:0] pf_filled_cnt_1, pf_filled_cnt_2, pf_filled_cnt_3, pf_filled_cnt_4;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        ml_done_seen     <= 1'b0;
        pf_req_seen      <= 1'b0;
        pf_accepted_seen <= 1'b0;
        pf_filled_seen   <= 1'b0;

        ml_done_cnt_1      <= 32'd0;
        ml_done_cnt_2      <= 32'd0;
        ml_done_cnt_3      <= 32'd0;
        ml_done_cnt_4      <= 32'd0;
        pf_req_cnt_1       <= 32'd0;
        pf_req_cnt_2       <= 32'd0;
        pf_req_cnt_3       <= 32'd0;
        pf_req_cnt_4       <= 32'd0;
        pf_accepted_cnt_1  <= 32'd0;
        pf_accepted_cnt_2  <= 32'd0;
        pf_accepted_cnt_3  <= 32'd0;
        pf_accepted_cnt_4  <= 32'd0;
        pf_filled_cnt_1    <= 32'd0;
        pf_filled_cnt_2    <= 32'd0;
        pf_filled_cnt_3    <= 32'd0;
        pf_filled_cnt_4    <= 32'd0;
    end else begin
        if (ml_done)     ml_done_seen     <= 1'b1;
        if (pf_req)      pf_req_seen      <= 1'b1;
        if (pf_accepted) pf_accepted_seen <= 1'b1;
        if (pf_filled)   pf_filled_seen   <= 1'b1;
    end
end

integer log_fd;
integer cycle_count;

initial begin
    $timeformat(-9, 0, "ns", 10);
    clk = 0; rst = 1; cycle_count = 0;

    $display("Writing simulation log to mem_access_log.csv");
    log_fd = $fopen("mem_access_log.csv", "w");
    if (log_fd == 0) begin
        $display("ERROR: could not open log file");
        $finish;
    end

    $fwrite(log_fd,
        "cycle,pc,if_pc,addr,hit,ml_busy,ml_done,pf_req,pf_addr,pf_accepted,pf_filled,pf_filled_addr,cache_stall,cache_pf_req,cache_pf_addr,pattern\n"
    );

    repeat (5) @(posedge clk);
    rst = 0;

    repeat (8000) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;

        if (ml_done) begin
            case (pattern_id)
                2'd1: ml_done_cnt_1 <= ml_done_cnt_1 + 1;
                2'd2: ml_done_cnt_2 <= ml_done_cnt_2 + 1;
                2'd3: ml_done_cnt_3 <= ml_done_cnt_3 + 1;
                2'd4: ml_done_cnt_4 <= ml_done_cnt_4 + 1;
            endcase
        end
        if (pf_req) begin
            case (pattern_id)
                2'd1: pf_req_cnt_1 <= pf_req_cnt_1 + 1;
                2'd2: pf_req_cnt_2 <= pf_req_cnt_2 + 1;
                2'd3: pf_req_cnt_3 <= pf_req_cnt_3 + 1;
                2'd4: pf_req_cnt_4 <= pf_req_cnt_4 + 1;
            endcase
        end
        if (pf_accepted) begin
            case (pattern_id)
                2'd1: pf_accepted_cnt_1 <= pf_accepted_cnt_1 + 1;
                2'd2: pf_accepted_cnt_2 <= pf_accepted_cnt_2 + 1;
                2'd3: pf_accepted_cnt_3 <= pf_accepted_cnt_3 + 1;
                2'd4: pf_accepted_cnt_4 <= pf_accepted_cnt_4 + 1;
            endcase
        end
        if (pf_filled) begin
            case (pattern_id)
                2'd1: pf_filled_cnt_1 <= pf_filled_cnt_1 + 1;
                2'd2: pf_filled_cnt_2 <= pf_filled_cnt_2 + 1;
                2'd3: pf_filled_cnt_3 <= pf_filled_cnt_3 + 1;
                2'd4: pf_filled_cnt_4 <= pf_filled_cnt_4 + 1;
            endcase
        end

        if (obs_valid || pf_req || pf_accepted || pf_filled || ml_done || cache_pf_req) begin
            $fwrite(log_fd,
                "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                cycle_count, obs_pc, if_pc, obs_addr,
                obs_hit      ? 1 : 0,
                ml_busy      ? 1 : 0,
                ml_done      ? 1 : 0,
                pf_req       ? 1 : 0,
                pf_addr,
                pf_accepted  ? 1 : 0,
                pf_filled    ? 1 : 0,
                pf_filled_addr,
                cache_stall  ? 1 : 0,
                cache_pf_req ? 1 : 0,
                cache_pf_addr,
                pattern_id
            );
        end
    end

    $fclose(log_fd);

    $display("================================================");
    $display("     ML PREFETCHER PREDICTION REPORT");
    $display("================================================");
    $display("last addr seen by ML = %0d", last_addr);
    $display("ML predicted delta   = %0d", ml_delta);
    $display("predicted bytes      = %0d", $signed(ml_delta) * 4);
    $display("pf_addr predicted    = %0d", pf_addr);
    $display("pf_filled_addr       = %0d", dut.pf_filled_addr_w);
    $display("expected next addr   = %0d", last_addr + ($signed(ml_delta) * 4));
    $display("================================================");
    $display("     CACHE STATS");
    $display("================================================");
    $display("accesses = %0d", dut.dcache.stat_accesses);
    $display("hits     = %0d", dut.dcache.stat_hits);
    $display("misses   = %0d", dut.dcache.stat_misses);
    $display("================================================");
    $display("     PREFETCH FLAGS");
    $display("================================================");
    $display("ml_done_seen     = %0d", ml_done_seen);
    $display("pf_req_seen      = %0d", pf_req_seen);
    $display("pf_accepted_seen = %0d", pf_accepted_seen);
    $display("pf_filled_seen   = %0d", pf_filled_seen);
    $display("================================================");
    $display("     PATTERN COUNTS");
    $display("================================================");
    $display("pattern 1 stride     ml_done=%0d pf_req=%0d pf_acc=%0d pf_filled=%0d",
             ml_done_cnt_1, pf_req_cnt_1, pf_accepted_cnt_1, pf_filled_cnt_1);
    $display("pattern 2 repeat     ml_done=%0d pf_req=%0d pf_acc=%0d pf_filled=%0d",
             ml_done_cnt_2, pf_req_cnt_2, pf_accepted_cnt_2, pf_filled_cnt_2);
    $display("pattern 3 random     ml_done=%0d pf_req=%0d pf_acc=%0d pf_filled=%0d",
             ml_done_cnt_3, pf_req_cnt_3, pf_accepted_cnt_3, pf_filled_cnt_3);
    $display("pattern 4 function   ml_done=%0d pf_req=%0d pf_acc=%0d pf_filled=%0d",
             ml_done_cnt_4, pf_req_cnt_4, pf_accepted_cnt_4, pf_filled_cnt_4);
    $display("================================================");

    $finish;
end

endmodule
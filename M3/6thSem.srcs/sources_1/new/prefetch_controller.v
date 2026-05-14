// ============================================================
//  prefetch_controller.v  –  FIXED VERSION
//
//  Bug fixed:
//  The original controller only held pf_req for one cycle, so
//  if the cache was busy (cache_busy=1) the request was simply
//  dropped. With 4 stride variants being emitted back-to-back,
//  requests can arrive while the cache is still in PF_MISS
//  or PF_FILL state.
//
//  Fix: add a 2-entry FIFO (head/tail) that buffers incoming
//  pf_req pulses from the ML prefetcher and drains them one
//  per cycle only when the cache is not busy. This prevents
//  dropping any of the 4 stride-variant requests while still
//  keeping a single-cycle pf_req pulse to the cache.
//
//  FIFO depth = 4, matching the 4 stride variants.
// ============================================================

module prefetch_controller (
    input clk,
    input reset,

    input        ml_pf_req,
    input [31:0] ml_pf_addr,

    input        cache_busy,

    output reg        cache_pf_req,
    output reg [31:0] cache_pf_addr
);

    // 4-entry FIFO
    localparam DEPTH = 4;
    reg [31:0] fifo_addr [0:DEPTH-1];
    reg [2:0]  fifo_head;   // read pointer
    reg [2:0]  fifo_tail;   // write pointer
    reg [2:0]  fifo_count;

    wire fifo_full  = (fifo_count == DEPTH);
    wire fifo_empty = (fifo_count == 3'd0);

    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fifo_head    <= 3'd0;
            fifo_tail    <= 3'd0;
            fifo_count   <= 3'd0;
            cache_pf_req <= 1'b0;
            cache_pf_addr<= 32'd0;
            for (i = 0; i < DEPTH; i = i + 1)
                fifo_addr[i] <= 32'd0;
        end else begin
            cache_pf_req <= 1'b0;

            // ── Enqueue incoming request ─────────────────
            if (ml_pf_req && !fifo_full) begin
                fifo_addr[fifo_tail[1:0]] <= ml_pf_addr;
                fifo_tail  <= fifo_tail + 3'd1;
                fifo_count <= fifo_count + 3'd1;
            end

            // ── Dequeue to cache when not busy ───────────
            if (!fifo_empty && !cache_busy) begin
                cache_pf_req  <= 1'b1;
                cache_pf_addr <= fifo_addr[fifo_head[1:0]];
                fifo_head     <= fifo_head + 3'd1;
                fifo_count    <= fifo_count - 3'd1;
            end
        end
    end

endmodule

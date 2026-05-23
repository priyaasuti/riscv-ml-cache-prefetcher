// ============================================================
//  prefetch_controller.v — FIXED v3
//
//  The FIFO approach was fundamentally broken because:
//  - pf_req arrives while CPU is doing demand misses
//  - cache_busy = cache_stall | pf_inflight was always 1
//  - FIFO never drained
//
//  With the new l1_cache (which latches pf_req internally
//  the moment it arrives), this controller's job is simplified:
//  just pass the filtered pf_req directly to the cache with
//  minimal delay.
//
//  cache_busy now only means "prefetch fill is in-flight"
//  (pf_inflight from l1_cache), NOT "CPU demand miss in progress".
//  The cache's internal pending register handles queueing.
//
//  This module is now a simple registered pass-through.
// ============================================================

module prefetch_controller (
    input clk,
    input reset,

    input        ml_pf_req,
    input [31:0] ml_pf_addr,

    // Only HIGH when a prefetch fill is actually in-flight in the cache
    // (pf_inflight_w from l1_cache — NOT cache_stall)
    input        cache_busy,

    output reg        cache_pf_req,
    output reg [31:0] cache_pf_addr
);

    // Simple 1-cycle registered pass-through.
    // The l1_cache now has an internal pending register that latches
    // pf_req immediately, so no deep FIFO is needed here.
    // cache_busy gating is kept to avoid sending a new request
    // while a previous prefetch fill is still completing.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cache_pf_req  <= 1'b0;
            cache_pf_addr <= 32'd0;
        end else begin
            cache_pf_req  <= 1'b0;
            cache_pf_addr <= 32'd0;
            if (ml_pf_req && !cache_busy) begin
                cache_pf_req  <= 1'b1;
                cache_pf_addr <= ml_pf_addr;
            end
        end
    end

endmodule

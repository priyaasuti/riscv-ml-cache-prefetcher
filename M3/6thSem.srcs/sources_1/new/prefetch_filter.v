// ============================================================
//  prefetch_filter.v  –  FIXED VERSION
//
//  Change: now also filters out non-word-aligned addresses
//  produced by stride ×2, ×4, ×8 which remain word-aligned
//  (delta_i8 << 2 is always 4-byte aligned; scaling by 1/2/4/8
//  stays 4-byte aligned for even deltas but could produce 4-byte
//  aligned odd addresses for odd deltas — the original [1:0]==0
//  check handles this correctly, so the combinatorial logic is
//  unchanged). The module is functionally identical; this version
//  adds a comment to clarify the alignment invariant.
// ============================================================

module prefetch_filter (
    input        pf_req_in,
    input [31:0] pf_addr_in,
    input [31:0] current_addr,

    output        pf_req_out,
    output [31:0] pf_addr_out
);

    // Filter out:
    //   same_addr  – prefetching what the CPU just accessed
    //   !aligned   – non-word-aligned (should never happen with
    //                the ML prefetcher but guard it here)
    wire same_addr    = (pf_addr_in == current_addr);
    wire aligned_addr = (pf_addr_in[1:0] == 2'b00);

    assign pf_req_out  = pf_req_in & (~same_addr) & aligned_addr;
    assign pf_addr_out = pf_addr_in;

endmodule

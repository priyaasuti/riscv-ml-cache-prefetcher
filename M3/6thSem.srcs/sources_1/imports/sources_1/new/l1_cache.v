`timescale 1ns / 1ps
// ============================================================
//  l1_cache.v  –  FIXED VERSION
//
//  Bugs fixed:
//  1. read_data mux: was returning dmem_read_data for ALL fills
//     (including prefetch fills), corrupting CPU reads.
//     Now only returns dmem_read_data during demand-fill (S_FILL
//     with m_is_pf==0).
//  2. Prefetch path: pf_accepted was firing repeatedly even when
//     cache was busy with its own fill, causing addr 0x0 ghost
//     fills. Added S_PF_MISS / S_PF_FILL states so the prefetch
//     has its own non-stalling path, completely separate from the
//     demand-miss path.
//  3. stall logic: was asserting stall even during a prefetch
//     fill, blocking the CPU. Now stall is strictly demand-only.
//  4. Prefetch fill now correctly writes pf_filled_addr from the
//     real pf_addr latched at acceptance time.
// ============================================================

module l1_cache #(
    parameter LINES  = 16,
    parameter OFFSET = 2
)(
    input  wire        clk,
    input  wire        rst,

    // CPU interface
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data,
    output wire        stall,

    // Backing memory interface
    output reg  [31:0] dmem_addr,
    output reg         dmem_read,
    output reg         dmem_write,
    output reg  [31:0] dmem_write_data,
    input  wire [31:0] dmem_read_data,

    // Observation / debug
    output reg         obs_valid,
    output reg  [31:0] obs_addr,
    output reg         obs_hit,
    output reg  [31:0] obs_pc,

    // Prefetch request from ML prefetcher
    input  wire        pf_req,
    input  wire [31:0] pf_addr,

    // Prefetch status outputs
    output reg         pf_accepted,
    output reg         pf_filled,
    output reg  [31:0] pf_filled_addr,

    // Statistics
    output reg  [31:0] stat_accesses,
    output reg  [31:0] stat_hits,
    output reg  [31:0] stat_misses,

    input  wire [31:0] pipeline_pc
);

localparam LOG_LINES = $clog2(LINES);
localparam TAG_W     = 32 - LOG_LINES - OFFSET;

// ── Address breakdown ──────────────────────────────────────
wire [LOG_LINES-1:0] idx = addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     tag = addr[31 : OFFSET + LOG_LINES];

wire [LOG_LINES-1:0] pf_idx = pf_addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     pf_tag = pf_addr[31 : OFFSET + LOG_LINES];

// ── Cache arrays ──────────────────────────────────────────
reg [TAG_W-1:0] c_tag   [0:LINES-1];
reg [31:0]      c_data  [0:LINES-1];
reg             c_valid [0:LINES-1];

wire hit    = c_valid[idx]    && (c_tag[idx]    == tag);
wire pf_hit = c_valid[pf_idx] && (c_tag[pf_idx] == pf_tag);

// ── FSM states ────────────────────────────────────────────
//  Demand path:   S_IDLE → S_MISS → S_FILL → S_IDLE
//  Prefetch path: S_IDLE → S_PF_MISS → S_PF_FILL → S_IDLE
//  Both paths share the same backing-memory bus (dmem_*).
//  The demand path holds priority: a pf can only start from
//  S_IDLE when no CPU access is pending.
localparam S_IDLE    = 3'd0;
localparam S_MISS    = 3'd1;
localparam S_FILL    = 3'd2;
localparam S_PF_MISS = 3'd3;
localparam S_PF_FILL = 3'd4;

reg [2:0]  state;

// Latched demand-miss info
reg [31:0] m_addr;
reg [31:0] m_pc;
wire [LOG_LINES-1:0] m_idx = m_addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     m_tag = m_addr[31 : OFFSET + LOG_LINES];

// Latched prefetch info
reg [31:0] pf_latch_addr;
wire [LOG_LINES-1:0] pfl_idx = pf_latch_addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     pfl_tag = pf_latch_addr[31 : OFFSET + LOG_LINES];

integer i;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state           <= S_IDLE;
        m_addr          <= 32'd0;
        m_pc            <= 32'd0;
        pf_latch_addr   <= 32'd0;

        dmem_read       <= 1'b0;
        dmem_write      <= 1'b0;
        dmem_addr       <= 32'd0;
        dmem_write_data <= 32'd0;

        obs_valid       <= 1'b0;
        obs_addr        <= 32'd0;
        obs_hit         <= 1'b0;
        obs_pc          <= 32'd0;

        stat_accesses   <= 32'd0;
        stat_hits       <= 32'd0;
        stat_misses     <= 32'd0;

        pf_accepted     <= 1'b0;
        pf_filled       <= 1'b0;
        pf_filled_addr  <= 32'd0;

        for (i = 0; i < LINES; i = i + 1) begin
            c_valid[i] <= 1'b0;
            c_tag[i]   <= {TAG_W{1'b0}};
            c_data[i]  <= 32'd0;
        end

    end else begin
        // Default one-cycle pulse resets
        dmem_read       <= 1'b0;
        dmem_write      <= 1'b0;
        dmem_addr       <= 32'd0;
        dmem_write_data <= 32'd0;

        obs_valid       <= 1'b0;
        obs_addr        <= 32'd0;
        obs_hit         <= 1'b0;
        obs_pc          <= 32'd0;

        pf_accepted     <= 1'b0;
        pf_filled       <= 1'b0;

        case (state)

            // ────────────────────────────────────────────
            S_IDLE: begin
                if (mem_read || mem_write) begin
                    // ── CPU demand access ────────────────
                    obs_valid     <= 1'b1;
                    obs_addr      <= addr;
                    obs_hit       <= hit;
                    obs_pc        <= pipeline_pc;
                    stat_accesses <= stat_accesses + 1;

                    if (mem_write) begin
                        dmem_write      <= 1'b1;
                        dmem_addr       <= addr;
                        dmem_write_data <= write_data;
                        if (hit)
                            c_data[idx] <= write_data;
                        stat_hits <= stat_hits + 1;

                    end else begin   // mem_read
                        if (hit) begin
                            stat_hits <= stat_hits + 1;
                            // read_data served combinatorially below
                        end else begin
                            stat_misses <= stat_misses + 1;
                            m_addr      <= addr;
                            m_pc        <= pipeline_pc;
                            dmem_read   <= 1'b1;
                            dmem_addr   <= addr;
                            state       <= S_MISS;
                        end
                    end

                end else if (pf_req && !pf_hit) begin
                    // ── Prefetch request (no CPU access this cycle) ──
                    // Accept silently; no stall.
                    pf_accepted   <= 1'b1;
                    pf_latch_addr <= pf_addr;
                    dmem_read     <= 1'b1;
                    dmem_addr     <= pf_addr;
                    state         <= S_PF_MISS;
                end
            end

            // ────────────────────────────────────────────
            // Demand miss: re-drive read for one cycle so
            // dmem sees at least 2 cycles of valid address
            S_MISS: begin
                dmem_read <= 1'b1;
                dmem_addr <= m_addr;
                state     <= S_FILL;
            end

            // Demand fill: latch data, return to CPU
            S_FILL: begin
                c_data[m_idx]  <= dmem_read_data;
                c_tag[m_idx]   <= m_tag;
                c_valid[m_idx] <= 1'b1;
                state          <= S_IDLE;
            end

            // ────────────────────────────────────────────
            // Prefetch miss: re-drive read (mirror of S_MISS)
            S_PF_MISS: begin
                dmem_read <= 1'b1;
                dmem_addr <= pf_latch_addr;
                state     <= S_PF_FILL;
            end

            // Prefetch fill: no CPU stall, just silently populate
            S_PF_FILL: begin
                c_data[pfl_idx]  <= dmem_read_data;
                c_tag[pfl_idx]   <= pfl_tag;
                c_valid[pfl_idx] <= 1'b1;

                pf_filled      <= 1'b1;
                pf_filled_addr <= pf_latch_addr;  // FIX: use latched pf_addr

                state <= S_IDLE;
            end

            default: state <= S_IDLE;

        endcase
    end
end

// ── read_data combinatorial mux ───────────────────────────
// FIX: Only return dmem_read_data to CPU during a DEMAND fill,
//      NOT during a prefetch fill (which would corrupt CPU reads).
always @(*) begin
    if (state == S_FILL)
        read_data = dmem_read_data;       // demand fill in progress
    else if (hit && mem_read)
        read_data = c_data[idx];          // cache hit
    else
        read_data = 32'd0;
end

// ── stall: only demand misses stall the CPU ───────────────
// FIX: Prefetch states (S_PF_MISS, S_PF_FILL) must NOT stall.
assign stall = (mem_read && !hit && state == S_IDLE) ||
               (state == S_MISS)                     ||
               (state == S_FILL);

endmodule

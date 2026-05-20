`timescale 1ns / 1ps
// ============================================================
//  l1_cache.v  — DEFINITIVE FIX (v3)
//
//  WHY pf_accepted WAS ALWAYS 0:
//
//  The original code only accepted a prefetch in S_IDLE when
//  BOTH: (a) no CPU mem access this cycle AND (b) cache is idle.
//  But the prefetch request (pf_req) was delivered through a
//  registered prefetch_controller, adding a 1-cycle delay.
//  In that 1 cycle, the CPU had already started a new demand
//  access (mem_read=1), so the "else if (pf_req && !mem_read)"
//  branch was NEVER taken — the demand branch always won.
//
//  The programs loop continuously (lw every few instructions),
//  so the cache spends almost no time in S_IDLE with no CPU
//  access happening simultaneously.
//
//  DEFINITIVE FIX:
//  1. Add an internal 1-entry "pending prefetch" register.
//     Any time pf_req arrives (even during S_MISS or S_FILL),
//     the address is latched immediately.
//  2. Separate prefetch states S_PF_MISS and S_PF_FILL handle
//     the fill without stalling the CPU.
//  3. On transition back to S_IDLE: if pending_pf is set AND
//     no CPU demand miss is needed, the pending prefetch fires
//     immediately — no wasted idle cycles.
//  4. pf_inflight is only HIGH during S_PF_MISS/S_PF_FILL.
//     This breaks the cache_stall|pf_inflight feedback loop
//     that kept cache_pf_busy permanently asserted.
//  5. stall never asserted during prefetch states.
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

    // Backing memory
    output reg  [31:0] dmem_addr,
    output reg         dmem_read,
    output reg         dmem_write,
    output reg  [31:0] dmem_write_data,
    input  wire [31:0] dmem_read_data,

    // Observation
    output reg         obs_valid,
    output reg  [31:0] obs_addr,
    output reg         obs_hit,
    output reg  [31:0] obs_pc,

    // Prefetch request in
    input  wire        pf_req,
    input  wire [31:0] pf_addr,

    // Prefetch status out
    output reg         pf_accepted,   // pulsed when prefetch latched
    output reg         pf_filled,     // pulsed when prefetch fill done
    output reg  [31:0] pf_filled_addr,
    output reg         pf_inflight,   // HIGH only during PF states (not demand)

    // Stats
    output reg  [31:0] stat_accesses,
    output reg  [31:0] stat_hits,
    output reg  [31:0] stat_misses,

    input  wire [31:0] pipeline_pc
);

localparam LOG_LINES = $clog2(LINES);
localparam TAG_W     = 32 - LOG_LINES - OFFSET;

// ── Address decode ─────────────────────────────────────────
wire [LOG_LINES-1:0] idx = addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     tag = addr[31 : OFFSET + LOG_LINES];

// ── Cache arrays ───────────────────────────────────────────
reg [TAG_W-1:0] c_tag   [0:LINES-1];
reg [31:0]      c_data  [0:LINES-1];
reg             c_valid [0:LINES-1];

wire hit = c_valid[idx] && (c_tag[idx] == tag);

// ── FSM states ─────────────────────────────────────────────
// Demand:  S_IDLE → S_MISS  → S_FILL    → S_IDLE  (CPU stalls)
// Prefetch:S_IDLE → S_PF_MISS → S_PF_FILL → S_IDLE (no stall)
localparam S_IDLE    = 3'd0;
localparam S_MISS    = 3'd1;
localparam S_FILL    = 3'd2;
localparam S_PF_MISS = 3'd3;
localparam S_PF_FILL = 3'd4;

reg [2:0] state;

// ── Demand miss registers ──────────────────────────────────
reg [31:0] m_addr;
reg [31:0] m_pc;
wire [LOG_LINES-1:0] m_idx = m_addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     m_tag = m_addr[31 : OFFSET + LOG_LINES];

// ── Pending prefetch register ──────────────────────────────
// Latches pf_req as soon as it arrives, regardless of cache state.
// This is the KEY fix: pf_req is never missed even during demand fills.
reg         pending_pf;
reg [31:0]  pending_pf_addr;

// Check if pending address is already in cache
wire [LOG_LINES-1:0] ppf_idx = pending_pf_addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     ppf_tag = pending_pf_addr[31 : OFFSET + LOG_LINES];
wire pending_pf_hit = c_valid[ppf_idx] && (c_tag[ppf_idx] == ppf_tag);

// ── Active prefetch fill registers ────────────────────────
reg [31:0] pf_latch;
wire [LOG_LINES-1:0] pfl_idx = pf_latch[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     pfl_tag = pf_latch[31 : OFFSET + LOG_LINES];

integer i;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state           <= S_IDLE;
        m_addr          <= 32'd0;
        m_pc            <= 32'd0;
        pf_latch        <= 32'd0;
        pending_pf      <= 1'b0;
        pending_pf_addr <= 32'd0;

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
        pf_inflight     <= 1'b0;

        for (i = 0; i < LINES; i = i + 1) begin
            c_valid[i] <= 1'b0;
            c_tag[i]   <= {TAG_W{1'b0}};
            c_data[i]  <= 32'd0;
        end

    end else begin
        // ── Default pulse resets ────────────────────────────
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

        // pf_inflight: HIGH only during prefetch fill — NOT demand fill
        pf_inflight <= (state == S_PF_MISS) || (state == S_PF_FILL);

        // ── Latch incoming prefetch request immediately ─────
        // This happens UNCONDITIONALLY regardless of cache state.
        // If a new pf_req arrives while one is pending, overwrite
        // with the newer address (more likely to be useful).
        if (pf_req) begin
            pending_pf      <= 1'b1;
            pending_pf_addr <= pf_addr;
            pf_accepted     <= 1'b1;  // pulse accepted immediately on latch
        end

        // ── State machine ───────────────────────────────────
        case (state)

            S_IDLE: begin
                if (mem_read || mem_write) begin
                    // ── CPU demand: highest priority ─────────
                    obs_valid     <= 1'b1;
                    obs_addr      <= addr;
                    obs_hit       <= hit;
                    obs_pc        <= pipeline_pc;
                    stat_accesses <= stat_accesses + 1;

                    if (mem_write) begin
                        dmem_write      <= 1'b1;
                        dmem_addr       <= addr;
                        dmem_write_data <= write_data;
                        if (hit) c_data[idx] <= write_data;
                        stat_hits <= stat_hits + 1;

                    end else begin  // mem_read
                        if (hit) begin
                            stat_hits <= stat_hits + 1;
                        end else begin
                            stat_misses <= stat_misses + 1;
                            m_addr    <= addr;
                            m_pc      <= pipeline_pc;
                            dmem_read <= 1'b1;
                            dmem_addr <= addr;
                            state     <= S_MISS;
                        end
                    end

                end else if (pending_pf && !pending_pf_hit) begin
                    // ── Serve pending prefetch (no CPU access this cycle) ──
                    pf_latch   <= pending_pf_addr;
                    pending_pf <= 1'b0;
                    dmem_read  <= 1'b1;
                    dmem_addr  <= pending_pf_addr;
                    state      <= S_PF_MISS;

                end else if (pending_pf && pending_pf_hit) begin
                    // Already in cache — discard
                    pending_pf <= 1'b0;
                end
            end

            // ── Demand fill (CPU stalls) ────────────────────
            S_MISS: begin
                dmem_read <= 1'b1;
                dmem_addr <= m_addr;
                state     <= S_FILL;
            end

            S_FILL: begin
                c_data[m_idx]  <= dmem_read_data;
                c_tag[m_idx]   <= m_tag;
                c_valid[m_idx] <= 1'b1;
                state          <= S_IDLE;
                // On next cycle (S_IDLE), pending_pf will be served
                // if no CPU access is needed
            end

            // ── Prefetch fill (no CPU stall) ────────────────
            S_PF_MISS: begin
                dmem_read <= 1'b1;
                dmem_addr <= pf_latch;
                state     <= S_PF_FILL;
            end

            S_PF_FILL: begin
                c_data[pfl_idx]  <= dmem_read_data;
                c_tag[pfl_idx]   <= pfl_tag;
                c_valid[pfl_idx] <= 1'b1;

                pf_filled      <= 1'b1;
                pf_filled_addr <= pf_latch;

                state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

// ── read_data mux ──────────────────────────────────────────
always @(*) begin
    if (state == S_FILL)
        read_data = dmem_read_data;   // demand fill: forward to CPU
    else if (hit && mem_read)
        read_data = c_data[idx];      // cache hit
    else
        read_data = 32'd0;
end

// ── stall: ONLY demand miss states stall the CPU ───────────
assign stall = (mem_read && !hit && state == S_IDLE) ||
               (state == S_MISS)                     ||
               (state == S_FILL);

endmodule

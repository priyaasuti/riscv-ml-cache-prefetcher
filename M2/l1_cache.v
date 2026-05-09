`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.05.2026 20:47:14
// Design Name: 
// Module Name: l1_cache
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// ============================================================
// l1_cache.v  -  Direct-mapped, write-through L1 data cache
//
// Parameters
//   LINES  : number of cache lines (power of 2).  Default 16.
//   OFFSET : log2(bytes per line).  Default 2 → 4-byte lines.
//
// Address breakdown (32-bit byte address, word-granular lines)
//   [31 : OFFSET+LOG_LINES]        tag
//   [OFFSET+LOG_LINES-1 : OFFSET]  index  (LOG_LINES bits)
//   [OFFSET-1 : 0]                 byte offset (ignored)
//
// Policy
//   Read hit   → combinational, stall = 0
//   Read miss  → stall = 1 for 2 extra cycles (S_MISS → S_FILL)
//   Write      → write-through, no-write-allocate, no stall
//
// Observation port: obs_valid pulses on every CPU access.
// Prefetch port: pf_req/pf_addr - tie pf_req=0 for Phase 2.
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
    output wire        stall,       // combinational

    // Backing memory interface
    output reg  [31:0] dmem_addr,
    output reg         dmem_read,
    output reg         dmem_write,
    output reg  [31:0] dmem_write_data,
    input  wire [31:0] dmem_read_data,

    // Observation port (ML logging)
    output reg         obs_valid,
    output reg  [31:0] obs_addr,
    output reg         obs_hit,
    output reg  [31:0] obs_pc,

    // Prefetch port (tie pf_req=0 until Phase 3)
    input  wire        pf_req,
    input  wire [31:0] pf_addr,

    // Performance counters
    output reg  [31:0] stat_accesses,
    output reg  [31:0] stat_hits,
    output reg  [31:0] stat_misses,

    // PC from pipeline (wire to EX/MEM pc)
    input  wire [31:0] pipeline_pc
);

// ── Widths ────────────────────────────────────────────────
localparam LOG_LINES = $clog2(LINES);
localparam TAG_W     = 32 - LOG_LINES - OFFSET;

// ── Address fields (current request) ─────────────────────
wire [LOG_LINES-1:0] idx = addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     tag = addr[31 : OFFSET + LOG_LINES];

// ── Address fields (prefetch request) ────────────────────
wire [LOG_LINES-1:0] pf_idx = pf_addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     pf_tag = pf_addr[31 : OFFSET + LOG_LINES];

// ── Cache arrays ──────────────────────────────────────────
reg [TAG_W-1:0] c_tag   [0:LINES-1];
reg [31:0]      c_data  [0:LINES-1];
reg             c_valid [0:LINES-1];

// ── Hit detect ────────────────────────────────────────────
wire hit = c_valid[idx] && (c_tag[idx] == tag);

// ── FSM states ────────────────────────────────────────────
localparam S_IDLE = 2'd0;
localparam S_MISS = 2'd1;
localparam S_FILL = 2'd2;

reg [1:0]  state;
reg [31:0] m_addr;   // latched miss address
reg [31:0] m_pc;     // latched miss PC
reg        m_is_pf;  // 1 = prefetch, suppress stall

// ── Miss address decomposition ────────────────────────────
wire [LOG_LINES-1:0] m_idx = m_addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     m_tag = m_addr[31 : OFFSET + LOG_LINES];

integer i;

// ── Sequential logic ──────────────────────────────────────
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state           <= S_IDLE;
        m_addr          <= 32'd0;
        m_pc            <= 32'd0;
        m_is_pf         <= 1'b0;
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
        for (i = 0; i < LINES; i = i + 1) begin
            c_valid[i] <= 1'b0;
            c_tag[i]   <= {TAG_W{1'b0}};
            c_data[i]  <= 32'd0;
        end
    end else begin
        // Safe defaults
        dmem_read       <= 1'b0;
        dmem_write      <= 1'b0;
        dmem_addr       <= 32'd0;
        dmem_write_data <= 32'd0;
        obs_valid       <= 1'b0;
        obs_addr        <= 32'd0;
        obs_hit         <= 1'b0;
        obs_pc          <= 32'd0;

        case (state)

            S_IDLE: begin

                if (mem_read || mem_write) begin
                    // Observation pulse
                    obs_valid <= 1'b1;
                    obs_addr  <= addr;
                    obs_hit   <= hit;
                    obs_pc    <= pipeline_pc;
                    stat_accesses <= stat_accesses + 1;

                    if (mem_write) begin
                        // Write-through: always push to backing store
                        dmem_write      <= 1'b1;
                        dmem_addr       <= addr;
                        dmem_write_data <= write_data;
                        // Update cache if line present
                        if (hit) c_data[idx] <= write_data;
                        stat_hits <= stat_hits + 1; // writes never stall

                    end else begin // mem_read
                        if (hit) begin
                            stat_hits <= stat_hits + 1;
                        end else begin
                            // Read miss
                            stat_misses <= stat_misses + 1;
                            m_addr      <= addr;
                            m_pc        <= pipeline_pc;
                            m_is_pf     <= 1'b0;
                            dmem_read   <= 1'b1;
                            dmem_addr   <= addr;
                            state       <= S_MISS;
                        end
                    end

                end else if (pf_req) begin
                    // Prefetch: silent, no stall
                    if (!(c_valid[pf_idx] && c_tag[pf_idx] == pf_tag)) begin
                        m_addr    <= pf_addr;
                        m_pc      <= 32'hDEADBEEF;
                        m_is_pf   <= 1'b1;
                        dmem_read <= 1'b1;
                        dmem_addr <= pf_addr;
                        state     <= S_MISS;
                    end
                end
            end

            S_MISS: begin
                // Keep dmem address stable; wait one cycle for read data
                dmem_read <= 1'b1;
                dmem_addr <= m_addr;
                state     <= S_FILL;
            end

            S_FILL: begin
                // dmem_read_data is valid now - fill the line
                c_data[m_idx]  <= dmem_read_data;
                c_tag[m_idx]   <= m_tag;
                c_valid[m_idx] <= 1'b1;
                state          <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

// ── Combinational read output ─────────────────────────────
always @(*) begin
    if (state == S_FILL)
        read_data = dmem_read_data;          // serve refill data immediately
    else if (hit && mem_read)
        read_data = c_data[idx];             // hit: serve from cache
    else
        read_data = 32'd0;
end


// ── Combinational stall ───────────────────────────────────
// Assert immediately (same cycle) when a read miss is detected
// so that ALL pipeline registers freeze on the SAME posedge.
assign stall = (mem_read && !hit && (state == S_IDLE))
             || (state == S_MISS)
             || (state == S_FILL);

endmodule

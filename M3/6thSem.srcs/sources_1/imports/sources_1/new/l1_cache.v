`timescale 1ns / 1ps

module l1_cache #(
    parameter LINES  = 16,
    parameter OFFSET = 2
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data,
    output wire        stall,

    output reg  [31:0] dmem_addr,
    output reg         dmem_read,
    output reg         dmem_write,
    output reg  [31:0] dmem_write_data,
    input  wire [31:0] dmem_read_data,

    output reg         obs_valid,
    output reg  [31:0] obs_addr,
    output reg         obs_hit,
    output reg  [31:0] obs_pc,

    input  wire        pf_req,
    input  wire [31:0] pf_addr,

    output reg         pf_accepted,
    output reg         pf_filled,
    output reg  [31:0] pf_filled_addr,

    output reg  [31:0] stat_accesses,
    output reg  [31:0] stat_hits,
    output reg  [31:0] stat_misses,

    input  wire [31:0] pipeline_pc
);

localparam LOG_LINES = $clog2(LINES);
localparam TAG_W     = 32 - LOG_LINES - OFFSET;

wire [LOG_LINES-1:0] idx = addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     tag = addr[31 : OFFSET + LOG_LINES];

wire [LOG_LINES-1:0] pf_idx = pf_addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     pf_tag = pf_addr[31 : OFFSET + LOG_LINES];

reg [TAG_W-1:0] c_tag   [0:LINES-1];
reg [31:0]      c_data  [0:LINES-1];
reg             c_valid [0:LINES-1];

wire hit    = c_valid[idx] && (c_tag[idx] == tag);
wire pf_hit = c_valid[pf_idx] && (c_tag[pf_idx] == pf_tag);

localparam S_IDLE = 2'd0;
localparam S_MISS = 2'd1;
localparam S_FILL = 2'd2;

reg [1:0]  state;
reg [31:0] m_addr;
reg [31:0] m_pc;
reg        m_is_pf;

wire [LOG_LINES-1:0] m_idx = m_addr[OFFSET + LOG_LINES - 1 : OFFSET];
wire [TAG_W-1:0]     m_tag = m_addr[31 : OFFSET + LOG_LINES];

integer i;

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

        pf_accepted     <= 1'b0;
        pf_filled       <= 1'b0;
        pf_filled_addr  <= 32'd0;

        for (i = 0; i < LINES; i = i + 1) begin
            c_valid[i] <= 1'b0;
            c_tag[i]   <= {TAG_W{1'b0}};
            c_data[i]  <= 32'd0;
        end
    end else begin
        dmem_read       <= 1'b0;
        dmem_write      <= 1'b0;
        dmem_addr       <= 32'd0;
        dmem_write_data <= 32'd0;

        obs_valid       <= 1'b0;
        obs_addr        <= 32'd0;
        obs_hit         <= 1'b0;
        obs_pc          <= 32'd0;

        // one-cycle debug pulses
        pf_accepted     <= 1'b0;
        pf_filled       <= 1'b0;

        case (state)

            S_IDLE: begin
                m_is_pf <= 1'b0;

                if (mem_read || mem_write) begin
                    obs_valid <= 1'b1;
                    obs_addr  <= addr;
                    obs_hit   <= hit;
                    obs_pc    <= pipeline_pc;

                    stat_accesses <= stat_accesses + 1;

                    if (mem_write) begin
                        dmem_write      <= 1'b1;
                        dmem_addr       <= addr;
                        dmem_write_data <= write_data;

                        if (hit)
                            c_data[idx] <= write_data;

                        stat_hits <= stat_hits + 1;

                    end else begin
                        if (hit) begin
                            stat_hits <= stat_hits + 1;
                        end else begin
                            stat_misses <= stat_misses + 1;

                            m_addr    <= addr;
                            m_pc      <= pipeline_pc;
                            m_is_pf   <= 1'b0;

                            dmem_read <= 1'b1;
                            dmem_addr <= addr;

                            state     <= S_MISS;
                        end
                    end

  end else if (pf_req && !pf_hit && !mem_read && !mem_write) begin
                    // Prefetch: silent, no CPU stall
                    pf_accepted <= 1'b1;

                    m_addr    <= pf_addr;
                    m_pc      <= 32'hDEADBEEF;
                    m_is_pf   <= 1'b1;

                    dmem_read <= 1'b1;
                    dmem_addr <= pf_addr;

                    state     <= S_MISS;
                end
            end

            S_MISS: begin
                dmem_read <= 1'b1;
                dmem_addr <= m_addr;
                state     <= S_FILL;
            end

            S_FILL: begin
                c_data[m_idx]  <= dmem_read_data;
                c_tag[m_idx]   <= m_tag;
                c_valid[m_idx] <= 1'b1;

                if (m_is_pf) begin
                    pf_filled      <= 1'b1;
                    pf_filled_addr <= m_addr;
                end

                state   <= S_IDLE;
                m_is_pf <= 1'b0;
            end

            default: begin
                state   <= S_IDLE;
                m_is_pf <= 1'b0;
            end

        endcase
    end
end

always @(*) begin
    if (state == S_FILL && !m_is_pf)
        read_data = dmem_read_data;
    else if (hit && mem_read)
        read_data = c_data[idx];
    else
        read_data = 32'd0;
end

assign stall = (!m_is_pf) &&
               (
                   (mem_read && !hit && (state == S_IDLE)) ||
                   (state == S_MISS) ||
                   (state == S_FILL)
               );

endmodule
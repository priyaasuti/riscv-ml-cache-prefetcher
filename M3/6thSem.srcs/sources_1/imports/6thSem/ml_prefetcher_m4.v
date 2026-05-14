`timescale 1ns / 1ps
// ============================================================
//  ml_prefetcher_m4.v  –  FIXED VERSION
//
//  Bugs / missing features fixed:
//  1. Previously only ONE prefetch address was emitted per ML
//     inference (base + stride×1). The ML model dataset has
//     four stride patterns: stride-1 (×4 bytes), stride-2
//     (×8 bytes), stride-4 (×16 bytes), stride-8 (×32 bytes).
//     Now, after every engine_done, a mini-sequencer walks
//     through all 4 stride-scaled variants of engine_out and
//     emits them as separate pf_req pulses, one per cycle.
//
//  2. Fixed: pf_req was being driven on the same cycle as
//     engine_done but then cleared on the next cycle because
//     start_engine reset it. Now pf_req pulses are generated
//     by a dedicated emit FSM so they don't collide.
//
//  Stride patterns applied (matching dataset):
//    delta × 1  → address + (delta_i8 << 2) × 1
//    delta × 2  → address + (delta_i8 << 2) × 2
//    delta × 4  → address + (delta_i8 << 2) × 4
//    delta × 8  → address + (delta_i8 << 2) × 8
// ============================================================

module ml_prefetcher_m4 (
    input  wire        clk,
    input  wire        reset,

    input  wire        obs_valid,
    input  wire [31:0] current_addr,

    output reg         pf_req,
    output reg  [31:0] pf_addr,

    output wire        ml_busy,
    output wire        ml_done,
    output wire signed [7:0] ml_delta_out
);

    // ── Delta tracking ──────────────────────────────────────
    reg [31:0] prev_addr;
    reg        have_prev;

    reg signed [31:0] raw_delta;
    reg signed [7:0]  delta_i8;

    reg [63:0] delta_window;
    reg [63:0] engine_window;

    reg [3:0] window_count;
    reg [31:0] last_addr_for_prediction;

    reg start_engine;

    // ── MLP engine instance ─────────────────────────────────
    wire signed [7:0] engine_out;
    wire engine_busy;
    wire engine_done;

    assign ml_busy      = engine_busy;
    assign ml_done      = engine_done;
    assign ml_delta_out = engine_out;

    mlp_engine_m4 ENGINE (
        .clk(clk),
        .reset(reset),
        .start(start_engine),
        .delta_window(engine_window),
        .busy(engine_busy),
        .done(engine_done),
        .mlp_out(engine_out)
    );

    // ── Multi-stride emit FSM ───────────────────────────────
    // After engine_done, emit 4 prefetch requests, one per cycle,
    // for stride multipliers: 1, 2, 4, 8.
    // Each pf_addr = base + (engine_out_signed << 2) * stride_mul
    //
    // stride_mul[i] = 1 << i  for i in {0,1,2,3}
    //
    localparam EMIT_IDLE = 3'd0;
    localparam EMIT_S1   = 3'd1;   // stride ×1
    localparam EMIT_S2   = 3'd2;   // stride ×2
    localparam EMIT_S4   = 3'd3;   // stride ×4
    localparam EMIT_S8   = 3'd4;   // stride ×8

    reg [2:0] emit_state;
    reg [31:0] base_addr_latch;
    reg signed [7:0] delta_latch;

    // Precompute the word-aligned signed displacement for stride-1
    // (delta_i8 × 4 bytes). Then scale by 1/2/4/8.
    wire signed [31:0] disp1 = {{22{delta_latch[7]}}, delta_latch, 2'b00};   // ×1 word
    wire signed [31:0] disp2 = {{21{delta_latch[7]}}, delta_latch, 3'b000};  // ×2
    wire signed [31:0] disp4 = {{20{delta_latch[7]}}, delta_latch, 4'b0000}; // ×4
    wire signed [31:0] disp8 = {{19{delta_latch[7]}}, delta_latch, 5'b00000};// ×8

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            prev_addr                <= 32'd0;
            have_prev                <= 1'b0;
            raw_delta                <= 32'sd0;
            delta_i8                 <= 8'sd0;
            delta_window             <= 64'd0;
            engine_window            <= 64'd0;
            window_count             <= 4'd0;
            last_addr_for_prediction <= 32'd0;
            start_engine             <= 1'b0;
            pf_req                   <= 1'b0;
            pf_addr                  <= 32'd0;

            emit_state               <= EMIT_IDLE;
            base_addr_latch          <= 32'd0;
            delta_latch              <= 8'sd0;

        end else begin

            // Default pulses
            start_engine <= 1'b0;
            pf_req       <= 1'b0;

            // ── Observe memory accesses and build delta window ──
            if (obs_valid) begin
                if (!have_prev) begin
                    prev_addr <= current_addr;
                    have_prev <= 1'b1;
                end else begin

                    raw_delta = $signed(current_addr) - $signed(prev_addr);

                    // Quantise to word units, clamp to int8
                    if ((raw_delta >>> 2) > 32'sd127)
                        delta_i8 = 8'sd127;
                    else if ((raw_delta >>> 2) < -32'sd128)
                        delta_i8 = -8'sd128;
                    else
                        delta_i8 = (raw_delta >>> 2);

                    delta_window <= {delta_window[55:0], delta_i8};

                    if (window_count < 4'd8)
                        window_count <= window_count + 4'd1;

                    prev_addr <= current_addr;

                    // Launch engine once window is full and engine is idle
                    if ((window_count >= 4'd7) && !engine_busy &&
                        (emit_state == EMIT_IDLE)) begin
                        engine_window            <= {delta_window[55:0], delta_i8};
                        last_addr_for_prediction <= current_addr;
                        start_engine             <= 1'b1;
                    end
                end
            end

            // ── Capture result and start emit sequencer ─────────
            if (engine_done) begin
                base_addr_latch <= last_addr_for_prediction;
                delta_latch     <= engine_out;
                emit_state      <= EMIT_S1;
            end

            // ── Emit FSM: one pf_req per cycle per stride ───────
            case (emit_state)
                EMIT_IDLE: ; // wait for engine_done

                EMIT_S1: begin
                    pf_req     <= 1'b1;
                    pf_addr    <= base_addr_latch + disp1;
                    emit_state <= EMIT_S2;
                end

                EMIT_S2: begin
                    pf_req     <= 1'b1;
                    pf_addr    <= base_addr_latch + disp2;
                    emit_state <= EMIT_S4;
                end

                EMIT_S4: begin
                    pf_req     <= 1'b1;
                    pf_addr    <= base_addr_latch + disp4;
                    emit_state <= EMIT_S8;
                end

                EMIT_S8: begin
                    pf_req     <= 1'b1;
                    pf_addr    <= base_addr_latch + disp8;
                    emit_state <= EMIT_IDLE;
                end

                default: emit_state <= EMIT_IDLE;
            endcase
        end
    end

endmodule

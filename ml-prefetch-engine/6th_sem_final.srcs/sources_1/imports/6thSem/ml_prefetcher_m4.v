`timescale 1ns / 1ps

// ML prefetch engine for M4 trace patterns:
//   A) pure stride
//   B) hit-hit-miss repeat
//   C) random-window reread
//   D) large jump / function-call boundary
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

    reg [31:0] prev_addr;
    reg        have_prev;

    reg signed [31:0] raw_delta;
    reg signed [7:0]  delta_i8;

    reg [63:0] delta_window;
    reg [63:0] engine_window;

    reg [3:0] window_count;
    reg [31:0] last_addr_for_prediction;

    reg start_engine;

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
        end else begin

            start_engine <= 1'b0;
            pf_req       <= 1'b0;

            if (obs_valid) begin
                if (!have_prev) begin
                    prev_addr <= current_addr;
                    have_prev <= 1'b1;
                end else begin

                    raw_delta = $signed(current_addr) - $signed(prev_addr);

                    if ((raw_delta >>> 2) > 32'sd127)
                        delta_i8 = 8'sd127;
                    else if ((raw_delta >>> 2) < -32'sd128)
                        delta_i8 = -8'sd128;
                    else
                        delta_i8 = (raw_delta >>> 2);

delta_window <= {delta_i8, delta_window[63:8]};

                    if (window_count < 4'd8)
                        window_count <= window_count + 4'd1;

                    prev_addr <= current_addr;

                    if ((window_count >= 4'd7) && !engine_busy) begin
                        engine_window <= {delta_window[55:0], delta_i8};
                        last_addr_for_prediction <= current_addr;
                        start_engine <= 1'b1;
                    end
                end
            end

            if (engine_done) begin
    pf_req  <= 1'b1;
    pf_addr <= last_addr_for_prediction + 
               ($signed({{24{engine_out[7]}}, engine_out}) * 32'sd4);
end
 
        end
    end

endmodule
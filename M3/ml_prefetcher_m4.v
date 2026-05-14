`timescale 1ns / 1ps

module ml_prefetcher_m4 (
    input  wire        clk,
    input  wire        reset,

    // Use l1_cache observation pulse/signals
    input  wire        obs_valid,
    input  wire [31:0] current_addr,

    output reg         pf_req,
    output reg  [31:0] pf_addr,

    // Useful for waveform/debug
    output wire        ml_busy,
    output wire        ml_done,
    output wire signed [7:0] ml_delta_out
);

reg [31:0] prev_addr;
reg        have_prev;

reg signed [7:0] d0;
reg signed [7:0] d1;
reg signed [7:0] d2;
reg signed [7:0] d3;
reg signed [7:0] d4;
reg signed [7:0] d5;
reg signed [7:0] d6;
reg signed [7:0] d7;

reg [31:0] last_addr_for_prediction;
reg        start_engine;

wire [63:0] delta_window;
assign delta_window = {d7, d6, d5, d4, d3, d2, d1, d0};

wire signed [7:0] engine_out;

mlp_engine_m4 ENGINE (
    .clk(clk),
    .reset(reset),
    .start(start_engine),
    .delta_window(delta_window),
    .busy(ml_busy),
    .done(ml_done),
    .mlp_out(engine_out)
);

assign ml_delta_out = engine_out;

function signed [7:0] clamp_stride_i8;
    input signed [31:0] x;
    begin
        if (x > 32'sd127)
            clamp_stride_i8 = 8'sd127;
        else if (x < -32'sd128)
            clamp_stride_i8 = -8'sd128;
        else
            clamp_stride_i8 = x[7:0];
    end
endfunction

wire signed [31:0] raw_delta;
wire signed [31:0] stride_32;
wire signed [31:0] predicted_bytes;

assign raw_delta       = $signed(current_addr) - $signed(prev_addr);
assign stride_32       = raw_delta >>> 2;              // divide by cache line size = 4
assign predicted_bytes = $signed(engine_out) <<< 2;    // multiply predicted stride by 4

always @(posedge clk or posedge reset) begin
    if (reset) begin
        prev_addr <= 32'd0;
        have_prev <= 1'b0;

        d0 <= 8'sd0;
        d1 <= 8'sd0;
        d2 <= 8'sd0;
        d3 <= 8'sd0;
        d4 <= 8'sd0;
        d5 <= 8'sd0;
        d6 <= 8'sd0;
        d7 <= 8'sd0;

        last_addr_for_prediction <= 32'd0;
        start_engine <= 1'b0;

        pf_req <= 1'b0;
        pf_addr <= 32'd0;
    end else begin
        start_engine <= 1'b0;
        pf_req <= 1'b0;

        if (obs_valid) begin
            if (have_prev && !ml_busy) begin
                // Shift in newest delta.
                d7 <= d6;
                d6 <= d5;
                d5 <= d4;
                d4 <= d3;
                d3 <= d2;
                d2 <= d1;
                d1 <= d0;
                d0 <= clamp_stride_i8(stride_32);

                last_addr_for_prediction <= current_addr;
                start_engine <= 1'b1;
            end

            prev_addr <= current_addr;
            have_prev <= 1'b1;
        end

        if (ml_done) begin
            if (engine_out != 8'sd0) begin
                pf_req  <= 1'b1;
                pf_addr <= last_addr_for_prediction + predicted_bytes[31:0];
            end else begin
                pf_req  <= 1'b0;
                pf_addr <= 32'd0;
            end
        end
    end
end

endmodule

`include "mlp_pkg1.vh"

module ml_prefetcher (
    input clk,
    input reset,

    input [31:0] addr,
    input obs_hit,

    output reg pf_req,
    output reg [31:0] pf_addr
);

    reg [31:0] prev_addr;
    reg [31:0] stride;

    wire signed [`DATA_W-1:0] x0;
    wire signed [`DATA_W-1:0] x1;
    wire signed [`DATA_W-1:0] x2;
    wire signed [`DATA_W-1:0] x3;

    wire signed [`DATA_W-1:0] h0;
    wire signed [`DATA_W-1:0] h1;
    wire signed [`DATA_W-1:0] h2;
    wire signed [`DATA_W-1:0] h3;
    wire signed [`DATA_W-1:0] h4;
    wire signed [`DATA_W-1:0] h5;
    wire signed [`DATA_W-1:0] h6;
    wire signed [`DATA_W-1:0] h7;

    wire signed [`DATA_W-1:0] ml_out;

    assign x0 = addr[15:0];
    assign x1 = prev_addr[15:0];
    assign x2 = stride[15:0];
    assign x3 = obs_hit ? 16'sd256 : 16'sd0;

    mlp_hidden_layer HIDDEN (
        .x0(x0), .x1(x1), .x2(x2), .x3(x3),
        .h0(h0), .h1(h1), .h2(h2), .h3(h3),
        .h4(h4), .h5(h5), .h6(h6), .h7(h7)
    );

    output_neuron OUT (
        .h0(h0), .h1(h1), .h2(h2), .h3(h3),
        .h4(h4), .h5(h5), .h6(h6), .h7(h7),
        .out_data(ml_out)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            prev_addr <= 32'd0;
            stride    <= 32'd0;
            pf_req    <= 1'b0;
            pf_addr   <= 32'd0;
        end else begin
            stride    <= addr - prev_addr;
            prev_addr <= addr;

            if (ml_out > 16'sd128) begin
                pf_req  <= 1'b1;
                pf_addr <= addr + stride;
            end else begin
                pf_req  <= 1'b0;
                pf_addr <= 32'd0;
            end
        end
    end

endmodule
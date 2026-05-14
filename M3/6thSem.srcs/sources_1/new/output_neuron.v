`include "mlp_pkg1.vh"

module output_neuron (
    input signed [`DATA_W-1:0] h0,
    input signed [`DATA_W-1:0] h1,
    input signed [`DATA_W-1:0] h2,
    input signed [`DATA_W-1:0] h3,
    input signed [`DATA_W-1:0] h4,
    input signed [`DATA_W-1:0] h5,
    input signed [`DATA_W-1:0] h6,
    input signed [`DATA_W-1:0] h7,

    output signed [`DATA_W-1:0] out_data
);

    wire signed [`DATA_W-1:0] m0;
    wire signed [`DATA_W-1:0] m1;
    wire signed [`DATA_W-1:0] m2;
    wire signed [`DATA_W-1:0] m3;
    wire signed [`DATA_W-1:0] m4;
    wire signed [`DATA_W-1:0] m5;
    wire signed [`DATA_W-1:0] m6;
    wire signed [`DATA_W-1:0] m7;

    fixed_mac MAC0 (
        .in_data(h0),
        .weight(16'sd0),
        .bias(16'sd0),
        .out_data(m0)
    );

    fixed_mac MAC1 (
        .in_data(h1),
        .weight(16'sd0),
        .bias(16'sd0),
        .out_data(m1)
    );

    fixed_mac MAC2 (
        .in_data(h2),
        .weight(16'sd0),
        .bias(16'sd0),
        .out_data(m2)
    );

    fixed_mac MAC3 (
        .in_data(h3),
        .weight(16'sd0),
        .bias(16'sd0),
        .out_data(m3)
    );

    fixed_mac MAC4 (
        .in_data(h4),
        .weight(16'sd0),
        .bias(16'sd0),
        .out_data(m4)
    );

    fixed_mac MAC5 (
        .in_data(h5),
        .weight(16'sd0),
        .bias(16'sd0),
        .out_data(m5)
    );

    fixed_mac MAC6 (
        .in_data(h6),
        .weight(16'sd0),
        .bias(16'sd0),
        .out_data(m6)
    );

    fixed_mac MAC7 (
        .in_data(h7),
        .weight(16'sd0),
        .bias(16'sd0),
        .out_data(m7)
    );

    assign out_data =
        m0 + m1 + m2 + m3 +
        m4 + m5 + m6 + m7;

endmodule
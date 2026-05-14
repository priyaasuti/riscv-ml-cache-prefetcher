`include "mlp_pkg1.vh"

module mlp_hidden_layer (
    input signed [`DATA_W-1:0] x0,
    input signed [`DATA_W-1:0] x1,
    input signed [`DATA_W-1:0] x2,
    input signed [`DATA_W-1:0] x3,

    output signed [`DATA_W-1:0] h0,
    output signed [`DATA_W-1:0] h1,
    output signed [`DATA_W-1:0] h2,
    output signed [`DATA_W-1:0] h3,
    output signed [`DATA_W-1:0] h4,
    output signed [`DATA_W-1:0] h5,
    output signed [`DATA_W-1:0] h6,
    output signed [`DATA_W-1:0] h7
);

    hidden_neuron H0 (
        .x0(x0), .x1(x1), .x2(x2), .x3(x3),
        .w0(16'sd0), .w1(16'sd0), .w2(16'sd0), .w3(16'sd0),
        .bias(16'sd0),
        .out_data(h0)
    );

    hidden_neuron H1 (
        .x0(x0), .x1(x1), .x2(x2), .x3(x3),
        .w0(16'sd0), .w1(16'sd0), .w2(16'sd0), .w3(16'sd0),
        .bias(16'sd0),
        .out_data(h1)
    );

    hidden_neuron H2 (
        .x0(x0), .x1(x1), .x2(x2), .x3(x3),
        .w0(16'sd0), .w1(16'sd0), .w2(16'sd0), .w3(16'sd0),
        .bias(16'sd0),
        .out_data(h2)
    );

    hidden_neuron H3 (
        .x0(x0), .x1(x1), .x2(x2), .x3(x3),
        .w0(16'sd0), .w1(16'sd0), .w2(16'sd0), .w3(16'sd0),
        .bias(16'sd0),
        .out_data(h3)
    );

    hidden_neuron H4 (
        .x0(x0), .x1(x1), .x2(x2), .x3(x3),
        .w0(16'sd0), .w1(16'sd0), .w2(16'sd0), .w3(16'sd0),
        .bias(16'sd0),
        .out_data(h4)
    );

    hidden_neuron H5 (
        .x0(x0), .x1(x1), .x2(x2), .x3(x3),
        .w0(16'sd0), .w1(16'sd0), .w2(16'sd0), .w3(16'sd0),
        .bias(16'sd0),
        .out_data(h5)
    );

    hidden_neuron H6 (
        .x0(x0), .x1(x1), .x2(x2), .x3(x3),
        .w0(16'sd0), .w1(16'sd0), .w2(16'sd0), .w3(16'sd0),
        .bias(16'sd0),
        .out_data(h6)
    );

    hidden_neuron H7 (
        .x0(x0), .x1(x1), .x2(x2), .x3(x3),
        .w0(16'sd0), .w1(16'sd0), .w2(16'sd0), .w3(16'sd0),
        .bias(16'sd0),
        .out_data(h7)
    );

endmodule
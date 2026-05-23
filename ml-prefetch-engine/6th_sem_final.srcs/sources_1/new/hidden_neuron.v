`include "mlp_pkg1.vh"

module hidden_neuron (
    input signed [`DATA_W-1:0] x0,
    input signed [`DATA_W-1:0] x1,
    input signed [`DATA_W-1:0] x2,
    input signed [`DATA_W-1:0] x3,

    input signed [`DATA_W-1:0] w0,
    input signed [`DATA_W-1:0] w1,
    input signed [`DATA_W-1:0] w2,
    input signed [`DATA_W-1:0] w3,

    input signed [`DATA_W-1:0] bias,

    output signed [`DATA_W-1:0] out_data
);

    wire signed [`DATA_W-1:0] mac0;
    wire signed [`DATA_W-1:0] mac1;
    wire signed [`DATA_W-1:0] mac2;
    wire signed [`DATA_W-1:0] mac3;

    wire signed [`DATA_W-1:0] sum01;
    wire signed [`DATA_W-1:0] sum23;
    wire signed [`DATA_W-1:0] sum_all;

    wire signed [`DATA_W-1:0] relu_out;

    fixed_mac MAC0 (
        .in_data(x0),
        .weight(w0),
        .bias(16'sd0),
        .out_data(mac0)
    );

    fixed_mac MAC1 (
        .in_data(x1),
        .weight(w1),
        .bias(16'sd0),
        .out_data(mac1)
    );

    fixed_mac MAC2 (
        .in_data(x2),
        .weight(w2),
        .bias(16'sd0),
        .out_data(mac2)
    );

    fixed_mac MAC3 (
        .in_data(x3),
        .weight(w3),
        .bias(16'sd0),
        .out_data(mac3)
    );

    assign sum01   = mac0 + mac1;
    assign sum23   = mac2 + mac3;
    assign sum_all = sum01 + sum23 + bias;

    relu RELU0 (
        .in_data(sum_all),
        .out_data(relu_out)
    );

    assign out_data = relu_out;

endmodule
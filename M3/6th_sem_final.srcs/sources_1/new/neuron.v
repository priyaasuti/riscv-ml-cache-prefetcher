`include "mlp_pkg1.vh"

module neuron (
    input  signed [`DATA_W-1:0] in_data,
    input  signed [`DATA_W-1:0] weight,
    input  signed [`DATA_W-1:0] bias,
    output signed [`DATA_W-1:0] out_data
);

    wire signed [`DATA_W-1:0] mac_out;

    fixed_mac MAC (
        .in_data(in_data),
        .weight(weight),
        .bias(bias),
        .out_data(mac_out)
    );

    relu RELU (
        .in_data(mac_out),
        .out_data(out_data)
    );

endmodule
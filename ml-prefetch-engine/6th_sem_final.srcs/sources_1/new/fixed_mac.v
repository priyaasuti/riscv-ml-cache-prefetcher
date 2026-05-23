`include "mlp_pkg1.vh"

module fixed_mac (
    input  signed [`DATA_W-1:0] in_data,
    input  signed [`DATA_W-1:0] weight,
    input  signed [`DATA_W-1:0] bias,
    output signed [`DATA_W-1:0] out_data
);

    wire signed [(2*`DATA_W)-1:0] mult_full;
    wire signed [`DATA_W-1:0] mult_scaled;

    assign mult_full   = in_data * weight;
    assign mult_scaled = mult_full >>> `FRAC_W;

    assign out_data = mult_scaled + bias;

endmodule
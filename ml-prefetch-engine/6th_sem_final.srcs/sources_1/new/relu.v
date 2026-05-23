`include "mlp_pkg1.vh"

module relu (
    input  signed [`DATA_W-1:0] in_data,
    output signed [`DATA_W-1:0] out_data
);

    assign out_data = (in_data > 0) ? in_data : 0;

endmodule
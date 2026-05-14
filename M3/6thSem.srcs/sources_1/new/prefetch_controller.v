module prefetch_controller (
    input clk,
    input reset,

    input        ml_pf_req,
    input [31:0] ml_pf_addr,

    input        cache_busy,

    output reg        cache_pf_req,
    output reg [31:0] cache_pf_addr
);

    always @(posedge clk or posedge reset) begin
    if (reset) begin
        cache_pf_req  <= 1'b0;
        cache_pf_addr <= 32'd0;
    end else begin

        // one-cycle pulse
        cache_pf_req <= 1'b0;

        // allow prefetch whenever ML requests
        if (ml_pf_req) begin
            cache_pf_req  <= 1'b1;
            cache_pf_addr <= ml_pf_addr;
        end
    end
end

endmodule
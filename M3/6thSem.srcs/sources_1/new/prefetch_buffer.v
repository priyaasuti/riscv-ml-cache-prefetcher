module prefetch_buffer (
    input        clk,
    input        reset,

    input        pf_req,
    input [31:0] pf_addr,

    input [31:0] cpu_addr,

    output reg        pf_hit,
    output reg [31:0] stored_pf_addr
);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            stored_pf_addr <= 32'd0;
            pf_hit <= 1'b0;
        end else begin
            if (pf_req) begin
                stored_pf_addr <= pf_addr;
            end

            if (cpu_addr == stored_pf_addr) begin
                pf_hit <= 1'b1;
            end else begin
                pf_hit <= 1'b0;
            end
        end
    end

endmodule
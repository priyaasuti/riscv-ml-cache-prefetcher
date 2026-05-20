module prefetch_filter (
    input        pf_req_in,
    input [31:0] pf_addr_in,
    input [31:0] current_addr,

    output       pf_req_out,
    output [31:0] pf_addr_out
);

    wire same_addr;
    wire aligned_addr;

    assign same_addr    = (pf_addr_in == current_addr);
    assign aligned_addr = (pf_addr_in[1:0] == 2'b00);

    assign pf_req_out  = pf_req_in & (~same_addr) & aligned_addr;
    assign pf_addr_out = pf_addr_in;

endmodule
// ============================================================
// data_memory.v  —  Synchronous write, combinational read
// ============================================================
module data_memory(
    input         clk,
    input         mem_read,
    input         mem_write,
    input  [31:0] addr,
    input  [31:0] write_data,
    output reg [31:0] read_data
);

reg [31:0] memory [0:255];

integer j;
initial begin
    for (j = 0; j < 256; j = j + 1)
        memory[j] = 32'd0;
end

always @(posedge clk) begin
    if (mem_write)
        memory[addr[9:2]] <= write_data;
end

always @(*) begin
    read_data = mem_read ? memory[addr[9:2]] : 32'd0;
end

endmodule

module prefetch_buffer (
    input        clk,
    input        reset,

    input        pf_req,
    input [31:0] pf_addr,

    input [31:0] cpu_addr,

    output wire       pf_hit,
    output reg [31:0] stored_pf_addr
);

    localparam DEPTH = 4;

    reg [31:0] fifo_addr [0:DEPTH-1];
    reg [2:0]  fifo_count;
    reg        pf_hit_r;
    integer    i, j;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fifo_count    <= 3'd0;
            stored_pf_addr<= 32'd0;
            pf_hit_r      <= 1'b0;
            for (i = 0; i < DEPTH; i = i + 1)
                fifo_addr[i] <= 32'd0;
        end else begin
            pf_hit_r <= 1'b0;

            if (pf_req && fifo_count < DEPTH) begin
                fifo_addr[fifo_count] <= pf_addr;
                fifo_count <= fifo_count + 3'd1;
            end

            if (fifo_count != 3'd0)
                stored_pf_addr <= fifo_addr[0];
            else
                stored_pf_addr <= 32'd0;

            for (i = 0; i < DEPTH; i = i + 1) begin
                if (i < fifo_count && fifo_addr[i] == cpu_addr && cpu_addr != 32'd0 && !pf_hit_r) begin
                    pf_hit_r <= 1'b1;
                    for (j = i; j < DEPTH-1; j = j + 1)
                        fifo_addr[j] <= fifo_addr[j+1];
                    fifo_addr[DEPTH-1] <= 32'd0;
                    if (fifo_count != 3'd0)
                        fifo_count <= fifo_count - 3'd1;
                end
            end
        end
    end

    assign pf_hit = pf_hit_r;

endmodule
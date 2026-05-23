`timescale 1ns/1ps

module tb_cache;

reg clk, rst;
always #5 clk = ~clk;

// DUT
datapath dut(.clk(clk), .rst(rst));

// Cache observation signals
wire        obs_valid = dut.dcache.obs_valid;
wire [31:0] obs_addr  = dut.dcache.obs_addr;
wire        obs_hit   = dut.dcache.obs_hit;
wire [31:0] obs_pc    = dut.dcache.obs_pc;

// CSV
integer log_fd;
integer cycle_count;

initial begin
    $timeformat(-9, 0, "ns", 10);

    clk = 0;
    rst = 1;
    cycle_count = 0;

    // Open file
    log_fd = $fopen("C:/Users/LENOVO/OneDrive/Desktop/Notes and projects/VIth sem projects/EL/riscv _latest/riscv_cache/mem_access_log.csv", "w");
    if (log_fd == 0) begin
        $display("ERROR: could not open log file");
        $finish;
    end

    $fwrite(log_fd, "cycle,pc,addr,hit\n");

    // Reset
    repeat (2) @(posedge clk);
    rst = 0;

    // Run simulation
    repeat (500) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;

        if (obs_valid) begin
            $fwrite(log_fd, "%0d,%08d,%08d,%0d\n",
                cycle_count,
                obs_pc,
                obs_addr,
                obs_hit ? 1 : 0
            );
        end
    end

    $fclose(log_fd);
    $display("Log written to mem_access_log.csv");

    $finish;
end

endmodule
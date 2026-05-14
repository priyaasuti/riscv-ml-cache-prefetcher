`timescale 1ns / 1ps

module mlp_engine_m4 (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [63:0] delta_window,

    output reg         busy,
    output reg         done,
    output reg signed [7:0] mlp_out
);

`include "weights_rom_functions.vh"

localparam S_IDLE = 3'd0;
localparam S_FC1  = 3'd1;
localparam S_FC2  = 3'd2;
localparam S_FC3  = 3'd3;
localparam S_DONE = 3'd4;

localparam FRAC_SHIFT = 8;

reg [2:0] state;
reg [6:0] row;
reg [6:0] col;

reg signed [31:0] acc;
reg signed [31:0] mac_sum;

reg signed [7:0] h1 [0:63];
reg signed [7:0] h2 [0:31];

integer i;

function signed [7:0] clamp_i8;
    input signed [31:0] x;
    begin
        if (x > 32'sd127)
            clamp_i8 = 8'sd127;
        else if (x < -32'sd128)
            clamp_i8 = -8'sd128;
        else
            clamp_i8 = x[7:0];
    end
endfunction

function signed [7:0] relu_i8;
    input signed [7:0] x;
    begin
        relu_i8 = (x < 0) ? 8'sd0 : x;
    end
endfunction

function signed [7:0] get_input;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: get_input = delta_window[7:0];
            3'd1: get_input = delta_window[15:8];
            3'd2: get_input = delta_window[23:16];
            3'd3: get_input = delta_window[31:24];
            3'd4: get_input = delta_window[39:32];
            3'd5: get_input = delta_window[47:40];
            3'd6: get_input = delta_window[55:48];
            3'd7: get_input = delta_window[63:56];
            default: get_input = 8'sd0;
        endcase
    end
endfunction

always @(posedge clk or posedge reset) begin
    if (reset) begin
        state   <= S_IDLE;
        row     <= 7'd0;
        col     <= 7'd0;
        acc     <= 32'sd0;
        mac_sum <= 32'sd0;
        busy    <= 1'b0;
        done    <= 1'b0;
        mlp_out <= 8'sd0;

        for (i = 0; i < 64; i = i + 1)
            h1[i] <= 8'sd0;

        for (i = 0; i < 32; i = i + 1)
            h2[i] <= 8'sd0;

    end else begin
        done <= 1'b0;

        case (state)

            S_IDLE: begin
                busy <= 1'b0;
                row  <= 7'd0;
                col  <= 7'd0;
                acc  <= 32'sd0;

                if (start) begin
                    busy  <= 1'b1;
                    state <= S_FC1;
                end
            end

            S_FC1: begin
                mac_sum = acc +
                    ($signed(get_input(col[2:0])) *
                     $signed(fc1_weight((row * 8) + col)));

                if (col == 7'd7) begin
                    h1[row] <= relu_i8(
                        clamp_i8((mac_sum >>> FRAC_SHIFT) +
                        $signed(fc1_bias(row[5:0])))
                    );

                    acc <= 32'sd0;
                    col <= 7'd0;

                    if (row == 7'd63) begin
                        row   <= 7'd0;
                        state <= S_FC2;
                    end else begin
                        row <= row + 7'd1;
                    end
                end else begin
                    acc <= mac_sum;
                    col <= col + 7'd1;
                end
            end

            S_FC2: begin
                mac_sum = acc +
                    ($signed(h1[col]) *
                     $signed(fc2_weight((row * 64) + col)));

                if (col == 7'd63) begin
                    h2[row] <= relu_i8(
                        clamp_i8((mac_sum >>> FRAC_SHIFT) +
                        $signed(fc2_bias(row[4:0])))
                    );

                    acc <= 32'sd0;
                    col <= 7'd0;

                    if (row == 7'd31) begin
                        row   <= 7'd0;
                        state <= S_FC3;
                    end else begin
                        row <= row + 7'd1;
                    end
                end else begin
                    acc <= mac_sum;
                    col <= col + 7'd1;
                end
            end

            S_FC3: begin
                mac_sum = acc +
                    ($signed(h2[col[4:0]]) *
                     $signed(fc3_weight(col[4:0])));

                if (col == 7'd31) begin
                    mlp_out <= clamp_i8(mac_sum >>> FRAC_SHIFT);

                    acc   <= 32'sd0;
                    col   <= 7'd0;
                    row   <= 7'd0;
                    state <= S_DONE;
                end else begin
                    acc <= mac_sum;
                    col <= col + 7'd1;
                end
            end

            S_DONE: begin
                busy  <= 1'b0;
                done  <= 1'b1;
                state <= S_IDLE;
            end

            default: begin
                state <= S_IDLE;
                busy  <= 1'b0;
                done  <= 1'b0;
            end

        endcase
    end
end

endmodule
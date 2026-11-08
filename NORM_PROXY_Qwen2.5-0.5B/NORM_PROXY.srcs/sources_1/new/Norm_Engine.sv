`timescale 1ns/1ps
// Generic reducer: synchronous active-high reset. Start precedes data.
// Keep block_id stable through last. Start restarts a block and accepts no data.
// 32 INT8 lanes: maximum word_sum=524288; 32 bits permit 8191 worst-case
// words per block. Caller must bound length; no saturation or approximation.
module Norm_Engine #(
    parameter DATA_W=8, LANES=32, BLOCK_ID_W=8, NORM_W=32
)(
    input logic clk, rst, start,
    input logic signed [LANES*DATA_W-1:0] data_in,
    input logic data_valid, data_last,
    input logic [BLOCK_ID_W-1:0] block_id,
    output logic [NORM_W-1:0] norm_sq,
    output logic norm_valid,
    output logic [BLOCK_ID_W-1:0] norm_block_id,
    output logic busy, done
);
    logic [NORM_W-1:0] accumulator, word_sum;
    logic signed [DATA_W-1:0] lane_value;
    logic signed [2*DATA_W-1:0] lane_square;
    integer i;
    always_comb begin
        word_sum = '0;
        lane_value = '0;
        lane_square = '0;
        for (i=0; i<LANES; i=i+1) begin
            lane_value = $signed(data_in[i*DATA_W +: DATA_W]);
            // Signed multiply isolated from unsigned addition context.
            lane_square = lane_value * lane_value;
            word_sum = word_sum + $unsigned(lane_square);
        end
    end
    always_ff @(posedge clk) begin
        if (rst) begin
            accumulator <= '0;
            norm_sq <= '0;
            norm_block_id <= '0;
            norm_valid <= 0;
            busy <= 0;
            done <= 0;
        end else begin
            norm_valid <= 0;
            done <= 0;
            if (start) begin
                accumulator <= '0;
                busy <= 1;
            end else if (data_valid && busy) begin
                if (data_last) begin
                    // Include last word in the registered result.
                    norm_sq <= accumulator + word_sum;
                    norm_block_id <= block_id;
                    norm_valid <= 1;
                    done <= 1;
                    accumulator <= '0;
                    busy <= 0;
                end else accumulator <= accumulator + word_sum;
            end
        end
    end
endmodule

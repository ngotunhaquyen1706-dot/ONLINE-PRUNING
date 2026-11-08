`timescale 1ns/1ps
// One-cycle synchronous read, read-first on same-address write/read.
// Reset invalidates entries without clearing payload, allowing RAM inference.
module Norm_RAM #(parameter ID_W=8, NORM_W=32)(
 input logic clk,rst,wr_valid,
 input logic [ID_W-1:0] wr_id,
 input logic [NORM_W-1:0] wr_norm,
 input logic rd_en,
 input logic [ID_W-1:0] rd_id,
 output logic [NORM_W-1:0] rd_norm,
 output logic rd_valid,rd_present
);
 logic [NORM_W-1:0] mem [0:(1<<ID_W)-1];
 logic [(1<<ID_W)-1:0] present;
 always_ff @(posedge clk) begin
  if(rst) begin present<='0; rd_valid<=0; rd_present<=0; rd_norm<=0; end
  else begin
   rd_valid<=rd_en;
   if(wr_valid) begin mem[wr_id]<=wr_norm; present[wr_id]<=1; end
   if(rd_en) begin
    rd_present<=present[rd_id];
    rd_norm<=present[rd_id] ? mem[rd_id] : '0;
   end
  end
 end
endmodule

`timescale 1ns/1ps
// One-entry elastic job register, preserving FIFO/request order.
module Block_Scheduler #(parameter ID_W=8)(
 input logic clk,rst,in_valid,
 output logic in_ready,
 input logic [ID_W-1:0] in_q_id,in_k_id,
 output logic job_valid,
 input logic job_ready,
 output logic [ID_W-1:0] job_q_id,job_k_id
);
 assign in_ready=!rst && (!job_valid || job_ready);
 always_ff @(posedge clk) begin
  if(rst) begin job_valid<=0;job_q_id<=0;job_k_id<=0;end
  else if(in_ready) begin
   job_valid<=in_valid;
   if(in_valid) begin job_q_id<=in_q_id;job_k_id<=in_k_id;end
  end
 end
endmodule

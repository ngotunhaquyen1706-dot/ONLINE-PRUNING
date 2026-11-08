`timescale 1ns/1ps
// FWFT head; full FIFO accepts replacement when a pop occurs on same edge.
module Block_FIFO #(parameter ID_W=8,DEPTH=8,
 parameter PTR_W=(DEPTH<=1?1:$clog2(DEPTH)),COUNT_W=$clog2(DEPTH+1))(
 input logic clk,rst,in_valid,
 output logic in_ready,
 input logic [ID_W-1:0] in_q_id,in_k_id,
 output logic out_valid,
 input logic out_ready,
 output logic [ID_W-1:0] out_q_id,out_k_id,
 output logic [COUNT_W-1:0] count
);
 logic [2*ID_W-1:0] mem[0:DEPTH-1];
 logic [PTR_W-1:0] wp,rp;
 wire pop=out_valid && out_ready;
 wire push=in_valid && in_ready;
 assign out_valid=!rst && count!=0;
 assign in_ready=!rst && ((count<DEPTH) || pop);
 assign {out_q_id,out_k_id}=out_valid?mem[rp]:'0;
 always_ff @(posedge clk) begin
  if(rst) begin count<=0;wp<=0;rp<=0;end
  else begin
   if(push) begin mem[wp]<={in_q_id,in_k_id};wp<=(wp==DEPTH-1)?0:wp+1'b1;end
   if(pop) rp<=(rp==DEPTH-1)?0:rp+1'b1;
   case({push,pop})
    2'b10:count<=count+1'b1;
    2'b01:count<=count-1'b1;
    default:count<=count;
   endcase
  end
 end
endmodule

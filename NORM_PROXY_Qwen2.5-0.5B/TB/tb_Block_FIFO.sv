`timescale 1ns/1ps
module tb_Block_FIFO;
 logic clk=0,rst=1,in_valid=0,out_ready=0;
 logic[7:0] in_q_id=0,in_k_id=0;wire in_ready,out_valid;
 wire[7:0] out_q_id,out_k_id;wire[1:0] count;
 logic[15:0] model[$];logic[15:0] discarded;
 integer total=0;
 // Depth 3 deliberately exercises non-power-of-two pointer wrap.
 Block_FIFO #(.DEPTH(3)) dut(.*);always #5 clk=~clk;
 task automatic check_head;
  if(out_valid!==(model.size()!=0) || count!==model.size()) $fatal(1,"FIFO occupancy FAIL");
  if(model.size()!=0 && {out_q_id,out_k_id}!==model[0])
   $fatal(1,"FIFO Expected=%h Actual=%h FAIL",model[0],{out_q_id,out_k_id});
 endtask
 task automatic step(input bit reset_i,push_i,pop_i,input integer value);
  bit push,pop,ready_expected;
  @(negedge clk);rst=reset_i;in_valid=push_i;out_ready=pop_i;
  in_q_id=value;in_k_id=255-value;#1;
  if(!reset_i) begin
   check_head();ready_expected=(model.size()<3)||(pop_i && model.size()!=0);
   if(in_ready!==ready_expected) $fatal(1,"FIFO ready FAIL");
   pop=pop_i && model.size()!=0;push=push_i && ready_expected;
   if(pop) discarded=model.pop_front();
   if(push) model.push_back({in_q_id,in_k_id});
  end else model.delete();
  @(posedge clk);#1;
  if(reset_i) begin if(count || out_valid || in_ready) $fatal(1,"FIFO reset FAIL");end
  else check_head();
  total++;$display("FIFO check=%0d Expected count=%0d Actual=%0d PASS",total,model.size(),count);
 endtask
 initial begin
  step(1,0,0,0);step(0,0,1,0);step(0,1,0,1);step(0,1,0,2);step(0,1,0,3);
  step(0,1,0,4);step(0,1,1,5);step(0,0,0,0);
  step(0,0,1,0);step(0,0,1,0);step(0,0,1,0);step(0,0,1,0);
  step(0,1,1,6);step(0,0,1,0);
  for(integer i=0;i<30;i++) step(0,1,1,i);
  step(1,1,1,99);step(0,0,1,0);
  $display("Total=%0d Passed=%0d Failed=0 ALL TESTS PASS",total,total);$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule

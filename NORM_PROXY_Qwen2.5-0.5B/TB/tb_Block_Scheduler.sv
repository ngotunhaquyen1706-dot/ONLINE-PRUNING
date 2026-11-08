`timescale 1ns/1ps
module tb_Block_Scheduler;
 logic clk=0,rst=1,in_valid=0,job_ready=0;
 logic[7:0] in_q_id=0,in_k_id=0;
 wire in_ready,job_valid;wire[7:0] job_q_id,job_k_id;
 logic[15:0] model[$];logic[15:0] removed;
 integer total=0,sent=0,received=0;
 Block_Scheduler dut(.*);always #5 clk=~clk;
 task automatic step(input bit v,r,input integer id);
  bit take_in,take_out;
  @(negedge clk);rst=0;in_valid=v;job_ready=r;in_q_id=id;in_k_id=255-id;#1;
  if(job_valid!==(model.size()!=0)) $fatal(1,"scheduler valid FAIL");
  if(in_ready!==((model.size()==0)||r)) $fatal(1,"scheduler backpressure FAIL");
  if(job_valid && {job_q_id,job_k_id}!==model[0]) $fatal(1,"order/loss FAIL");
  take_in=v && in_ready;take_out=job_valid && r;
  if(take_out) begin removed=model.pop_front();received++;end
  if(take_in) begin model.push_back({in_q_id,in_k_id});sent++;end
  @(posedge clk);#1;
  if(job_valid!==(model.size()!=0)) $fatal(1,"registered valid FAIL");
  if(job_valid && {job_q_id,job_k_id}!==model[0]) $fatal(1,"Expected=%h Actual=%h FAIL",model[0],{job_q_id,job_k_id});
  total++;$display("Scheduler cycle=%0d Expected pending=%0d Actual valid=%b PASS",total,model.size(),job_valid);
 endtask
 initial begin
  @(posedge clk);#1;if(job_valid) $fatal(1,"reset FAIL");
  step(0,1,0);step(1,0,1);step(1,0,2);step(0,0,0);
  step(1,1,3);step(1,1,4);step(0,1,0);step(0,1,0);
  for(integer i=0;i<40;i++) step((i%5)!=0,(i%4)!=0,i+10);
  step(0,1,0);step(0,1,0);
  if(sent!=received || model.size()!=0) $fatal(1,"lost/duplicated job FAIL");
  step(1,0,255);
  @(negedge clk);rst=1;
  @(posedge clk);#1;if(job_valid) $fatal(1,"pending reset FAIL");
  total++;$display("Total=%0d Passed=%0d Failed=0 ALL TESTS PASS",total,total);$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule

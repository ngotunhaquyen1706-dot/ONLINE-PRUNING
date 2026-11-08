`timescale 1ns/1ps
module tb_Threshold_Comparator;
 logic clk=0,rst=1,valid=0;logic[63:0] proxy_score=0,threshold_T=0;
 logic[7:0] q_id=0,k_id=0;wire keep,out_valid;wire[7:0] out_q_id,out_k_id;
 integer total=0;
 Threshold_Comparator dut(.*);always #5 clk=~clk;
 task automatic step(input bit v,input logic[63:0] p,t,input bit expected);
  @(negedge clk);rst=0;valid=v;proxy_score=p;threshold_T=t;q_id=total;k_id=255-total;
  @(posedge clk);#1;
  if(out_valid!==v || (v && (keep!==expected || out_q_id!==q_id || out_k_id!==k_id)))
   $fatal(1,"Comparator P=%0d T=%0d Expected=%b Actual=%b FAIL",p,t,expected,keep);
  total++;$display("Comparator P=%0d T=%0d Expected=%b Actual=%b valid=%b PASS",p,t,expected,keep,v);
 endtask
 initial begin
  @(posedge clk);#1;if(out_valid || keep) $fatal(1,"reset FAIL");
  step(1,99,100,0);step(1,100,100,1);step(1,101,100,1);
  step(1,0,0,1);step(1,0,1,0);step(0,7,8,0);
  step(1,64'hffffffffffffffff,64'hffffffffffffffff,1);
  step(1,64'h8000000000000000,64'h7fffffffffffffff,1);
  step(1,64'h7fffffffffffffff,64'h8000000000000000,0);
  @(negedge clk);rst=1;valid=1;
  @(posedge clk);#1;if(out_valid || keep) $fatal(1,"reset FAIL");
  total++;$display("Total=%0d Passed=%0d Failed=0 ALL TESTS PASS",total,total);$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule

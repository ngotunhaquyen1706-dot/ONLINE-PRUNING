`timescale 1ns/1ps
module tb_Proxy_Engine;
 logic clk=0,rst=1,valid=0;
 logic[31:0] q_norm_sq=0,k_norm_sq=0;
 logic[7:0] q_id=0,k_id=0;
 wire[63:0] proxy_score;wire[7:0] out_q_id,out_k_id;wire out_valid;
 integer total=0; logic[63:0] held=0;
 Proxy_Engine dut(.*);always #5 clk=~clk;
 task automatic step(input bit v,input logic[31:0] a,b,input integer qi,ki);
  // Shift/add reference independent of the DUT multiplication expression.
  logic[63:0] expected; expected=0;
  for(integer i=0;i<32;i++) if(b[i]) expected+=({32'b0,a}<<i);
  @(negedge clk);rst=0;valid=v;q_norm_sq=a;k_norm_sq=b;q_id=qi;k_id=ki;
  @(posedge clk);#1;
  if(out_valid!==v) $fatal(1,"valid timing FAIL");
  if(v) begin
   if(proxy_score!==expected || out_q_id!==q_id || out_k_id!==k_id)
    $fatal(1,"Expected=%0d Actual=%0d IDs=%0d,%0d FAIL",expected,proxy_score,out_q_id,out_k_id);
   held=expected;
  end else if(proxy_score!==held) $fatal(1,"invalid hold FAIL");
  total++;$display("Proxy Expected=%0d Actual=%0d valid=%b PASS",v?expected:held,proxy_score,v);
 endtask
 initial begin
  @(posedge clk);#1;if(out_valid || proxy_score) $fatal(1,"reset FAIL");
  step(1,12,34,0,1);step(1,0,123,2,3);step(1,123,0,4,5);
  step(1,1,1,255,255);step(0,99,99,8,9);step(1,32'd2097152,32'd4294443008,11,12);
  step(1,32'hffffffff,32'hffffffff,254,0);step(1,32'h80000000,2,42,99);
  step(0,0,0,0,0);
  @(negedge clk);rst=1;valid=1;
  @(posedge clk);#1;if(out_valid || proxy_score) $fatal(1,"reset FAIL");
  total++;$display("Total=%0d Passed=%0d Failed=0 ALL TESTS PASS",total,total);$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule

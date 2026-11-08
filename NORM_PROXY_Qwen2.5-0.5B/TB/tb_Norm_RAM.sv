`timescale 1ns/1ps
module tb_Norm_RAM;
 logic clk=0,rst=1,wr_valid=0,rd_en=0;
 logic [7:0] wr_id=0,rd_id=0;
 logic [31:0] wr_norm=0;
 wire [31:0] rd_norm; wire rd_valid,rd_present;
 longint unsigned model[256]; bit present[256]; integer total=0;
 logic[31:0] held_norm=0;
 Norm_RAM dut(.*); always #5 clk=~clk;
 task automatic step(input bit reset_i,w,r,input integer wi,ri,input logic[31:0] value);
  bit ep; logic[31:0] ev;
  @(negedge clk); rst=reset_i;wr_valid=w;rd_en=r;wr_id=wi;rd_id=ri;wr_norm=value;
  ep=present[ri]; ev=r?(ep?model[ri]:0):held_norm;
  @(posedge clk); #1;
  if(reset_i) begin
   for(integer i=0;i<256;i++) begin present[i]=0;model[i]=0;end
   if(rd_valid || rd_present || rd_norm) $fatal(1,"reset FAIL");
   held_norm=0;
  end else begin
   if(rd_valid!==r) $fatal(1,"read latency FAIL");
   if(r && (rd_present!==ep || rd_norm!==ev))
    $fatal(1,"RAM ID=%0d Expected=%0d Actual=%0d",ri,ev,rd_norm);
   if(!r && rd_norm!==held_norm) $fatal(1,"idle hold FAIL");
   if(r) held_norm=ev;
   if(w) begin present[wi]=1;model[wi]=value;end
  end
  total++; $display("RAM check %0d Expected=%0d Actual=%0d PASS",total,reset_i?0:ev,rd_norm);
 endtask
 initial begin
  step(1,0,0,0,0,0); step(0,0,1,0,0,0);
  step(0,1,0,0,0,123); step(0,0,1,0,0,0);
  step(0,1,1,255,0,32'hffffffff);step(0,0,1,0,255,0);
  step(0,1,1,255,255,456);step(0,0,1,0,255,0);
  for(integer i=1;i<12;i++) step(0,1,1,i,i-1,i*777);
  step(0,0,0,0,0,0);step(1,1,1,0,255,5);step(0,0,1,0,255,0);
  $display("Total=%0d Passed=%0d Failed=0 ALL TESTS PASS",total,total);$finish;
 end
 initial begin #10000; $fatal(1,"timeout");end
endmodule

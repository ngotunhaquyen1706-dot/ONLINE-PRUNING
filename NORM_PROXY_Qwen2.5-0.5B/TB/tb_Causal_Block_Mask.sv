`timescale 1ns/1ps
module tb_Causal_Block_Mask;
 logic rst=0,in_valid=0;
 logic [7:0] q_block_id=0,k_block_id=0;
 wire [7:0] out_q_block_id,out_k_block_id;
 wire out_valid,causal_prune;
 integer tests=0,passed=0,failed=0;
 logic [31:0] seed=32'hca051234;
 Causal_Block_Mask dut(.*);
 task automatic check_pair(input integer q,k,input bit v,r);
  bit prune_expected,valid_expected,ok;
  q_block_id=q;k_block_id=k;in_valid=v;rst=r;#5;
  prune_expected=v && !r && (k>q);
  valid_expected=v && !r && (k<=q);
  ok=(causal_prune===prune_expected && out_valid===valid_expected &&
      out_q_block_id===q[7:0] && out_k_block_id===k[7:0]);
  tests++;if(ok) passed++;else failed++;
  $display("%0d | %0d | %s | %s | %s valid expected=%b actual=%b rst=%b in_valid=%b",
   q,k,prune_expected?"PRUNE":"KEEP",causal_prune?"PRUNE":"KEEP",ok?"PASS":"FAIL",
   valid_expected,out_valid,r,v);
 endtask
 initial begin
  $display("============================================================");
  $display("CAUSAL BLOCK MASK TEST");
  $display("Q_ID | K_ID | Expected | Actual | Status");
  for(integer q=0;q<4;q++) for(integer k=0;k<4;k++) check_pair(q,k,1,0);
  check_pair(0,0,1,0);check_pair(0,255,1,0);
  check_pair(255,0,1,0);check_pair(255,255,1,0);
  for(integer i=0;i<256;i++) begin
   seed=seed*32'd1664525+32'd1013904223;
   check_pair(seed[7:0],seed[23:16],1,0);
  end
  check_pair(0,255,0,0);check_pair(255,0,0,0);
  check_pair(0,255,1,1);check_pair(255,0,1,1);
  check_pair(0,0,0,1);check_pair(0,0,1,0);
  $display("Total tests : %0d Passed : %0d Failed : %0d",tests,passed,failed);
  if(failed) $fatal(1,"CAUSAL MASK TEST: FAIL");
  $display("CAUSAL MASK TEST: PASS; Total=%0d Passed=%0d Failed=0 ALL TESTS PASS",tests,passed);
  $finish;
 end
endmodule

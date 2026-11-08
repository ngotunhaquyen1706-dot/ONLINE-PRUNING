`timescale 1ns/1ps
module tb_Norm_Base_Top;
 logic clk=0,rst=1,q_start=0,k_start=0;
 logic signed[255:0] q_data=0,k_data=0;
 logic q_valid=0,q_last=0,k_valid=0,k_last=0;
 logic[7:0] q_block_id=0,k_block_id=0;
 wire q_busy,k_busy,q_done,k_done;
 logic pair_valid=0;wire pair_ready;
 logic[7:0] pair_q_id=0,pair_k_id=0;
 logic[63:0] threshold_T=0;
 wire decision_valid,decision_keep,pair_error;
 wire[7:0] decision_q_id,decision_k_id;
 wire[31:0] decision_q_norm,decision_k_norm;
 wire[63:0] decision_score,decision_threshold;
 wire job_valid;logic job_ready=0;wire[7:0] job_q_id,job_k_id;
 Norm_Base_Top #(.FIFO_DEPTH(2)) dut(.*);always #5 clk=~clk;
 longint unsigned golden_Q_norm[256],golden_K_norm[256];
 logic[63:0] golden_proxy[4][4];bit golden_keep[4][4];
 logic[15:0] expected_decisions[$],expected_jobs[$];logic[63:0] expected_thresholds[$];
 logic[15:0] pair_item,job_item;logic[63:0] t_item,p_item;
 integer qi,ki,decisions=0,actual_keep=0,actual_prune=0,correct=0,wrong=0,jobs=0;
 integer expected_keep=0,expected_prune=0,total_pairs=0;
 integer all_pairs=0,all_keep=0,all_prune=0,all_correct=0,all_jobs=0,cases_passed=0;
 integer causal_count=0,norm_count=0,all_causal=0,all_norm=0,proxy_inputs=0,proxy_outputs=0;
 integer errors=0,full_stalls=0;bit expect_error=0,monitor=0,stall_held=0;
 logic[15:0] stalled_job;
 // Reference values are calculated from signed input samples, never DUT norms.
 function automatic integer sample(input bit is_k,input integer id,w,lane);
  if(!is_k) case(id)
   0:sample=0;1:sample=1;default:sample=((w*32+lane)%7)-3;
  endcase
  else case(id)
   0:sample=1;1:sample=-2;default:sample=(lane%2)?127:-128;
  endcase
 endfunction
 task automatic load_block(input integer id);
  longint signed vq,vk;longint unsigned nq,nk;
  nq=0;nk=0;
  @(negedge clk);q_start=1;k_start=1;q_block_id=id;k_block_id=id;
  for(integer w=0;w<32;w++) begin
   @(negedge clk);q_start=0;k_start=0;q_valid=1;k_valid=1;q_last=(w==31);k_last=(w==31);
   for(integer lane=0;lane<32;lane++) begin
    vq=sample(0,id,w,lane);vk=sample(1,id,w,lane);
    q_data[lane*8+:8]=vq[7:0];k_data[lane*8+:8]=vk[7:0];
    nq+=vq*vq;nk+=vk*vk;
   end
   @(posedge clk);#1;
   if(w==31 && (!q_done || !k_done)) $fatal(1,"norm completion FAIL");
   if(w%5==2 && w<31) begin
    @(negedge clk);q_valid=0;k_valid=0;q_last=1;k_last=1;
   end
  end
  golden_Q_norm[id]=nq;golden_K_norm[id]=nk;
  $display("Loaded ID=%0d Golden Q norm=%0d K norm=%0d",id,nq,nk);
  @(negedge clk);q_valid=0;k_valid=0;q_last=0;k_last=0;
  repeat(2) @(negedge clk);
 endtask
 task automatic send_pair(input integer q,k,input logic[63:0] t);
  @(negedge clk);pair_valid=1;pair_q_id=q;pair_k_id=k;threshold_T=t;
  @(posedge clk);while(!pair_ready) @(posedge clk);
  @(negedge clk);pair_valid=0;threshold_T=~t; // Threshold must be captured.
 endtask
 // Sample transfers before NBA; inspect new registered decision pulses after #1.
 always @(posedge clk) begin
  if(!rst && monitor) begin
   if(stall_held && (!job_valid || {job_q_id,job_k_id}!==stalled_job))
    $fatal(1,"scheduler output changed during backpressure");
   stall_held=job_valid && !job_ready;stalled_job={job_q_id,job_k_id};
   if(dut.fifo_count==2 && !dut.fifo_in_ready) full_stalls++;
   if(pair_valid && pair_ready && !expect_error) begin
    expected_decisions.push_back({pair_q_id,pair_k_id});
    expected_thresholds.push_back(threshold_T);
    if(pair_k_id<=pair_q_id && golden_Q_norm[pair_q_id]*golden_K_norm[pair_k_id]>=threshold_T)
     expected_jobs.push_back({pair_q_id,pair_k_id});
   end
   if(dut.u_proxy.valid) begin
    if(dut.u_proxy.k_id>dut.u_proxy.q_id) $fatal(1,"causal pair reached Proxy");
    proxy_inputs++;
   end
   if(dut.proxy_valid) proxy_outputs++;
   if(job_valid && job_ready) begin
    if(expected_jobs.size()==0) $fatal(1,"unexpected/duplicated job %0d,%0d",job_q_id,job_k_id);
    job_item=expected_jobs.pop_front();
    if({job_q_id,job_k_id}!==job_item) $fatal(1,"job order Expected=%h Actual=%h",job_item,{job_q_id,job_k_id});
    jobs++;
   end
   #1;
   if(pair_error) begin
    if(!expect_error) $fatal(1,"unexpected missing-norm error");
    errors++;
   end
   if(decision_valid) begin
    if(expected_decisions.size()==0) $fatal(1,"unexpected/duplicate decision");
    pair_item=expected_decisions.pop_front();t_item=expected_thresholds.pop_front();
    qi=pair_item[15:8];ki=pair_item[7:0];p_item=(ki>qi)?0:golden_Q_norm[qi]*golden_K_norm[ki];
    if(decision_q_id!==qi[7:0] || decision_k_id!==ki[7:0] ||
       decision_q_norm!==golden_Q_norm[qi][31:0] || decision_k_norm!==golden_K_norm[ki][31:0] ||
       decision_score!==p_item || decision_threshold!==t_item || decision_keep!==((ki<=qi) && (p_item>=t_item))) begin
     wrong++;
     $display("FAIL Q ID expected=%0d actual=%0d K ID expected=%0d actual=%0d",qi,decision_q_id,ki,decision_k_id);
     $display("Q norm Expected=%0d Actual=%0d K norm Expected=%0d Actual=%0d",golden_Q_norm[qi],decision_q_norm,golden_K_norm[ki],decision_k_norm);
     $display("Proxy Expected=%0d Actual=%0d threshold expected=%0d actual=%0d KEEP Expected=%b Actual=%b",p_item,decision_score,t_item,decision_threshold,(ki<=qi && p_item>=t_item),decision_keep);
     $fatal(1,"golden mismatch");
    end
    if(ki>qi) causal_count++;else if(!decision_keep) norm_count++;
    correct++;decisions++;if(decision_keep) actual_keep++;else actual_prune++;
    $display("Decision Q=%0d K=%0d Expected=%b Actual=%b PASS",qi,ki,(ki<=qi && p_item>=t_item),decision_keep);
   end
  end
 end
 task automatic run_case(input string name,input logic[63:0] t,input bit per_pair);
  causal_count=0;norm_count=0;proxy_inputs=0;proxy_outputs=0;
  decisions=0;actual_keep=0;actual_prune=0;correct=0;wrong=0;jobs=0;
  expected_keep=0;expected_prune=0;total_pairs=16;
  for(integer q=0;q<4;q++) for(integer k=0;k<4;k++) begin
   golden_proxy[q][k]=golden_Q_norm[q]*golden_K_norm[k];
   golden_keep[q][k]=(k<=q) && golden_proxy[q][k]>=(per_pair?golden_proxy[q][k]+(k==0?1:0):t);
   if(golden_keep[q][k]) expected_keep++;else expected_prune++;
  end
  job_ready=0;
  fork
   begin
    for(integer q=0;q<4;q++) for(integer k=0;k<4;k++)
     send_pair(q,k,per_pair?golden_proxy[q][k]+(k==0?1:0):t);
   end
   begin
    // Fill scheduler + depth-2 FIFO and force upstream request backpressure.
    repeat(100) @(negedge clk);
    for(integer c=0;c<120;c++) begin @(negedge clk);job_ready=(c%4!=0);end
    @(negedge clk);job_ready=1;
   end
  join
  wait(decisions==16 && expected_jobs.size()==0 && pair_ready && !job_valid);
  repeat(4) @(negedge clk);
  if(actual_keep!=expected_keep || actual_prune!=expected_prune || jobs!=expected_keep || expected_decisions.size()!=0)
   $fatal(1,"case counts/lost jobs FAIL");
  $display("CASE %s Total block pairs=%0d Expected KEEP=%0d Actual KEEP=%0d Expected PRUNE=%0d Actual PRUNE=%0d Correct decisions=%0d Wrong decisions=%0d Decision accuracy=%0.2f%% Measured sparsity=%0.2f%% PASS",
   name,total_pairs,expected_keep,actual_keep,expected_prune,actual_prune,correct,wrong,100.0*correct/total_pairs,100.0*actual_prune/total_pairs);
  if(causal_count!=6 || proxy_inputs!=10 || proxy_outputs!=10 || actual_prune!=causal_count+norm_count)
   $fatal(1,"causal priority / Proxy bypass counts FAIL");
  $display("METRICS %s Total block pairs=%0d Causally pruned blocks=%0d Remaining candidate blocks=%0d Norm-based pruned blocks=%0d Final pruned blocks=%0d Final kept blocks=%0d Causal sparsity=%0.2f%% Final measured sparsity=%0.2f%% Proxy computations=%0d",
   name,total_pairs,causal_count,total_pairs-causal_count,norm_count,actual_prune,actual_keep,
   100.0*causal_count/total_pairs,100.0*actual_prune/total_pairs,proxy_inputs);
  all_causal+=causal_count;all_norm+=norm_count;
  all_pairs+=total_pairs;all_keep+=actual_keep;all_prune+=actual_prune;all_correct+=correct;all_jobs+=jobs;cases_passed++;
 endtask
 initial begin
  repeat(3) @(negedge clk);rst=0;monitor=1;
  for(integer i=0;i<4;i++) load_block(i);
  run_case("A all candidates KEEP",0,0);
  run_case("B all candidates PRUNE",64'hffffffffffffffff,0);
  run_case("C mixed with equality",64'd4194304,0);
  run_case("D per-request threshold boundaries",0,1);
  expect_error=1;send_pair(255,0,0);repeat(8) @(negedge clk);
  if(errors!=1 || decision_valid || job_valid) $fatal(1,"missing norm handling FAIL");
  // Reset must invalidate previously loaded RAM entries.
  @(negedge clk);rst=1;repeat(2) @(negedge clk);rst=0;
  send_pair(1,1,0);repeat(8) @(negedge clk);
  if(errors!=2 || job_valid || full_stalls==0) $fatal(1,"reset/backpressure coverage FAIL");
  $display("AGGREGATE Total block pairs=%0d Expected KEEP=%0d Actual KEEP=%0d Expected PRUNE=%0d Actual PRUNE=%0d Correct decisions=%0d Wrong decisions=0 Decision accuracy=%0.2f%% Measured sparsity=%0.2f%% Jobs=%0d Full-stall cycles=%0d",
   all_pairs,all_keep,all_keep,all_prune,all_prune,all_correct,100.0*all_correct/all_pairs,100.0*all_prune/all_pairs,all_jobs,full_stalls);
  $display("FINAL METRICS Total block pairs=%0d Causally pruned blocks=%0d Remaining candidate blocks=%0d Norm-based pruned blocks=%0d Final pruned blocks=%0d Final kept blocks=%0d Causal sparsity=%0.2f%% Norm pruning of candidates=%0.2f%% Final measured sparsity=%0.2f%%",
   all_pairs,all_causal,all_pairs-all_causal,all_norm,all_prune,all_keep,
   100.0*all_causal/all_pairs,100.0*all_norm/(all_pairs-all_causal),100.0*all_prune/all_pairs);
  $display("Total=%0d Passed=%0d Failed=0 ALL TESTS PASS",cases_passed+2,cases_passed+2);$finish;
 end
 initial begin #100000;$fatal(1,"integration timeout");end
endmodule

`timescale 1ns/1ps
// Standalone load-then-evaluate predictor. See AUDIT_AND_INTERFACE.md.
module Norm_Base_Top #(parameter ID_W=8,NORM_W=32,FIFO_DEPTH=8)(
 input logic clk,rst,
 input logic q_start,k_start,
 input logic signed [255:0] q_data,k_data,
 input logic q_valid,q_last,k_valid,k_last,
 input logic [ID_W-1:0] q_block_id,k_block_id,
 output logic q_busy,k_busy,q_done,k_done,
 input logic pair_valid,
 output logic pair_ready,
 input logic [ID_W-1:0] pair_q_id,pair_k_id,
 input logic [2*NORM_W-1:0] threshold_T,
 output logic decision_valid,decision_keep,pair_error,
 output logic [ID_W-1:0] decision_q_id,decision_k_id,
 output logic [NORM_W-1:0] decision_q_norm,decision_k_norm,
 output logic [2*NORM_W-1:0] decision_score,decision_threshold,
 output logic job_valid,
 input logic job_ready,
 output logic [ID_W-1:0] job_q_id,job_k_id
);
 typedef enum logic[2:0] {IDLE,READ_NORMS,WAIT_PROXY,WAIT_COMPARE,ENQUEUE} state_t;
 state_t state;
 logic [NORM_W-1:0] q_norm_sq,k_norm_sq,q_ram_norm,k_ram_norm;
 logic [ID_W-1:0] q_norm_id,k_norm_id;
 logic q_norm_valid,k_norm_valid,q_ram_valid,k_ram_valid,q_present,k_present;
 wire accept_pair=pair_valid && pair_ready;
 assign pair_ready=!rst && state==IDLE && !q_busy && !k_busy &&
                   !q_start && !k_start && !q_norm_valid && !k_norm_valid;
 Norm_Engine #(.BLOCK_ID_W(ID_W),.NORM_W(NORM_W)) u_q_norm(
  .clk(clk),.rst(rst),.start(q_start && state==IDLE),.data_in(q_data),
  .data_valid(q_valid),.data_last(q_last),.block_id(q_block_id),
  .norm_sq(q_norm_sq),.norm_valid(q_norm_valid),.norm_block_id(q_norm_id),.busy(q_busy),.done(q_done));
 Norm_Engine #(.BLOCK_ID_W(ID_W),.NORM_W(NORM_W)) u_k_norm(
  .clk(clk),.rst(rst),.start(k_start && state==IDLE),.data_in(k_data),
  .data_valid(k_valid),.data_last(k_last),.block_id(k_block_id),
  .norm_sq(k_norm_sq),.norm_valid(k_norm_valid),.norm_block_id(k_norm_id),.busy(k_busy),.done(k_done));
 Norm_RAM #(.ID_W(ID_W),.NORM_W(NORM_W)) u_q_ram(
  .clk(clk),.rst(rst),.wr_valid(q_norm_valid),.wr_id(q_norm_id),.wr_norm(q_norm_sq),
  .rd_en(accept_pair),.rd_id(pair_q_id),.rd_norm(q_ram_norm),.rd_valid(q_ram_valid),.rd_present(q_present));
 Norm_RAM #(.ID_W(ID_W),.NORM_W(NORM_W)) u_k_ram(
  .clk(clk),.rst(rst),.wr_valid(k_norm_valid),.wr_id(k_norm_id),.wr_norm(k_norm_sq),
  .rd_en(accept_pair),.rd_id(pair_k_id),.rd_norm(k_ram_norm),.rd_valid(k_ram_valid),.rd_present(k_present));
 logic [2*NORM_W-1:0] proxy_score;
 logic [ID_W-1:0] proxy_q_id,proxy_k_id,keep_q_id,keep_k_id;
 logic proxy_valid,keep_valid,keep;
 wire norms_ready=state==READ_NORMS && q_ram_valid && k_ram_valid && q_present && k_present;
 logic mask_valid,causal_prune;
 logic [ID_W-1:0] mask_q_id,mask_k_id;
 Causal_Block_Mask #(.ID_W(ID_W)) u_causal_mask(
  .rst(rst),.in_valid(norms_ready),.q_block_id(decision_q_id),.k_block_id(decision_k_id),
  .out_q_block_id(mask_q_id),.out_k_block_id(mask_k_id),
  .out_valid(mask_valid),.causal_prune(causal_prune));
 Proxy_Engine #(.ID_W(ID_W),.NORM_W(NORM_W)) u_proxy(
  .clk(clk),.rst(rst),.valid(mask_valid),.q_norm_sq(q_ram_norm),.k_norm_sq(k_ram_norm),
  .q_id(mask_q_id),.k_id(mask_k_id),.proxy_score(proxy_score),
  .out_q_id(proxy_q_id),.out_k_id(proxy_k_id),.out_valid(proxy_valid));
 Threshold_Comparator #(.ID_W(ID_W),.SCORE_W(2*NORM_W)) u_compare(
  .clk(clk),.rst(rst),.valid(proxy_valid),.proxy_score(proxy_score),.threshold_T(decision_threshold),
  .q_id(proxy_q_id),.k_id(proxy_k_id),.keep(keep),.out_valid(keep_valid),
  .out_q_id(keep_q_id),.out_k_id(keep_k_id));
 logic fifo_in_ready,fifo_out_valid,fifo_out_ready;
 logic [ID_W-1:0] fifo_q_id,fifo_k_id;
 logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_count;
 Block_FIFO #(.ID_W(ID_W),.DEPTH(FIFO_DEPTH)) u_fifo(
  .clk(clk),.rst(rst),.in_valid(state==ENQUEUE),.in_ready(fifo_in_ready),
  .in_q_id(keep_q_id),.in_k_id(keep_k_id),.out_valid(fifo_out_valid),.out_ready(fifo_out_ready),
  .out_q_id(fifo_q_id),.out_k_id(fifo_k_id),.count(fifo_count));
 Block_Scheduler #(.ID_W(ID_W)) u_scheduler(
  .clk(clk),.rst(rst),.in_valid(fifo_out_valid),.in_ready(fifo_out_ready),
  .in_q_id(fifo_q_id),.in_k_id(fifo_k_id),.job_valid(job_valid),.job_ready(job_ready),
  .job_q_id(job_q_id),.job_k_id(job_k_id));
 always_ff @(posedge clk) begin
  if(rst) begin
   state<=IDLE;decision_valid<=0;decision_keep<=0;pair_error<=0;
   decision_q_id<=0;decision_k_id<=0;decision_q_norm<=0;decision_k_norm<=0;
   decision_score<=0;decision_threshold<=0;
  end else begin
   decision_valid<=0;pair_error<=0;
   case(state)
    IDLE: if(accept_pair) begin
     decision_q_id<=pair_q_id;decision_k_id<=pair_k_id;
     decision_threshold<=threshold_T;state<=READ_NORMS;
    end
    READ_NORMS: begin
     if(norms_ready) begin
      decision_q_norm<=q_ram_norm;decision_k_norm<=k_ram_norm;
      if(causal_prune) begin
       decision_score<=0;decision_keep<=0;decision_valid<=1;state<=IDLE;
      end else state<=WAIT_PROXY;
     end else begin pair_error<=1;state<=IDLE;end
    end
    WAIT_PROXY: if(proxy_valid) begin decision_score<=proxy_score;state<=WAIT_COMPARE;end
    WAIT_COMPARE: if(keep_valid) begin
     decision_valid<=1;decision_keep<=keep;state<=keep?ENQUEUE:IDLE;
    end
    ENQUEUE: if(fifo_in_ready) state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule

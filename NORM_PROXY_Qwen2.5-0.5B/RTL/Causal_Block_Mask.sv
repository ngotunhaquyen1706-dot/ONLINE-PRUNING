`timescale 1ns/1ps
// Combinational valid-only filter; no added pipeline stage or handshake.
module Causal_Block_Mask #(parameter ID_W=8)(
 input logic rst,in_valid,
 input logic [ID_W-1:0] q_block_id,k_block_id,
 output logic [ID_W-1:0] out_q_block_id,out_k_block_id,
 output logic out_valid,causal_prune
);
 assign out_q_block_id=q_block_id;
 assign out_k_block_id=k_block_id;
 assign causal_prune=!rst && in_valid && (k_block_id>q_block_id);
 assign out_valid=!rst && in_valid && (k_block_id<=q_block_id);
endmodule

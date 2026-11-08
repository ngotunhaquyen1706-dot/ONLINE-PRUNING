`timescale 1ns/1ps
// GUI-READY V4: no plusargs, no CMD, no separate Python runner.
// Uses real golden files created by Colab v4. Run in Vivado 2022.2 GUI.
// For a real Qwen case, change only CASE_DIR, Q_BLOCKS, K_BLOCKS, PAIR_COUNT
// to match its metadata.json. Four levels run automatically.
module tb_proxy_comparator_GUI_v4;
    // ==== USER CONFIG (edit when choosing a different Colab case) ====
    localparam string CASE_DIR =
        "D:/GEMM/NORM_PROXY/vivado_testdata/test_deterministic_64";
    localparam integer Q_BLOCKS = 2;
    localparam integer K_BLOCKS = 2;
    localparam integer PAIR_COUNT = 3;
    localparam string REPORT_DIR = "D:/GEMM/NORM_PROXY/verification";
    // ================================================================
    localparam integer MAX_BLOCKS = 128;
    localparam integer MAX_PAIRS = 8256;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic rst = 1'b1;
    logic input_valid = 1'b0;
    logic [7:0] qi=0,ki=0;
    logic [31:0] qn=0,kn=0;
    logic [63:0] threshold_T=0;
    wire [7:0] mq,mk,proxy_q,proxy_k,compare_q,compare_k;
    wire causal_valid,causal_prune;
    wire [63:0] score;
    wire proxy_valid,decision_valid,keep;
    Causal_Block_Mask #(.ID_W(8)) u_causal(
      .rst(rst),.in_valid(input_valid),.q_block_id(qi),.k_block_id(ki),
      .out_q_block_id(mq),.out_k_block_id(mk),.out_valid(causal_valid),
      .causal_prune(causal_prune));
    Proxy_Engine #(.NORM_W(32),.ID_W(8)) u_proxy(
      .clk(clk),.rst(rst),.valid(causal_valid),.q_norm_sq(qn),.k_norm_sq(kn),
      .q_id(mq),.k_id(mk),.proxy_score(score),
      .out_q_id(proxy_q),.out_k_id(proxy_k),.out_valid(proxy_valid));
    Threshold_Comparator #(.SCORE_W(64),.ID_W(8)) u_compare(
      .clk(clk),.rst(rst),.valid(proxy_valid),.proxy_score(score),
      .threshold_T(threshold_T),.q_id(proxy_q),.k_id(proxy_k),
      .keep(keep),.out_valid(decision_valid),.out_q_id(compare_q),.out_k_id(compare_k));

    logic [31:0] qnorm[0:MAX_BLOCKS-1], knorm[0:MAX_BLOCKS-1];
    logic [15:0] pairs[0:MAX_PAIRS-1];
    logic [63:0] golden_proxy[0:MAX_PAIRS-1];
    logic [63:0] pair_T[0:MAX_PAIRS-1];
    logic [0:0] golden_keep[0:MAX_PAIRS-1];
    logic [63:0] global_T[0:0];
    integer level,fh,checked=0,pruned=0;
    string report, f;

    task automatic must_exist(input string fname);
        integer fd;
        begin
            fd=$fopen(fname,"r");
            if (fd==0) $fatal(1,"DATA MISSING: %s",fname);
            $fclose(fd);
        end
    endtask

    task automatic read_shared_data;
        begin
            if(Q_BLOCKS<=0||Q_BLOCKS>MAX_BLOCKS||
               K_BLOCKS<=0||K_BLOCKS>MAX_BLOCKS||
               PAIR_COUNT<=0||PAIR_COUNT>MAX_PAIRS)
                $fatal(1,"Bad Q_BLOCKS/K_BLOCKS/PAIR_COUNT config");
            f={CASE_DIR,"/q_norm_sq.hex"};must_exist(f);$readmemh(f,qnorm,0,Q_BLOCKS-1);
            f={CASE_DIR,"/k_norm_sq.hex"};must_exist(f);$readmemh(f,knorm,0,K_BLOCKS-1);
            f={CASE_DIR,"/pairs.hex"};must_exist(f);$readmemh(f,pairs,0,PAIR_COUNT-1);
            f={CASE_DIR,"/expected_proxy.hex"};must_exist(f);$readmemh(f,golden_proxy,0,PAIR_COUNT-1);
        end
    endtask

    task automatic read_level(input integer sparse_level);
        integer i,a,b;
        begin
            level=sparse_level;
            f=$sformatf("%s/threshold_inputs_%0d.hex",CASE_DIR,level);
            must_exist(f);$readmemh(f,pair_T,0,PAIR_COUNT-1);
            f=$sformatf("%s/expected_mask_%0d.hex",CASE_DIR,level);
            must_exist(f);$readmemh(f,golden_keep,0,PAIR_COUNT-1);
            f=$sformatf("%s/threshold_%0d.hex",CASE_DIR,level);
            must_exist(f);$readmemh(f,global_T,0,0);
            for(i=0;i<PAIR_COUNT;i=i+1) begin
                a=int'(pairs[i][15:8]);b=int'(pairs[i][7:0]);
                if(a>=Q_BLOCKS||b>=K_BLOCKS||b>a)
                    $fatal(1,"Invalid causal pair index=%0d q=%0d k=%0d",i,a,b);
                if(golden_proxy[i] !== ({32'b0,qnorm[a]}*{32'b0,knorm[b]}))
                    $fatal(1,"BAD GOLDEN proxy pair=%0d",i);
                if(pair_T[i] !== (a==b?64'b0:global_T[0]))
                    $fatal(1,"BAD GOLDEN T pair=%0d",i);
                if(golden_keep[i][0] !== (golden_proxy[i]>=pair_T[i]))
                    $fatal(1,"BAD GOLDEN mask pair=%0d",i);
            end
            $display("[GOLDEN OK] sparsity=%0d%% T=%0d (0x%016h), pairs=%0d",
                      level,global_T[0],global_T[0],PAIR_COUNT);
        end
    endtask

    task automatic one_pair(input integer idx);
       integer a,b,wait_n;
       begin
          a=int'(pairs[idx][15:8]);
          b=int'(pairs[idx][7:0]);
          @(negedge clk);
          qi=a[7:0];ki=b[7:0];
          qn=qnorm[a];kn=knorm[b];threshold_T=pair_T[idx];
          input_valid=1;
          #1;
          if(!causal_valid || causal_prune) $fatal(1,"CAUSAL FAIL pair=%0d",idx);
          @(negedge clk);
          input_valid=0;
          wait_n=0;
          while(decision_valid !== 1'b1 && wait_n < 20) begin
             @(negedge clk);
             wait_n=wait_n+1;
          end
          if(!decision_valid) $fatal(1,"COMPARATOR TIMEOUT pair=%0d",idx);
          if({compare_q,compare_k} !== pairs[idx] ||
             score !== golden_proxy[idx] ||
             keep !== golden_keep[idx][0])
             $fatal(1,"RTL FAIL idx=%0d q=%0d k=%0d proxy=%h expected=%h T=%h keep=%b expected=%b",
                    idx,a,b,score,golden_proxy[idx],threshold_T,keep,golden_keep[idx][0]);
          $fwrite(fh,"%0d,%0d,%0d,%0d,%016h,%016h,%0d,PASS\n",
                  idx,level,a,b,score,threshold_T,keep);
          checked=checked+1;
          if(!keep) pruned=pruned+1;
       end
    endtask

    task automatic future_pair_test;
       integer t;
       begin
          if(Q_BLOCKS<2 || K_BLOCKS<2) return;
          @(negedge clk);
          qi=0;ki=1;qn=qnorm[0];kn=knorm[1];threshold_T=0;input_valid=1;
          #1;
          if(causal_valid!==1'b0 || causal_prune!==1'b1)
             $fatal(1,"CAUSAL FUTURE PAIR FAIL (0,1)");
          @(negedge clk);
          input_valid=0;
          for(t=0;t<4;t=t+1) begin
             @(negedge clk);
             if(proxy_valid || decision_valid)
                $fatal(1,"CAUSAL FUTURE PAIR incorrectly emitted");
          end
          $display("CAUSAL FUTURE (q=0,k=1) PASS");
       end
    endtask

    task automatic run_level(input integer sparse_level);
        integer i;
        begin
            @(negedge clk);
            rst=1;input_valid=0;checked=0;pruned=0;
            read_level(sparse_level);
            report=$sformatf("%s/gui_comparator_%0d.csv",REPORT_DIR,level);
            fh=$fopen(report,"w");
            if(!fh)$fatal(1,"Cannot write report: %s",report);
            $fwrite(fh,"pair_idx,level,q_id,k_id,proxy_hex,threshold_hex,keep,status\n");
            repeat(4)@(negedge clk);
            rst=0;
            for(i=0;i<PAIR_COUNT;i=i+1) one_pair(i);
            future_pair_test();
            if(checked!=PAIR_COUNT)$fatal(1,"Missing pair decision");
            $display("RTL_PASS LEVEL=%0d%% pairs=%0d kept=%0d pruned=%0d T=%0d",
                     level,checked,checked-pruned,pruned,global_T[0]);
            $fwrite(fh,"SUMMARY,%0d,,,,,,RTL_PASS\n",level);
            $fclose(fh);
        end
    endtask

    initial begin
        $display("=== VIVADO GUI V4: COMPARE ALL FOUR LEVELS ===");
        $display("Data: %s",CASE_DIR);
        read_shared_data();
        run_level(50);
        run_level(70);
        run_level(80);
        run_level(90);
        $display("=======================================================");
        $display("FINAL: ALL FOUR SPARSITY LEVELS PASS (50/70/80/90)");
        $display("Reports: %s/gui_comparator_*.csv",REPORT_DIR);
        $display("=======================================================");
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1,"GUI comparator simulation timeout");
    end
endmodule

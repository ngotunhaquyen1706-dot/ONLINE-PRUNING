`timescale 1ns/1ps
// =============================================================================
// REAL QWEN INT8 ACTIVATIONS -> Norm_Base_Top RTL -> ALL 4 THRESHOLDS
// Direct Vivado 2022.2 GUI Behavioral Simulation (NO CMD / NO PLUSARGS).
//
// Source: Qwen25_0p5B_Q4KM_LongBench_ThresholdT_RTL_Golden_v4.ipynb
// Input:  one complete vivado_testdata/test_narrativeqa_.../ directory.
//
// Only change CASE_DIR below to switch to a different REAL Qwen test.
// Counts QB/KB/Q beats/K beats/pairs AUTOMATICALLY from the HEX files.
// =============================================================================
module tb_Qwen_Real2048_AllT_GUI;

    localparam string CASE_DIR =
        "D:/GEMM/NORM_PROXY/vivado_testdata/test_narrativeqa_000_L00_H00_B0";
    localparam string REPORT_DIR = "D:/GEMM/NORM_PROXY/verification";
    // Change REPORT_TAG when switching samples to avoid overwriting old CSV files.
    localparam string REPORT_TAG = "real_narrativeqa_000_L00_H00_B0";

    localparam int MAX_BLOCKS = 64;       // ceil(2048/32)
    localparam int MAX_PAIRS = 2080;      // 64*65/2 causal block pairs
    localparam int MAX_BEATS = 8192;      // up to 128 x 256-bit words per block
    localparam int MAX_WAIT_CYCLES = 250;

    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1;
    logic q_start = 0, k_start = 0;
    logic signed [255:0] q_data = '0, k_data = '0;
    logic q_valid = 0, q_last = 0, k_valid = 0, k_last = 0;
    logic [7:0] q_block_id = 0, k_block_id = 0;
    wire q_busy, k_busy, q_done, k_done;
    logic pair_valid = 0;
    wire pair_ready;
    logic [7:0] pair_q_id = 0, pair_k_id = 0;
    logic [63:0] threshold_T = 0;
    wire decision_valid, decision_keep, pair_error;
    wire [7:0] decision_q_id, decision_k_id;
    wire [31:0] decision_q_norm, decision_k_norm;
    wire [63:0] decision_score, decision_threshold;
    wire job_valid;
    logic job_ready = 1;
    wire [7:0] job_q_id, job_k_id;

    // Use the actual source files already in Vivado Design Sources.
    Norm_Base_Top #(.ID_W(8), .NORM_W(32), .FIFO_DEPTH(8)) dut (
        .clk(clk), .rst(rst),
        .q_start(q_start), .k_start(k_start),
        .q_data(q_data), .k_data(k_data),
        .q_valid(q_valid), .q_last(q_last),
        .k_valid(k_valid), .k_last(k_last),
        .q_block_id(q_block_id), .k_block_id(k_block_id),
        .q_busy(q_busy), .k_busy(k_busy), .q_done(q_done), .k_done(k_done),
        .pair_valid(pair_valid), .pair_ready(pair_ready),
        .pair_q_id(pair_q_id), .pair_k_id(pair_k_id),
        .threshold_T(threshold_T),
        .decision_valid(decision_valid), .decision_keep(decision_keep),
        .pair_error(pair_error),
        .decision_q_id(decision_q_id), .decision_k_id(decision_k_id),
        .decision_q_norm(decision_q_norm), .decision_k_norm(decision_k_norm),
        .decision_score(decision_score), .decision_threshold(decision_threshold),
        .job_valid(job_valid), .job_ready(job_ready),
        .job_q_id(job_q_id), .job_k_id(job_k_id)
    );

    // Restrict array sizes to REAL 2048-token Qwen cases; do not add arrays
    // to Vivado waveform (they exceed its display limit). View DUT signals.
    logic [255:0] q_words [0:MAX_BEATS-1];
    logic [255:0] k_words [0:MAX_BEATS-1];
    logic [31:0] golden_q_norm [0:MAX_BLOCKS-1];
    logic [31:0] golden_k_norm [0:MAX_BLOCKS-1];
    logic [15:0] golden_pairs [0:MAX_PAIRS-1];
    logic [63:0] golden_proxy [0:MAX_PAIRS-1];
    logic [63:0] golden_threshold_input [0:MAX_PAIRS-1];
    logic golden_keep [0:MAX_PAIRS-1];
    logic [63:0] global_T [0:0];
    logic [15:0] expected_jobs [0:MAX_PAIRS-1];

    integer qb, kb, q_beats, k_beats, q_total_beats, k_total_beats, np;
    integer expected_jobs_total = 0, jobs_seen = 0;
    integer level = 0, cycles = 0;
    integer decision_count = 0, prune_count = 0;
    integer summary_fd = 0, pairs_fd = 0, norms_fd = 0;
    bit monitor_jobs = 0;
    string path, report_path;

    // One valid line per HEX entry. The notebook writer never inserts blank
    // lines. Return 0 for a missing or empty file and fail before readmemh.
    function automatic integer count_lines(input string filename);
        integer fd, r, n;
        string line;
        begin
            fd = $fopen(filename, "r");
            if (fd == 0) $fatal(1, "MISSING REAL QWEN DATA: %s", filename);
            n = 0;
            while (!$feof(fd)) begin
                r = $fgets(line, fd);
                if (r > 0) n = n + 1;
            end
            $fclose(fd);
            if (n <= 0) $fatal(1, "EMPTY GOLDEN FILE: %s", filename);
            count_lines = n;
        end
    endfunction

    // This test checks that the Q/K INT8 words match the golden norm files,
    // BEFORE comparing any RTL output. It also catches damaged / mis-packed HEX.
    task automatic validate_int8_words;
        integer b, w, lane;
        integer signed value;
        integer signed square;   // 32-bit signed multiplication result (always >= 0)
        longint unsigned sumsq;  // zero-extend positive square; no signed/unsigned mixing
        begin
            for (b=0; b<qb; b=b+1) begin
                sumsq=0;
                for (w=0; w<q_beats; w=w+1) begin
                    if (^q_words[b*q_beats+w] === 1'bx)
                        $fatal(1, "UNKNOWN Q HEX word at block=%0d beat=%0d", b, w);
                    for (lane=0; lane<32; lane=lane+1) begin
                        value = $signed(q_words[b*q_beats+w][8*lane +: 8]);
                        // IMPORTANT: evaluate the multiplication in a SIGNED 32-bit
                        // context first; direct sumsq += value*value can sign-convert
                        // negative INT8 lanes into unsigned 64-bit operands in XSim.
                        square = value * value;
                        sumsq = sumsq + $unsigned(square);
                    end
                end
                if (sumsq !== {32'b0,golden_q_norm[b]})
                    $fatal(1,"Q HEX norm mismatch block=%0d calculated=%0d expected=%0d",
                           b,sumsq,golden_q_norm[b]);
            end
            for (b=0; b<kb; b=b+1) begin
                sumsq=0;
                for (w=0; w<k_beats; w=w+1) begin
                    if (^k_words[b*k_beats+w] === 1'bx)
                        $fatal(1, "UNKNOWN K HEX word at block=%0d beat=%0d", b, w);
                    for (lane=0; lane<32; lane=lane+1) begin
                        value = $signed(k_words[b*k_beats+w][8*lane +: 8]);
                        square = value * value;
                        sumsq = sumsq + $unsigned(square);
                    end
                end
                if (sumsq !== {32'b0,golden_k_norm[b]})
                    $fatal(1,"K HEX norm mismatch block=%0d calculated=%0d expected=%0d",
                           b,sumsq,golden_k_norm[b]);
            end
            $display("GOLDEN INT8 PACKING PASS: Q=%0d K=%0d blocks",qb,kb);
        end
    endtask

    task automatic load_shared_data;
        integer q, k, i, exp_pairs, prev_q, prev_k;
        begin
            qb = count_lines({CASE_DIR,"/q_norm_sq.hex"});
            kb = count_lines({CASE_DIR,"/k_norm_sq.hex"});
            np = count_lines({CASE_DIR,"/pairs.hex"});
            q_total_beats = count_lines({CASE_DIR,"/q_int8.hex"});
            k_total_beats = count_lines({CASE_DIR,"/k_int8.hex"});
            if (qb>MAX_BLOCKS || kb>MAX_BLOCKS || np>MAX_PAIRS ||
                q_total_beats>MAX_BEATS || k_total_beats>MAX_BEATS)
                $fatal(1,"CASE exceeds 2048-token / MAX_BEATS limit: qb=%0d kb=%0d pairs=%0d qbeats=%0d kbeats=%0d",
                       qb,kb,np,q_total_beats,k_total_beats);
            if (q_total_beats%qb || k_total_beats%kb)
                $fatal(1,"Non-integral beats/block, invalid HEX count");
            q_beats=q_total_beats/qb;
            k_beats=k_total_beats/kb;
            if (q_beats<=0 || k_beats<=0 || q_beats>128 || k_beats>128)
                $fatal(1,"Invalid beats per block Q=%0d K=%0d",q_beats,k_beats);
            if (q_beats != k_beats)
                $fatal(1,"Q/K head_dim mismatch: q beats=%0d k beats=%0d",q_beats,k_beats);
            exp_pairs=0;
            for(q=0; q<qb; q=q+1)
                for(k=0; k<kb; k=k+1)
                    if(k<=q) exp_pairs++;
            if (np!=exp_pairs)
                $fatal(1,"Missing/extra causal pairs; file=%0d expected=%0d",np,exp_pairs);
            // Protect against accidentally re-running the 64-token fixture.
            if (qb<16 || kb<16)
                $fatal(1,"This is a REAL LONG Qwen test: need >=16 Q/K blocks; got %0d/%0d",qb,kb);
            path={CASE_DIR,"/q_int8.hex"};         $readmemh(path,q_words,0,q_total_beats-1);
            path={CASE_DIR,"/k_int8.hex"};         $readmemh(path,k_words,0,k_total_beats-1);
            path={CASE_DIR,"/q_norm_sq.hex"};      $readmemh(path,golden_q_norm,0,qb-1);
            path={CASE_DIR,"/k_norm_sq.hex"};      $readmemh(path,golden_k_norm,0,kb-1);
            path={CASE_DIR,"/pairs.hex"};          $readmemh(path,golden_pairs,0,np-1);
            path={CASE_DIR,"/expected_proxy.hex"};
            if (count_lines(path)!=np) $fatal(1,"Expected proxy count incorrect");
            $readmemh(path,golden_proxy,0,np-1);
            prev_q=-1;prev_k=-1;
            for(i=0;i<np;i=i+1) begin
                q=int'(golden_pairs[i][15:8]);k=int'(golden_pairs[i][7:0]);
                if(q>=qb || k>=kb || k>q)
                    $fatal(1,"Bad pairs.hex i=%0d q=%0d k=%0d",i,q,k);
                if (i>0 && (q<prev_q || (q==prev_q && k<=prev_k)))
                    $fatal(1,"pairs.hex is not strictly row-major at i=%0d",i);
                if (golden_proxy[i] !==
                    ({32'b0,golden_q_norm[q]}*{32'b0,golden_k_norm[k]}))
                    $fatal(1,"BAD GOLDEN PROXY at i=%0d",i);
                prev_q=q;prev_k=k;
            end
            validate_int8_words();
            $display("===============================================================");
            $display("REAL QWEN CASE: %s",CASE_DIR);
            $display("QB=%0d KB=%0d beats/block=%0d candidate_pairs=%0d",qb,kb,q_beats,np);
            $display("If q_len=2048, QB should be 64 and pairs should be 2080.");
            $display("===============================================================");
        end
    endtask

    // The four levels use the same real Q/K activation captured during
    // DENSE PREFILL. Diagonal KEEP is implemented using threshold_input=0.
    task automatic load_threshold_level(input integer sparse_level);
        integer i, q, k, n;
        logic [63:0] computed;
        begin
            level=sparse_level;
            path=$sformatf("%s/threshold_%0d.hex",CASE_DIR,level);
            if (count_lines(path)!=1) $fatal(1,"threshold file must have one line");
            $readmemh(path,global_T,0,0);
            path=$sformatf("%s/threshold_inputs_%0d.hex",CASE_DIR,level);
            if (count_lines(path)!=np) $fatal(1,"threshold inputs count mismatch at level=%0d",level);
            $readmemh(path,golden_threshold_input,0,np-1);
            path=$sformatf("%s/expected_mask_%0d.hex",CASE_DIR,level);
            if (count_lines(path)!=np) $fatal(1,"expected mask count mismatch at level=%0d",level);
            $readmemh(path,golden_keep,0,np-1);
            expected_jobs_total=0;
            jobs_seen=0;
            decision_count=0;
            prune_count=0;
            for(i=0;i<np;i=i+1) begin
                q=int'(golden_pairs[i][15:8]);k=int'(golden_pairs[i][7:0]);
                computed=(q==k) ? 64'b0 : global_T[0];
                if(golden_threshold_input[i] !== computed)
                    $fatal(1,"BAD T INPUT level=%0d pair=%0d got=%h exp=%h",
                           level,i,golden_threshold_input[i],computed);
                if(golden_keep[i] !== (golden_proxy[i]>=computed))
                    $fatal(1,"BAD MASK level=%0d pair=%0d",level,i);
                if(golden_keep[i]) begin
                    expected_jobs[expected_jobs_total] = golden_pairs[i];
                    expected_jobs_total++;
                end
            end
            $display("[GOLDEN T] level=%0d T=%0d (0x%016h) target_keep=%0d/%0d",
                     level,global_T[0],global_T[0],expected_jobs_total,np);
        end
    endtask

    always @(posedge clk) begin
        if(!rst) begin
            cycles <= cycles+1;
            if(monitor_jobs && job_valid && job_ready) begin
                if (jobs_seen>=expected_jobs_total)
                    $fatal(1,"EXTRA RTL job level=%0d q=%0d k=%0d",level,job_q_id,job_k_id);
                if ({job_q_id,job_k_id} !== expected_jobs[jobs_seen])
                    $fatal(1,"JOB ORDER MISMATCH level=%0d index=%0d got=%02h%02h expected=%04h",
                           level,jobs_seen,job_q_id,job_k_id,expected_jobs[jobs_seen]);
                jobs_seen = jobs_seen + 1;
            end
            if(pair_error)
                $fatal(1,"RTL missing-norm / pair_error at cycle=%0d",cycles);
            if(cycles>1000000) $fatal(1,"GLOBAL WATCHDOG >1,000,000 cycles");
        end
    end

    task automatic load_q(input integer b);
        integer w;
        begin
            @(negedge clk);
            if(q_busy || pair_valid) $fatal(1,"Q engine busy at block %0d",b);
            q_start=1;
            q_block_id=b[7:0];
            q_valid=0;
            @(negedge clk);
            q_start=0;
            for(w=0;w<q_beats;w=w+1) begin
                q_data=q_words[b*q_beats+w];
                q_valid=1;
                q_last=(w==q_beats-1);
                @(negedge clk);
            end
            q_valid=0;q_last=0;q_data='0;
            repeat(3) @(negedge clk);
            if(q_busy || dut.u_q_ram.present[b] !== 1'b1)
                $fatal(1,"Q Norm Engine / RAM load did not complete b=%0d",b);
            if(dut.u_q_ram.mem[b] !== golden_q_norm[b])
                $fatal(1,"Q NORM RTL FAIL b=%0d actual=%08h expected=%08h",
                       b,dut.u_q_ram.mem[b],golden_q_norm[b]);
            $fwrite(norms_fd,"Q,%0d,%08h,%08h,PASS\n",
                    b,golden_q_norm[b],dut.u_q_ram.mem[b]);
            if ((b+1)%16==0 || b==qb-1)
                $display("Q NORM PASS %0d/%0d",b+1,qb);
        end
    endtask

    task automatic load_k(input integer b);
        integer w;
        begin
            @(negedge clk);
            if(k_busy || pair_valid) $fatal(1,"K engine busy at block %0d",b);
            k_start=1;
            k_block_id=b[7:0];
            k_valid=0;
            @(negedge clk);
            k_start=0;
            for(w=0;w<k_beats;w=w+1) begin
                k_data=k_words[b*k_beats+w];
                k_valid=1;
                k_last=(w==k_beats-1);
                @(negedge clk);
            end
            k_valid=0;k_last=0;k_data='0;
            repeat(3) @(negedge clk);
            if(k_busy || dut.u_k_ram.present[b] !== 1'b1)
                $fatal(1,"K Norm Engine / RAM load did not complete b=%0d",b);
            if(dut.u_k_ram.mem[b] !== golden_k_norm[b])
                $fatal(1,"K NORM RTL FAIL b=%0d actual=%08h expected=%08h",
                       b,dut.u_k_ram.mem[b],golden_k_norm[b]);
            $fwrite(norms_fd,"K,%0d,%08h,%08h,PASS\n",
                    b,golden_k_norm[b],dut.u_k_ram.mem[b]);
            if ((b+1)%16==0 || b==kb-1)
                $display("K NORM PASS %0d/%0d",b+1,kb);
        end
    endtask

    task automatic one_pair(input integer idx);
        integer q,k,n;
        begin
            q=int'(golden_pairs[idx][15:8]);
            k=int'(golden_pairs[idx][7:0]);
            n=0;
            while (!pair_ready && n<MAX_WAIT_CYCLES) begin
                @(negedge clk);n++;
            end
            if(!pair_ready) $fatal(1,"pair_ready TIMEOUT at pair=%0d",idx);
            @(negedge clk);
            pair_q_id=q[7:0];pair_k_id=k[7:0];
            threshold_T=golden_threshold_input[idx];
            pair_valid=1;
            @(negedge clk);
            pair_valid=0;
            n=0;
            while(decision_valid !== 1'b1 && n<MAX_WAIT_CYCLES) begin
                @(negedge clk);n++;
            end
            if(!decision_valid) $fatal(1,"decision_valid TIMEOUT level=%0d pair=%0d",level,idx);
            if({decision_q_id,decision_k_id} !== golden_pairs[idx])
                $fatal(1,"PAIR ID FAIL level=%0d pair=%0d",level,idx);
            if(decision_q_norm !== golden_q_norm[q] ||
               decision_k_norm !== golden_k_norm[k])
                $fatal(1,"DECISION NORM FAIL level=%0d pair=%0d",level,idx);
            if(decision_score !== golden_proxy[idx])
                $fatal(1,"PROXY RTL FAIL level=%0d pair=%0d got=%016h expect=%016h",
                       level,idx,decision_score,golden_proxy[idx]);
            if(decision_threshold !== golden_threshold_input[idx])
                $fatal(1,"THRESHOLD RTL FAIL level=%0d pair=%0d got=%016h exp=%016h",
                       level,idx,decision_threshold,golden_threshold_input[idx]);
            if(decision_keep !== golden_keep[idx])
                $fatal(1,"KEEP/PRUNE RTL FAIL level=%0d pair=%0d q=%0d k=%0d got=%b exp=%b",
                       level,idx,q,k,decision_keep,golden_keep[idx]);
            decision_count++;
            if(!golden_keep[idx])prune_count++;
            $fwrite(pairs_fd,"%0d,%0d,%0d,%0d,%016h,%016h,%0d,PASS\n",
                    idx,level,q,k,decision_score,decision_threshold,decision_keep);
            if (idx==0 || (idx+1)%256==0 || idx==np-1)
                $display("PAIR PASS level=%0d %0d/%0d T=%016h kept=%0d",
                         level,idx+1,np,global_T[0],decision_count-prune_count);
        end
    endtask

    task automatic test_future_causal;
        integer n;
        begin
            if (qb<2 || kb<2) return;
            // An invalid causal pair must not create ANY scheduler job.
            expected_jobs_total=0;
            jobs_seen=0;
            monitor_jobs=1;
            n=0;
            while(!pair_ready && n<MAX_WAIT_CYCLES)begin
                @(negedge clk);n++;
            end
            if(!pair_ready) $fatal(1,"Causal pair_ready timeout");
            @(negedge clk);
            pair_q_id=0;pair_k_id=1;threshold_T=0;pair_valid=1;
            @(negedge clk);pair_valid=0;
            n=0;
            while(decision_valid !== 1'b1 && n<MAX_WAIT_CYCLES)begin
                @(negedge clk);n++;
            end
            if(!decision_valid || decision_keep !== 1'b0 || decision_score !== 64'b0)
                $fatal(1,"CAUSAL FUTURE q=0,k=1 FAIL");
            repeat (3) @(negedge clk);
            if(job_valid) $fatal(1,"Causal FUTURE unexpectedly scheduled job");
            if(jobs_seen!=0) $fatal(1,"Causal future pair emitted job");
            monitor_jobs=0;
            $display("CAUSAL FUTURE PASS (q=0,k=1)");
        end
    endtask

    task automatic run_level(input integer sparse_level);
        integer idx, wait_jobs;
        real actual_sparse;
        begin
            // Keep loaded Norm_RAM and Q/K activation unchanged across levels.
            load_threshold_level(sparse_level);
            report_path=$sformatf("%s/%s_pairs_%0d.csv",REPORT_DIR,REPORT_TAG,level);
            pairs_fd=$fopen(report_path,"w");
            if(pairs_fd==0) $fatal(1,"Cannot write %s",report_path);
            $fwrite(pairs_fd,"pair_idx,level,q_id,k_id,proxy_hex,threshold_input_hex,keep,status\n");
            monitor_jobs=1;
            for(idx=0;idx<np;idx=idx+1) one_pair(idx);
            wait_jobs=0;
            while(jobs_seen<expected_jobs_total && wait_jobs<MAX_WAIT_CYCLES)begin
                @(negedge clk);wait_jobs++;
            end
            if(jobs_seen!=expected_jobs_total ||
               decision_count!=np || (decision_count-prune_count)!=expected_jobs_total)
                $fatal(1,"LEVEL %0d COUNT FAIL: jobs=%0d/%0d decisions=%0d/%0d",
                       level,jobs_seen,expected_jobs_total,decision_count,np);
            repeat(3)@(negedge clk);
            if(dut.u_fifo.count!=0 || job_valid)
                $fatal(1,"FIFO NOT EMPTY after level %0d",level);
            monitor_jobs=0;
            actual_sparse=100.0*prune_count/np;
            $display("===============================================================");
            $display("RTL_PASS REAL_QWEN LEVEL=%0d T=%0d (0x%016h) pairs=%0d kept=%0d pruned=%0d actual_sparsity=%0f%% jobs=%0d",
                     level,global_T[0],global_T[0],np,expected_jobs_total,prune_count,actual_sparse,jobs_seen);
            $display("===============================================================");
            $fwrite(summary_fd,"%0d,%0d,%016h,%0d,%0d,%0d,%0f,%0d,%0d,RTL_PASS\n",
                    level,global_T[0],global_T[0],np,expected_jobs_total,
                    prune_count,actual_sparse,decision_count,jobs_seen);
            $fclose(pairs_fd);
        end
    endtask

    initial begin : main
        integer b;
        $display("=== QWEN REAL ACTIVATION FULL-TOP RTL / 4 LEVELS / VIVADO GUI ===");
        load_shared_data();
        report_path=$sformatf("%s/%s_norms.csv",REPORT_DIR,REPORT_TAG);
        norms_fd=$fopen(report_path,"w");
        if(norms_fd==0)$fatal(1,"Cannot write %s",report_path);
        $fwrite(norms_fd,"kind,block_id,expected_hex,rtl_hex,status\n");
        report_path=$sformatf("%s/%s_summary.csv",REPORT_DIR,REPORT_TAG);
        summary_fd=$fopen(report_path,"w");
        if(summary_fd==0)$fatal(1,"Cannot write %s",report_path);
        $fwrite(summary_fd,"target_sparsity_pct,threshold_T,threshold_hex,candidate_pairs,kept,pruned,actual_sparsity_pct,decision_passed,jobs_seen,status\n");
        repeat(5)@(negedge clk);
        rst=0;
        for(b=0;b<qb;b=b+1) load_q(b);
        for(b=0;b<kb;b=b+1) load_k(b);
        $display("ALL NORM ENGINE / RAM CHECKS PASSED: Q=%0d K=%0d",qb,kb);
        $fclose(norms_fd);
        repeat(3)@(negedge clk);
        run_level(50);
        run_level(70);
        run_level(80);
        run_level(90);
        test_future_causal();
        $fclose(summary_fd);
        $display("===============================================================");
        $display("FINAL REAL-QWEN: ALL 4 LEVELS RTL PASS (50/70/80/90)");
        $display("Case: %s",CASE_DIR);
        $display("Reports: %s/%s_summary.csv",REPORT_DIR,REPORT_TAG);
        $display("===============================================================");
        $finish;
    end
    initial begin
        #100000000; // 100 milliseconds in 1 ns timescale
        $fatal(1,"SIMULATION TIMEOUT: 100ms. Check loop or DUT handshake");
    end
endmodule

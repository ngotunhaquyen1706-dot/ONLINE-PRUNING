`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// End-to-end, SELF-CHECKING testbench for the supplied Norm_Base_Top.sv.
// Exact golden file names/packing of Qwen ...ThresholdT_RTL_Golden_v4.ipynb.
// GUI DEFAULTS replace CLI plusargs. Run from Vivado 2022.2 Behavioral Simulation.
// Uses actual RTL Norm_Engine.sv if provided; the optional REFERENCE engine
// verifies INTEGRATION ONLY, never the user's missing real Norm_Engine.
// -----------------------------------------------------------------------------
module tb_norm_proxy_GUI_v4;
    // ==== USER CONFIG: refer to vivado_testdata/<case>/metadata.json ====
    localparam string GUI_CASE_DIR = "D:/GEMM/NORM_PROXY/vivado_testdata/test_deterministic_64";
    localparam integer GUI_Q_BLOCKS = 2;
    localparam integer GUI_K_BLOCKS = 2;
    localparam integer GUI_Q_BEATS_PER_BLOCK = 64;
    localparam integer GUI_K_BEATS_PER_BLOCK = 64;
    localparam integer GUI_PAIR_COUNT = 3;
    localparam integer GUI_SPARSITY_LEVEL = 50; // 50,70,80,90
    localparam string GUI_REPORT_DIR = "D:/GEMM/NORM_PROXY/verification";
    // ================================================================
    localparam integer ID_W = 8;
    localparam integer NORM_W = 32;
    localparam integer MAX_BLOCKS = 128;
    localparam integer MAX_BEATS = 32768;
    localparam integer MAX_PAIRS = 8256; // MAX_BLOCKS*(MAX_BLOCKS+1)/2
    localparam integer FIFO_DEPTH = 8;

    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic rst = 1'b1;
    logic q_start = 0, k_start = 0;
    logic signed [255:0] q_data = '0, k_data = '0;
    logic q_valid = 0, q_last = 0, k_valid = 0, k_last = 0;
    logic [7:0] q_block_id = '0, k_block_id = '0;
    wire q_busy, k_busy, q_done, k_done;
    logic pair_valid = 0;
    wire pair_ready;
    logic [7:0] pair_q_id = 0, pair_k_id = 0;
    logic [63:0] threshold_T = '0;
    wire decision_valid, decision_keep, pair_error;
    wire [7:0] decision_q_id, decision_k_id;
    wire [31:0] decision_q_norm, decision_k_norm;
    wire [63:0] decision_score, decision_threshold;
    wire job_valid;
    logic job_ready = 1'b1;
    wire [7:0] job_q_id, job_k_id;

    Norm_Base_Top #(.ID_W(ID_W), .NORM_W(NORM_W), .FIFO_DEPTH(FIFO_DEPTH)) dut (
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

    logic [255:0] q_mem [0:MAX_BEATS-1];
    logic [255:0] k_mem [0:MAX_BEATS-1];
    logic [31:0] q_norm_exp [0:MAX_BLOCKS-1];
    logic [31:0] k_norm_exp [0:MAX_BLOCKS-1];
    logic [15:0] pairs [0:MAX_PAIRS-1];
    logic [63:0] proxy_exp [0:MAX_PAIRS-1];
    logic [63:0] t_input_exp [0:MAX_PAIRS-1];
    logic [0:0] keep_exp [0:MAX_PAIRS-1];
    logic [15:0] expected_jobs [0:MAX_PAIRS-1];
    logic [63:0] global_threshold [0:0];
    integer qb, kb, q_bpb, k_bpb, np, level;
    integer expected_jobs_total = 0;
    integer jobs_seen = 0;
    integer num_passed = 0;
    integer num_pruned = 0;
    integer cycle_count = 0;
    integer file_handle, norm_handle;
    string data_dir, report_file, norm_report_file;
    string f;

    always @(posedge clk) begin
        if (!rst) begin
            cycle_count <= cycle_count + 1;
            // One job should be scheduled for each KEEP decision, FIFO order.
            if (job_valid && job_ready) begin
                if (jobs_seen >= expected_jobs_total)
                    $fatal(1, "EXTRA JOB q=%0d k=%0d", job_q_id, job_k_id);
                if ({job_q_id,job_k_id} !== expected_jobs[jobs_seen])
                    $fatal(1, "JOB ORDER FAIL index=%0d got=%02h%02h exp=%04h",
                           jobs_seen, job_q_id, job_k_id, expected_jobs[jobs_seen]);
                jobs_seen <= jobs_seen + 1;
            end
            if (pair_error)
                $fatal(1, "RTL pair_error at cycle=%0d. Check RAM load/read timing and block IDs", cycle_count);
            // Guard against any unexpected hangs, even inside task waits.
            if (cycle_count > 2000000)
                $fatal(1, "GLOBAL WATCHDOG: >2,000,000 cycles");
        end
    end

    task automatic load_q_block(input integer b);
        integer beat;
        begin
            if (b < 0 || b >= qb) $fatal(1, "Invalid q block ID %0d", b);
            @(negedge clk);
            if (q_busy || pair_valid) $fatal(1, "Q engine busy at block=%0d", b);
            q_block_id = b[7:0];
            q_start = 1;
            q_valid = 0;
            @(negedge clk);
            q_start = 0;
            for (beat = 0; beat < q_bpb; beat = beat + 1) begin
                q_data = q_mem[b*q_bpb + beat];
                q_last = (beat == q_bpb-1);
                q_valid = 1;
                @(negedge clk);
            end
            q_valid = 0;
            q_last = 0;
            q_data = '0;
            // Norm output valid is captured by synchronous Norm_RAM one cycle later.
            repeat (3) @(negedge clk);
            if (q_busy) $fatal(1, "Q engine stuck busy, block %0d", b);
            if (dut.u_q_ram.present[b] !== 1'b1)
                $fatal(1, "Q norm missing in Norm_RAM, block=%0d", b);
            if (dut.u_q_ram.mem[b] !== q_norm_exp[b])
                $fatal(1, "NORM Q FAIL block=%0d expected=%08h got=%08h",
                       b, q_norm_exp[b], dut.u_q_ram.mem[b]);
            $fwrite(norm_handle,"Q,%0d,%08h,%08h,PASS\n",b,q_norm_exp[b],dut.u_q_ram.mem[b]);
        end
    endtask

    task automatic load_k_block(input integer b);
        integer beat;
        begin
            @(negedge clk);
            if (k_busy || pair_valid) $fatal(1, "K engine busy at block=%0d", b);
            k_block_id = b[7:0];
            k_start = 1;
            k_valid = 0;
            @(negedge clk);
            k_start = 0;
            for (beat = 0; beat < k_bpb; beat = beat + 1) begin
                k_data = k_mem[b*k_bpb + beat];
                k_last = (beat == k_bpb-1);
                k_valid = 1;
                @(negedge clk);
            end
            k_valid = 0;
            k_last = 0;
            k_data = '0;
            repeat (3) @(negedge clk);
            if (k_busy) $fatal(1, "K engine stuck busy, block %0d", b);
            if (dut.u_k_ram.present[b] !== 1'b1)
                $fatal(1, "K norm missing in Norm_RAM, block=%0d", b);
            if (dut.u_k_ram.mem[b] !== k_norm_exp[b])
                $fatal(1, "NORM K FAIL block=%0d expected=%08h got=%08h",
                       b, k_norm_exp[b], dut.u_k_ram.mem[b]);
            $fwrite(norm_handle,"K,%0d,%08h,%08h,PASS\n",b,k_norm_exp[b],dut.u_k_ram.mem[b]);
        end
    endtask

    task automatic run_pair(input integer idx);
        integer qid, kid, cycles_waited;
        begin
            qid = int'(pairs[idx][15:8]);
            kid = int'(pairs[idx][7:0]);
            cycles_waited = 0;
            while (!pair_ready && cycles_waited < 100) begin
                @(negedge clk);
                cycles_waited = cycles_waited + 1;
            end
            if (!pair_ready) $fatal(1, "TIMEOUT pair_ready idx=%0d", idx);
            @(negedge clk);
            pair_valid = 1;
            pair_q_id = qid[7:0];
            pair_k_id = kid[7:0];
            threshold_T = t_input_exp[idx];
            @(negedge clk); // accepted at previous posedge
            pair_valid = 0;
            cycles_waited = 0;
            while (decision_valid !== 1'b1 && cycles_waited < 100) begin
                @(negedge clk);
                cycles_waited = cycles_waited + 1;
            end
            if (!decision_valid) $fatal(1, "TIMEOUT decision_valid idx=%0d", idx);
            if (pair_error) $fatal(1, "Unexpected pair_error idx=%0d", idx);
            if ({decision_q_id,decision_k_id} !== pairs[idx])
                $fatal(1, "ID FAIL idx=%0d got=%02h%02h expected=%04h",
                       idx,decision_q_id,decision_k_id,pairs[idx]);
            if (decision_q_norm !== q_norm_exp[qid] || decision_k_norm !== k_norm_exp[kid])
                $fatal(1, "DECISION NORM FAIL idx=%0d pair=(%0d,%0d) q=%h/%h k=%h/%h",
                       idx,qid,kid,decision_q_norm,q_norm_exp[qid],decision_k_norm,k_norm_exp[kid]);
            if (decision_score !== proxy_exp[idx])
                $fatal(1, "PROXY FAIL idx=%0d (%0d,%0d) got=%016h exp=%016h",
                       idx,qid,kid,decision_score,proxy_exp[idx]);
            if (decision_threshold !== t_input_exp[idx])
                $fatal(1, "T INPUT FAIL idx=%0d got=%016h exp=%016h",
                       idx,decision_threshold,t_input_exp[idx]);
            if (decision_keep !== keep_exp[idx][0])
                $fatal(1, "KEEP FAIL idx=%0d (%0d,%0d) score=%016h threshold=%016h got=%b exp=%b",
                       idx,qid,kid,decision_score,decision_threshold,decision_keep,keep_exp[idx][0]);
            num_passed = num_passed + 1;
            if (keep_exp[idx][0] == 1'b0) num_pruned = num_pruned + 1;
            $fwrite(file_handle,"%0d,%0d,%0d,%0d,%08h,%08h,%016h,%016h,%0d,%0d,PASS\n",
                    idx,level,qid,kid,decision_q_norm,decision_k_norm,
                    decision_score,decision_threshold,decision_keep,cycle_count);
            if (idx < 3 || ((idx+1) % 256 == 0) || idx == np-1)
                $display("pair=%0d/%0d q=%0d k=%0d T=%016h keep=%0d PASS",
                         idx+1,np,qid,kid,t_input_exp[idx],decision_keep);
        end
    endtask

    task automatic test_future_pair;
        integer count_wait;
        begin
            if (qb < 2 || kb < 2) return;
            count_wait = 0;
            while (!pair_ready && count_wait < 100) begin
                @(negedge clk);
                count_wait = count_wait + 1;
            end
            if (!pair_ready) $fatal(1,"Future pair ready timeout");
            @(negedge clk);
            pair_valid = 1;
            pair_q_id = 0;
            pair_k_id = 1; // INVALID: k > q
            threshold_T = 0;
            @(negedge clk);
            pair_valid = 0;
            count_wait = 0;
            while (decision_valid !== 1'b1 && count_wait < 100) begin
                @(negedge clk);
                count_wait = count_wait + 1;
            end
            if (!decision_valid) $fatal(1,"Future pair decision timeout");
            if (decision_keep !== 1'b0 || decision_score !== 64'b0)
                $fatal(1,"CAUSAL FILTER FAIL expected prune and score=0 got=%b/%h",
                       decision_keep,decision_score);
            $display("CAUSAL FUTURE BLOCK (q=0,k=1) PASS");
        end
    endtask

    initial begin : test_main
        integer i, j, qid, kid, r;
        data_dir = GUI_CASE_DIR;
        qb=GUI_Q_BLOCKS;
        kb=GUI_K_BLOCKS;
        q_bpb=GUI_Q_BEATS_PER_BLOCK;
        k_bpb=GUI_K_BEATS_PER_BLOCK;
        np=GUI_PAIR_COUNT;
        level=GUI_SPARSITY_LEVEL;
        report_file=$sformatf("%s/gui_full_pairs_%0d.csv",GUI_REPORT_DIR,level);
        norm_report_file=$sformatf("%s/gui_full_norms_%0d.csv",GUI_REPORT_DIR,level);
        if (qb<=0 || qb>MAX_BLOCKS || kb<=0 || kb>MAX_BLOCKS ||
            np<=0 || np>MAX_PAIRS || q_bpb<=0 || k_bpb<=0 ||
            qb*q_bpb>MAX_BEATS || kb*k_bpb>MAX_BEATS)
            $fatal(1,"Out-of-range case config QB=%0d KB=%0d QBPB=%0d KBPB=%0d NP=%0d",
                   qb,kb,q_bpb,k_bpb,np);
        if (level!=50 && level!=70 && level!=80 && level!=90)
            $fatal(1,"LEVEL must be 50,70,80,90, not %0d",level);
        $display("TB BEGIN dir=%s level=%0d Q=%0d K=%0d beats/block Q=%0d K=%0d pairs=%0d",
                 data_dir,level,qb,kb,q_bpb,k_bpb,np);
        f={data_dir,"/q_int8.hex"};             $readmemh(f,q_mem,0,qb*q_bpb-1);
        f={data_dir,"/k_int8.hex"};             $readmemh(f,k_mem,0,kb*k_bpb-1);
        f={data_dir,"/q_norm_sq.hex"};         $readmemh(f,q_norm_exp,0,qb-1);
        f={data_dir,"/k_norm_sq.hex"};         $readmemh(f,k_norm_exp,0,kb-1);
        f={data_dir,"/pairs.hex"};             $readmemh(f,pairs,0,np-1);
        f={data_dir,"/expected_proxy.hex"};    $readmemh(f,proxy_exp,0,np-1);
        f=$sformatf("%s/threshold_inputs_%0d.hex",data_dir,level);
        $readmemh(f,t_input_exp,0,np-1);
        f=$sformatf("%s/expected_mask_%0d.hex",data_dir,level);
        $readmemh(f,keep_exp,0,np-1);
        f=$sformatf("%s/threshold_%0d.hex",data_dir,level);
        $readmemh(f,global_threshold,0,0);
        file_handle=$fopen(report_file,"w");
        if (file_handle==0) $fatal(1,"Cannot write REPORT_FILE=%s",report_file);
        $fwrite(file_handle,"pair_idx,level,q_id,k_id,q_norm_hex,k_norm_hex,proxy_hex,threshold_hex,keep,cycle,status\n");
        norm_handle=$fopen(norm_report_file,"w");
        if (norm_handle==0) $fatal(1,"Cannot write NORM_REPORT_FILE=%s",norm_report_file);
        $fwrite(norm_handle,"kind,block_id,expected_norm_hex,rtl_norm_hex,status\n");

        // Independently check the structure, golden products, comparator and
        // expected FIFO order BEFORE clocking RTL. Detect corrupted/misaligned files.
        expected_jobs_total=0;
        j=0;
        for (i=0;i<np;i=i+1) begin
            qid=int'(pairs[i][15:8]);kid=int'(pairs[i][7:0]);
            if (qid>=qb || kid>=kb || kid>qid) $fatal(1,"BAD pairs.hex[%0d]=%0d,%0d",i,qid,kid);
            if (i!=0 && ((pairs[i][15:8]<pairs[i-1][15:8]) ||
                         (pairs[i][15:8]==pairs[i-1][15:8] && pairs[i][7:0]<=pairs[i-1][7:0])))
                $fatal(1,"pairs.hex is not sorted row-major at %0d",i);
            if (proxy_exp[i] !== ({32'b0,q_norm_exp[qid]} * {32'b0,k_norm_exp[kid]}))
                $fatal(1,"GOLDEN PROXY INCONSISTENCY index=%0d",i);
            if (keep_exp[i][0] !== (proxy_exp[i]>=t_input_exp[i]))
                $fatal(1,"GOLDEN T/MASK INCONSISTENCY index=%0d",i);
            if (qid==kid) begin
                if (t_input_exp[i] !== 64'b0)
                    $fatal(1,"Diagonal threshold must equal ZERO at index=%0d",i);
            end else if (t_input_exp[i] !== global_threshold[0])
                $fatal(1,"Offdiagonal threshold differs from threshold_%0d.hex at %0d",level,i);
            if (keep_exp[i][0]) begin
                expected_jobs[expected_jobs_total] = pairs[i];
                expected_jobs_total = expected_jobs_total + 1;
            end
        end
        $display("GOLDEN SELF-CHECK PASS: T(offdiag)=%016h expected KEEP jobs=%0d/%0d",
                 global_threshold[0],expected_jobs_total,np);
        repeat (5) @(negedge clk);
        rst=0;
        // Test Q/K streaming engines + Norm_RAM per block, complete all before pairs.
        for (i=0;i<qb;i=i+1) load_q_block(i);
        $display("Q NORM PASS: %0d blocks",qb);
        for (i=0;i<kb;i=i+1) load_k_block(i);
        $display("K NORM PASS: %0d blocks",kb);
        repeat (2) @(negedge clk);
        for (i=0;i<np;i=i+1) run_pair(i);
        test_future_pair();
        // Wait for scheduler to drain, including final KEEP in flight.
        i=0;
        while (jobs_seen < expected_jobs_total && i<100) begin
            @(negedge clk);
            i=i+1;
        end
        if (jobs_seen != expected_jobs_total)
            $fatal(1,"JOB COUNT FAIL got=%0d exp=%0d",jobs_seen,expected_jobs_total);
        repeat(3) @(negedge clk);
        if (dut.u_fifo.count != 0 || job_valid)
            $fatal(1,"FIFO did not drain / job_valid stuck");
        if (num_passed != np) $fatal(1,"DECISION COUNT FAIL got=%0d exp=%0d",num_passed,np);
        $display("==================================================");
        $display("RTL_PASS level=%0d candidate=%0d kept=%0d pruned=%0d actual_sparsity_pct=%0f jobs=%0d cycles=%0d",
                 level,np,expected_jobs_total,num_pruned,100.0*num_pruned/np,jobs_seen,cycle_count);
        $display("==================================================");
        $fwrite(file_handle,"SUMMARY,%0d,,,,,,,kept=%0d,cycles=%0d,RTL_PASS\n",
                level,expected_jobs_total,cycle_count);
        $fclose(file_handle);
        $fclose(norm_handle);
        $finish;
    end
endmodule

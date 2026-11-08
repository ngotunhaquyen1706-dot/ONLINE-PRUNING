`timescale 1ns/1ps
module tb_Norm_Engine;
    logic clk=0, rst=1, start=0, data_valid=0, data_last=0;
    logic signed [255:0] data_in=0;
    logic [7:0] block_id=0;
    wire [31:0] norm_sq;
    wire [7:0] norm_block_id;
    wire norm_valid, busy, done;
    integer total=0, passed=0;
    Norm_Engine dut(.*);
    always #5 clk=~clk;
    // Waveform: add_wave /tb_Norm_Engine/* /tb_Norm_Engine/dut/word_sum
    // add_wave /tb_Norm_Engine/dut/accumulator
    task automatic check(input bit ok, input string message);
        if (!ok) $fatal(1,"FAIL: %s",message);
    endtask
    task automatic run_block(input string name, input integer words,
                             input integer pattern, input integer id,
                             input bit gaps);
        integer w, lane;
        longint signed value, expected, per_word;
        logic [31:0] previous_acc;
        begin
            total=total+1;
            expected=0;
            @(negedge clk);
            start=1; data_valid=0; data_last=0; block_id=id;
            @(posedge clk); #1;
            check(busy && !done && !norm_valid,"start state");
            for(w=0;w<words;w=w+1) begin
                @(negedge clk);
                start=0; data_valid=1; data_last=(w==words-1);
                per_word=0;
                for(lane=0;lane<32;lane=lane+1) begin
                    case(pattern)
                        1000: value=lane-16;
                        1001: case(lane%5)
                            0:value=-128; 1:value=-1; 2:value=0;
                            3:value=1; 4:value=127;
                        endcase
                        default:value=pattern;
                    endcase
                    data_in[lane*8 +: 8]=value[7:0];
                    per_word=per_word+value*value;
                end
                expected=expected+per_word;
                @(posedge clk); #1;
                check(dut.word_sum===per_word,"word_sum signed arithmetic");
                if(w==words-1) begin
                    $display("TEST: %s INPUT SIZE=%0d words EXPECTED=%0d DUT RESULT=%0d BLOCK ID=%0d VALID=%b",
                             name,words,expected,norm_sq,norm_block_id,norm_valid);
                    check(norm_valid && done && !busy,"last-word pulse");
                    check(norm_sq===expected && norm_block_id==id,"final norm and ID");
                end else check(!norm_valid && !done && busy,"intermediate state");
                if(gaps && w<words-1) begin
                    previous_acc=dut.accumulator;
                    @(negedge clk); data_valid=0; data_last=1; data_in='1;
                    @(posedge clk); #1;
                    check(dut.accumulator===previous_acc && !norm_valid && !done,"invalid gap ignored");
                end
            end
            @(negedge clk); data_valid=0; data_last=0;
            @(posedge clk); #1;
            check(!norm_valid && !done && !busy,"one-cycle output pulse");
            passed=passed+1;
            $display("PASS");
        end
    endtask
    initial begin
        repeat(2) @(negedge clk);
        rst=0;
        run_block("all +1",64,1,0,0);
        run_block("all -128 / next block without reset",4,-128,1,0);
        run_block("mixed signed",8,1000,2,0);
        run_block("valid gaps",4,2,3,1);
        run_block("signed extremes / ID boundary",1,1001,255,0);
        run_block("zero / no accumulator leak",1,0,0,0);
        run_block("all +127",2,127,4,0);
        run_block("maximum supported worst-case block",8191,-128,5,0);
        // Idle data must be ignored; reset during a partial block cancels it.
        @(negedge clk); data_valid=1; data_last=1;
        @(posedge clk); #1; check(!norm_valid && !busy,"idle input ignored");
        @(negedge clk); start=1; data_valid=0;
        @(negedge clk); start=0; data_valid=1; data_last=0; data_in='1;
        @(negedge clk); rst=1;
        @(posedge clk); #1;
        check(!busy && !norm_valid && !done && norm_sq==0 && dut.accumulator==0,"reset cancels block");
        total=total+1; passed=passed+1;
        $display("TOTAL TESTS=%0d PASSED=%0d FAILED=0 ALL TESTS PASS",total,passed);
        $finish;
    end
    initial begin #200000; $fatal(1,"timeout"); end
endmodule

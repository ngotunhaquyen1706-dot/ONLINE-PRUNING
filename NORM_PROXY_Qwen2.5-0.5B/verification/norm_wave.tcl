# xsim norm_engine_verified -tclbatch norm_wave.tcl
log_wave /tb_Norm_Engine/*
log_wave /tb_Norm_Engine/dut/word_sum
log_wave /tb_Norm_Engine/dut/accumulator
run all
quit

param([string]$VivadoBin='C:\VIVADO\Vivado\2022.2\bin')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    & "$VivadoBin\xvlog.bat" --sv ..\NORM_PROXY.srcs\sources_1\new\Norm_Engine.sv ..\NORM_PROXY.srcs\sim_1\new\tb_Norm_Engine.sv
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    & "$VivadoBin\xelab.bat" work.tb_Norm_Engine -s norm_engine_verified -debug typical
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }
    & "$VivadoBin\xsim.bat" norm_engine_verified -tclbatch norm_wave.tcl -wdb Norm_Engine.wdb -log norm_engine_simulation.log
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }
    if (-not (Select-String -Path norm_engine_simulation.log -SimpleMatch 'ALL TESTS PASS' -Quiet)) { throw 'Simulation did not pass' }
} finally { Pop-Location }

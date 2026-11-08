param([Parameter(Mandatory=$true)][string]$Module,
      [string]$VivadoBin='C:\VIVADO\Vivado\2022.2\bin')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    $rtl=@(Get-ChildItem ../RTL/*.sv | ForEach-Object {$_.FullName})
    $rtl+= (Resolve-Path ../NORM_PROXY.srcs/sources_1/new/Norm_Engine.sv).Path
    $tb="../TB/tb_$Module.sv"
    & "$VivadoBin/xvlog.bat" --sv @rtl $tb
    if ($LASTEXITCODE -ne 0) {throw 'xvlog failed'}
    & "$VivadoBin/xelab.bat" "work.tb_$Module" -s "test_$Module" -debug typical
    if ($LASTEXITCODE -ne 0) {throw 'xelab failed'}
    @('log_wave -r /*','run all','quit') | Set-Content "wave_$Module.tcl"
    & "$VivadoBin/xsim.bat" "test_$Module" -tclbatch "wave_$Module.tcl" -wdb "$Module.wdb" -log "$Module.log"
    if ($LASTEXITCODE -ne 0) {throw 'xsim failed'}
    if (-not (Select-String -Path "$Module.log" -SimpleMatch 'ALL TESTS PASS' -Quiet)) {throw 'Missing PASS summary'}
} finally {Pop-Location}

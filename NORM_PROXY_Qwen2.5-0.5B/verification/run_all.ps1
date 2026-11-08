param([string]$VivadoBin='C:\VIVADO\Vivado\2022.2\bin')
$ErrorActionPreference='Stop'
$results=@()
$names=@('Norm_Engine','Norm_RAM','Causal_Block_Mask','Proxy_Engine','Threshold_Comparator','Block_FIFO','Block_Scheduler','Norm_Base_Top')
foreach($name in $names) {
 try {
  if($name -eq 'Norm_Engine') { & "$PSScriptRoot/run_norm.ps1" -VivadoBin $VivadoBin }
  else { & "$PSScriptRoot/run_module.ps1" -Module $name -VivadoBin $VivadoBin }
  $results+=[pscustomobject]@{Module=$name;Status='PASS';Error=''}
 } catch {
  $results+=[pscustomobject]@{Module=$name;Status='FAIL';Error=$_.Exception.Message}
  break
 }
}
$results | Export-Csv -NoTypeInformation "$PSScriptRoot/verification_summary.csv"
$results | Format-Table -AutoSize | Out-Host
$passed=@($results | Where-Object Status -eq 'PASS').Count
$failed=@($results | Where-Object Status -eq 'FAIL').Count
Write-Host "MODULE SUMMARY: PASS=$passed FAIL=$failed NOT RUN=$($names.Count-$results.Count)"
if($failed -gt 0) {throw 'Verification stopped at first failed module; see summary and module log.'}
& "$PSScriptRoot/verify_workspace.ps1"
Write-Host 'ALL MODULES PASS'

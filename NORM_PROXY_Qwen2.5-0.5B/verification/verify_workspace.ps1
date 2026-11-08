$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path "$PSScriptRoot/..").Path
$referenceRoot=(Resolve-Path "$projectRoot/../GEMM_final_DSP").Path
$baseline=@(Import-Csv "$PSScriptRoot/gemm_before.csv")
$current=@(Get-ChildItem -LiteralPath $referenceRoot -Recurse -File)
# Original Windows PowerShell Export-Csv used ASCII. Resolve any non-ASCII
# directory names uniquely through the same encoding, then compare SHA256.
$index=@{}
foreach($file in $current) {
 $key=[System.Text.Encoding]::ASCII.GetString([System.Text.Encoding]::ASCII.GetBytes($file.FullName))
 if($index.ContainsKey($key)) {throw "Ambiguous reference manifest path: $key"}
 $index[$key]=$file.FullName
}
$changed=@();$missing=@();$checked=0
foreach($entry in $baseline) {
 if(-not $index.ContainsKey($entry.Path)) {$missing+=$entry.Path;continue}
 $actualPath=$index[$entry.Path]
 $actualHash=(Get-FileHash -LiteralPath $actualPath -Algorithm SHA256).Hash
 if($actualHash -ne $entry.Hash) {$changed+=$actualPath}
 $checked++
}
$integrity=[pscustomobject]@{BaselineFiles=$baseline.Count;CurrentFiles=$current.Count;CheckedHashes=$checked;ChangedFiles=$changed.Count;MissingFiles=$missing.Count}
$integrity | ConvertTo-Json | Set-Content -Encoding UTF8 "$PSScriptRoot/gemm_integrity.json"
$integrity | Format-List | Out-Host
if($changed.Count -or $missing.Count -or $baseline.Count -ne $current.Count) {
 throw "Reference integrity failure. Changed: $changed Missing: $missing"
}
[xml]$project=Get-Content -LiteralPath "$projectRoot/NORM_PROXY.xpr"
$sourceCount=0
foreach($set in $project.Project.FileSets.FileSet) {
 foreach($file in $set.File) {
  if($null -eq $file) {continue}
  $sourcePath=$file.Path.Replace('$PPRDIR',$projectRoot).Replace('$PSRCDIR',"$projectRoot/NORM_PROXY.srcs")
  if(-not (Test-Path -LiteralPath $sourcePath)) {throw "Project references missing file: $sourcePath"}
  $sourceCount++
 }
}
Write-Host "PROJECT XML PASS: $sourceCount source/testbench files exist. GEMM reference SHA256 PASS."

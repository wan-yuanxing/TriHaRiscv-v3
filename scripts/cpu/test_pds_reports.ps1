#requires -Version 7.0
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'pds_reports.ps1')
$sample = "Total LUTs: 123 of 66600 (0.18%)`nTotal Registers: 456 of 133200 (0.34%)`nTotal Latches: 0`nTotal DRM = 0.5 of 155 (0.32%)`nTotal APMs = 4.00 of 240 (1.67%)`nTotal I/O ports = 244 of 300 (81.33%)`n"
$resources = Get-TrihaPdsResources $sample
if ($resources.lut -ne 123 -or $resources.registers -ne 456 -or
    $resources.drm -ne 0.5 -or $resources.apm -ne 4 -or $resources.io -ne 244) { throw 'Resource count mismatch.' }
$rejected = 0
foreach ($bad in @('', $sample.Replace('Total APMs = 4.00','APMs missing'), $sample + "`nTotal LUTs = 99")) {
    try { Get-TrihaPdsResources $bad | Out-Null } catch { ++$rejected }
}
if ($rejected -ne 3) { throw 'Missing/duplicate resource field was accepted.' }
Assert-TrihaPdsStages "Executing : compile -top_module triha_core successfully.`nExecuting : synthesize -ads successfully.`nExecuting : dev_map -detail successfully." 'map'
$rejected = 0
foreach ($bad in @('Executing : compile successfully.',
    "E: native failure`nExecuting : compile successfully.`nExecuting : synthesize successfully.")) {
    try { Assert-TrihaPdsStages $bad 'synth' } catch { ++$rejected }
}
if ($rejected -ne 2) { throw 'Failed/missing PDS stage was accepted.' }
$configuration = "I: Module instance {triha_core} parameter value:`n    DUAL_ISSUE = 32'b00000000000000000000000000000000`nI: Module instance {triha_core/u_cpu} parameter value:`n"
foreach ($key in @('SUPPORT_BRANCH_PREDICTION','SUPPORT_MULDIV','SUPPORT_SUPER','SUPPORT_MMU',
    'SUPPORT_DUAL_ISSUE','SUPPORT_LOAD_BYPASS','SUPPORT_MUL_BYPASS','SUPPORT_REGFILE_XILINX','EXTRA_DECODE_STAGE')) {
    $value = [int]($key -in @('SUPPORT_BRANCH_PREDICTION','SUPPORT_MULDIV','SUPPORT_LOAD_BYPASS','SUPPORT_MUL_BYPASS'))
    $configuration += "    $key = 32'b" + [Convert]::ToString($value,2).PadLeft(32,'0') + "`n"
}
Assert-TrihaPdsConfiguration $configuration 0 | Out-Null
$rejected = 0
foreach ($bad in @($configuration,'')) {
    try { Assert-TrihaPdsConfiguration $bad 1 | Out-Null } catch { ++$rejected }
}
if ($rejected -ne 2) { throw 'Wrong/missing elaborated issue width was accepted.' }
$mapped = "| LUT | 123 | 66600 |`n| FF | 456 | 133200 |`n| DRM | 0.5 | 155 |`n| APM | 4 | 240 |`n| IO | 244 | 300 |`n"
$mappedResources = Get-TrihaPdsMappedResources $mapped
foreach ($key in $mappedResources.Keys) {
    if ($mappedResources[$key] -ne $resources[$key]) { throw "Mapped resource mismatch: $key" }
}
$rejected = $false
try { Get-TrihaPdsMappedResources '' | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Empty map report was accepted.' }
Write-Host 'CPU_PDS_REPORT_TEST PASS resource_stage_configuration_checks=12'

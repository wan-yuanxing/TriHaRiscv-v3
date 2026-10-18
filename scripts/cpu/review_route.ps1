#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string] $RunDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'firmware_common.ps1')
. (Join-Path $PSScriptRoot 'pds_reports.ps1')
. (Join-Path $PSScriptRoot 'route_reports.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$run=(Resolve-Path -LiteralPath $RunDirectory).Path
$receipt=Join-Path $root ('build/cpu/route-review-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')+'.json')
$result=[ordered]@{status='FAIL';run=$run;frozen_result_sha256=$null;input_count=0;output_count=0
    flow_status='UNKNOWN';timing=$null;mapped_resources=$null;error=$null;reviewer_hashes=[ordered]@{}}
try {
    $path=Join-Path $run 'result.json'
    $result.frozen_result_sha256=Get-TrihaHash $path
    $frozen=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    if(-not $frozen.source_unchanged){throw 'Original run inputs changed.'}
    foreach($entry in $frozen.input_hashes.PSObject.Properties) {
        if((Get-TrihaHash (Join-Path $run ('src/'+$entry.Name))) -ne $entry.Value){throw "Frozen input mismatch: $($entry.Name)"}
        $result.input_count++
    }
    foreach($entry in $frozen.output_hashes.PSObject.Properties) {
        if((Get-TrihaHash (Join-Path $run $entry.Name)) -ne $entry.Value){throw "Frozen output mismatch: $($entry.Name)"}
        $result.output_count++
    }
    foreach($name in @('review_route.ps1','pds_reports.ps1','route_reports.ps1','firmware_common.ps1')) {
        $result.reviewer_hashes[$name]=Get-TrihaHash (Join-Path $PSScriptRoot $name)
    }
    $pds=@($frozen.native_commands|Where-Object {$_.arguments -contains '-file'})
    if($pds.Count -ne 1 -or $pds[0].return_code -ne 0 -or $pds[0].timed_out){throw 'Native PDS did not complete successfully.'}
    $output=[IO.File]::ReadAllText((Join-Path $run 'pds.stdout.log'))
    Assert-TrihaPdsStages $output 'map'
    foreach($stage in @('pnr','report_timing')) {
        if($output -notmatch ('(?m)^Executing : '+$stage+'(?: [^\r\n]*)? successfully\.\s*$')){throw "Missing route stage: $stage"}
    }
    $result['configuration']=Assert-TrihaPdsConfiguration ([IO.File]::ReadAllText((Join-Path $run 'compile/run.log'))) 0
    $unconstrained=@([regex]::Matches($output,"(?m)^W: Timing-408[67]: Port '([^']+)' is not constrained.*$")|
        Where-Object {$_.Groups[1].Value -ne 'clk_i'})
    if($unconstrained.Count -ne 0){throw 'Functional CPU port missing timing constraint.'}
    $result.timing=Get-TrihaRouteTiming ([IO.File]::ReadAllText((Join-Path $run 'report_timing/triha_core.rtr')))
    $result.mapped_resources=Get-TrihaPdsMappedResources ([IO.File]::ReadAllText((Join-Path $run 'device_map/triha_core.dmr')))
    $result.flow_status='PASS'
    $result.status=if($result.timing.met){'PASS'}else{'TIMING_FAIL'}
} catch {$result.error=$_.Exception.Message}
Save-TrihaJson $receipt $result
Write-Host "CPU_ROUTE_REVIEW $($result.status) receipt=$receipt"
if($result.error){Write-Host $result.error}
if($result.status -eq 'PASS'){exit 0}elseif($result.status -eq 'TIMING_FAIL'){exit 2}else{exit 1}

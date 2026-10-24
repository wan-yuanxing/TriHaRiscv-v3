#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $PreparedDirectory,
    [switch] $Execute,
    [switch] $AllowConcurrentPds,
    [string] $PdsShell='D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'firmware_common.ps1')
. (Join-Path $PSScriptRoot 'pds_reports.ps1')
. (Join-Path $PSScriptRoot 'route_reports.ps1')
$work=(Resolve-Path -LiteralPath $PreparedDirectory).Path
$preparedPath=Join-Path $work 'prepared.json'
$preparedHash=Get-TrihaHash $preparedPath
$prepared=Get-Content -LiteralPath $preparedPath -Raw|ConvertFrom-Json
if($prepared.status -ne 'PREPARED_NOT_EXECUTED' -or $prepared.pds_started){throw 'Need an unexecuted frozen package.'}
& python (Join-Path $PSScriptRoot 'prepare_dual_physical.py') $work --verify
if($LASTEXITCODE -ne 0){throw 'Frozen package verification failed.'}
if(-not $Execute){Write-Host 'DUAL_ROUTE_PREFLIGHT_PASS PDS_NOT_STARTED';exit 0}
# Concurrent independent PDS runs require explicit opt-in. Never stop other runs.
$busy=@(Get-CimInstance Win32_Process|Where-Object {$_.Name -match '^pds_shell\.exe$|^pnr\.exe$'})
if($busy.Count -and -not $AllowConcurrentPds){throw 'PDS is occupied; use explicit AllowConcurrentPds for an isolated concurrent run.'}
if(Test-Path -LiteralPath (Join-Path $work 'result.json')){throw 'Do not overwrite a prior route attempt.'}
foreach($directory in @('compile','synthesize','device_map','place_route','report_timing')){
    if(Test-Path -LiteralPath (Join-Path $work $directory)){throw 'Prior tool output exists; prepare a fresh package.'}
}
# TEMP/TMP changes are local to this runner process and its children.
$privateTemp=Join-Path $work 'native-temp'
[IO.Directory]::CreateDirectory($privateTemp)|Out-Null
$env:TEMP=$privateTemp;$env:TMP=$privateTemp
$toolHashes=[ordered]@{}
$verificationSnapshot=Join-Path $work 'verification-src'
[IO.Directory]::CreateDirectory($verificationSnapshot)|Out-Null
foreach($name in @('run_dual_route.ps1','prepare_dual_physical.py','firmware_common.ps1','pds_reports.ps1','route_reports.ps1','../../fpga/pg2l100h/project/cpu_minimal_soc.json')){
    $path=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot $name)).Path;$toolHashes[$path]=Get-TrihaHash $path
    [IO.File]::Copy($path,(Join-Path $verificationSnapshot ([IO.Path]::GetFileName($path))))
}
$commands=[Collections.Generic.List[object]]::new()
$row=[ordered]@{status='RUNNING';flow_status='RUNNING';timing_closed=$false;source_unchanged=$false
    concurrent_pds_allowed=[bool]$AllowConcurrentPds;other_pds_at_launch=@($busy|Select-Object ProcessId,Name,CommandLine);private_temp=$privateTemp
    prepared_sha256=$preparedHash;verification_tool_hashes=$toolHashes;native_commands=$commands;output_hashes=[ordered]@{}
    timing=$null;error=$null;runner_return_code=$null;board_validated=$false
    cpu_only_resources=$null;cpu_area_status='UNKNOWN: system resources are not CPU-only'
    scope='Isolated dual CPU plus actual ROM/SRAM/MMIO; no board or official CoreMark acceptance'}
$result=Join-Path $work 'result.json'
Save-TrihaJson $result $row
try {
    $row['pds_shell_sha256']=Get-TrihaHash $PdsShell
    $row['pds_version']=Invoke-TrihaNative $PdsShell @('-version') $work 'pds-version' $commands
    $output=Invoke-TrihaNative -Executable $PdsShell -CommandArguments @('-file',(Join-Path $work 'build.tcl'),'-work_dir',$work,'-project_name','triha_minimal_soc') -RunDirectory $work -Label 'pds-route' -Records $commands -TimeoutSeconds 900
    Assert-TrihaPdsStages $output 'map'
    foreach($stage in @('pnr','report_timing')){
        if($output -notmatch ('(?m)^Executing : '+$stage+'(?: [^\r\n]*)? successfully\.\s*$')){throw "Missing stage: $stage"}
    }
    $compile=[IO.File]::ReadAllText((Join-Path $work 'compile/run.log'))
    if($compile -notmatch 'Module instance \{triha_minimal_soc/u_core\}'){throw 'Actual CPU hierarchy missing.'}
    $compile=$compile.Replace('triha_minimal_soc/u_core','triha_core')
    $row['configuration']=Assert-TrihaPdsConfiguration $compile 1 1 1
    $row['predictor']=Assert-TrihaPdsPredictorConfiguration $compile
    $unconstrained=@([regex]::Matches($output,"(?m)^W: Timing-408[67]: Port '([^']+)' is not constrained.*$")|Where-Object {$_.Groups[1].Value -ne 'clk_i'})
    if($unconstrained.Count){throw 'Unconstrained functional port.'}
    $row.timing=Get-TrihaRouteTiming ([IO.File]::ReadAllText((Join-Path $work 'report_timing/triha_minimal_soc.rtr')))
    $row['system_resources']=Get-TrihaPdsMappedResources ([IO.File]::ReadAllText((Join-Path $work 'device_map/triha_minimal_soc.dmr')))
    if($row.system_resources.drm -lt 8){throw 'SRAM native block mapping missing.'}
    $row.flow_status='PASS';$row.timing_closed=$row.timing.met
    $row.status=if($row.timing_closed){'TIMING_PASS_AREA_PENDING'}else{'TIMING_FAIL'}
} catch {$row.status='FAIL';$row.flow_status='FAIL';$row.error=$_.Exception.Message}
finally {
    & python (Join-Path $PSScriptRoot 'prepare_dual_physical.py') $work --verify
    $row.source_unchanged=($LASTEXITCODE -eq 0 -and (Get-TrihaHash $preparedPath) -eq $preparedHash)
    foreach($path in $toolHashes.Keys){if((Get-TrihaHash $path) -ne $toolHashes[$path]){$row.source_unchanged=$false}}
    if(-not $row.source_unchanged){$row.status='FAIL';$row.timing_closed=$false;$row.error='Frozen inputs changed.'}
    foreach($file in Get-ChildItem -LiteralPath $work -File -Recurse){
        if($file.FullName -ne $result){$row.output_hashes[[IO.Path]::GetRelativePath($work,$file.FullName).Replace('\','/')]=Get-TrihaHash $file.FullName}
    }
    $row.runner_return_code=if($row.flow_status -eq 'PASS' -and $row.source_unchanged){if($row.timing_closed){0}else{2}}else{1}
    $row['finished_utc']=[DateTime]::UtcNow.ToString('o')
    Save-TrihaJson $result $row
    Write-Host "DUAL_ROUTE $($row.status) result=$result"
}
exit $row.runner_return_code

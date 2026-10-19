#requires -Version 7.0
[CmdletBinding()]
param([string] $PdsShell='D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe', [switch] $Compact, [switch] $SingleClockRegion, [switch] $IoRegisters)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'firmware_common.ps1')
. (Join-Path $PSScriptRoot 'pds_reports.ps1')
. (Join-Path $PSScriptRoot 'route_reports.ps1')
if(([int][bool]$Compact+[int][bool]$SingleClockRegion+[int][bool]$IoRegisters) -gt 1){throw 'Choose only one physical recipe.'}
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if($env:TRIHA_PDS_SHELL){$PdsShell=$env:TRIHA_PDS_SHELL}
$work=Join-Path $root ('build/cpu/route-single-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
[IO.Directory]::CreateDirectory($work)|Out-Null
$commands=[Collections.Generic.List[object]]::new()
$result=[ordered]@{schema_version=1;status='RUNNING';flow_status='RUNNING';timing_closed=$false
    directory=$work;started_utc=[DateTime]::UtcNow.ToString('o');input_hashes=[ordered]@{};output_hashes=[ordered]@{}
    native_commands=$commands;source_unchanged=$false;error=$null;timing=$null;runner_return_code=$null
    scope='CPU-only isolation route; assumed I/O budget; automatic I/O placement, no board acceptance'
    board_validated=$false;bitstream_generated=$false}
$resultPath=Join-Path $work 'result.json'
Save-TrihaJson $resultPath $result
$timer=[Diagnostics.Stopwatch]::StartNew()
Write-Host "CPU_ROUTE_RUN directory=$work"
try {
    Assert-TrihaAdaptation $root
    $recipeName=if($IoRegisters){'fpga/pg2l100h/project/cpu_route_single_clock_io.json'}elseif($SingleClockRegion){'fpga/pg2l100h/project/cpu_route_single_clock.json'}elseif($Compact){'fpga/pg2l100h/project/cpu_route_compact.json'}else{'fpga/pg2l100h/project/cpu_route.json'}
    $recipe=Get-Content (Join-Path $root $recipeName) -Raw|ConvertFrom-Json
    $core=Get-Content (Join-Path $root $recipe.core_manifest) -Raw|ConvertFrom-Json
    if($recipe.dual_issue -ne 0 -or $recipe.period_ns -ne 10 -or $core.top -ne 'triha_core'){throw 'Unexpected route configuration.'}
    $result['boundary']=$recipe
    $physicalFiles=if('physical_constraints' -in $recipe.PSObject.Properties.Name){@($recipe.physical_constraints)}else{@()}
    $names=@($core.sources)+@($core.headers)+$physicalFiles+@($recipeName,$recipe.core_manifest,$recipe.constraints,
        'rtl/cpu/ADAPTATIONS.json','rtl/cpu/vendor/UPSTREAM.json','scripts/cpu/run_route.ps1',
        'scripts/cpu/route_reports.ps1','scripts/cpu/pds_reports.ps1','scripts/cpu/firmware_common.ps1')
    foreach($name in $names) {
        if([IO.Path]::IsPathRooted($name) -or $name.Contains('..')){throw 'Unsafe route input.'}
        $source=Join-Path $root $name;$destination=Join-Path $work ('src/'+$name)
        $result.input_hashes[$name]=Get-TrihaHash $source
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))|Out-Null
        [IO.File]::Copy($source,$destination)
        if((Get-TrihaHash $destination) -ne $result.input_hashes[$name]){throw 'Snapshot hash mismatch.'}
    }
    function TclPath([string] $Path){'{'+$Path.Replace('\','/')+'}'}
    $lines=@("set_arch -family $($core.family) -device $($core.device) -speedgrade $($core.speedgrade) -package $($core.package)")
    foreach($name in $core.sources){$lines+='add_design '+(TclPath (Join-Path $work ('src/'+$name)))}
    $lines+='add_constraint '+(TclPath (Join-Path $work ('src/'+$recipe.constraints)))
    foreach($name in $physicalFiles){$lines+='add_constraint '+(TclPath (Join-Path $work ('src/'+$name)))}
    $include=TclPath (Join-Path $work ('src/'+$core.include_directory))
    $lines+="compile -top_module triha_core -include_path {$include} -defined_parameters {DUAL_ISSUE 0}"
    $lines+='synthesize -ads -write_verilog TRUE'
    $lines+='dev_map -detail'
    $lines+="pnr -action_timeout $($recipe.pnr_action_minutes) -optimize_multi_corner_timing -fix_hold_violation -gplace_seed 1 -dump_router_congestion_plot TRUE"
    $lines+='report_timing -max_path 20'
    $script=Join-Path $work 'build.tcl'
    [IO.File]::WriteAllText($script,($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
    $result['pds_shell_sha256']=Get-TrihaHash $PdsShell
    $result['pds_version']=(Invoke-TrihaNative -Executable $PdsShell -CommandArguments @('-version') -RunDirectory $work -Label 'version' -Records $commands).Trim()
    $output=Invoke-TrihaNative -Executable $PdsShell -CommandArguments @('-file',$script,'-work_dir',$work,'-project_name','cpu_route') -RunDirectory $work -Label 'pds' -Records $commands -TimeoutSeconds $recipe.outer_seconds
    Assert-TrihaPdsStages $output 'map'
    foreach($stage in @('pnr','report_timing')) {
        if($output -notmatch ('(?m)^Executing : '+$stage+'(?: [^\r\n]*)? successfully\.\s*$')){throw "Missing actual route stage: $stage"}
    }
    $result['elaborated_configuration']=Assert-TrihaPdsConfiguration ([IO.File]::ReadAllText((Join-Path $work 'compile/run.log'))) 0 1 1
    $unconstrained=@([regex]::Matches($output,"(?m)^W: Timing-408[67]: Port '([^']+)' is not constrained.*$")|Where-Object {$_.Groups[1].Value -ne 'clk_i'})
    if($unconstrained.Count -ne 0){throw 'A functional CPU port is missing timing constraints.'}
    $report=Join-Path $work 'report_timing/triha_core.rtr'
    $result['timing_report']=$report
    $result.timing=Get-TrihaRouteTiming ([IO.File]::ReadAllText($report))
    $result['mapped_resources']=Get-TrihaPdsMappedResources ([IO.File]::ReadAllText((Join-Path $work 'device_map/triha_core.dmr')))
    $result.flow_status='PASS';$result.timing_closed=$result.timing.met
    $result.status=if($result.timing_closed){'PASS'}else{'TIMING_FAIL'}
} catch {$result.status='FAIL';$result.flow_status='FAIL';$result.error=$_.Exception.Message}
finally {
    $result.source_unchanged=$true
    foreach($name in $result.input_hashes.Keys){if((Get-TrihaHash (Join-Path $root $name)) -ne $result.input_hashes[$name]){$result.source_unchanged=$false}}
    if(-not $result.source_unchanged){$result.status='FAIL';$result.timing_closed=$false;$result.error='Route inputs changed.'}
    foreach($file in Get-ChildItem -LiteralPath $work -File -Recurse){if($file.FullName -ne $resultPath){$result.output_hashes[[IO.Path]::GetRelativePath($work,$file.FullName).Replace('\','/')]=Get-TrihaHash $file.FullName}}
    $result.runner_return_code=if($result.status -eq 'PASS'){0}elseif($result.status -eq 'TIMING_FAIL'){2}else{1}
    $result['finished_utc']=[DateTime]::UtcNow.ToString('o');$result['elapsed_seconds']=[Math]::Round($timer.Elapsed.TotalSeconds,3)
    Save-TrihaJson $resultPath $result
    Write-Host "CPU_ROUTE $($result.status) result=$resultPath"
    if($result.error){Write-Host $result.error}
}
exit $result.runner_return_code

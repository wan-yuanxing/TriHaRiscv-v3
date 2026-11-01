#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $FirmwareRunDirectory,
    [Parameter(Mandatory)][string] $ClockRunDirectory,
    [ValidateSet('system','coremark')][string] $FirmwareTest='system',
    [string] $PdsShell='D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe',
    [ValidateRange(1,16)][int] $PlacementSeed=1,
    [ValidateRange(1,20)][int] $HoldFixIterations=5
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../cpu/firmware_common.ps1')
. (Join-Path $PSScriptRoot '../cpu/pds_reports.ps1')
. (Join-Path $PSScriptRoot '../cpu/route_reports.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if($env:TRIHA_PDS_SHELL){$PdsShell=$env:TRIHA_PDS_SHELL}
$work=Join-Path $root ('build/soc/board-route-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
[IO.Directory]::CreateDirectory($work)|Out-Null
$commands=[Collections.Generic.List[object]]::new()
$privateTemp=Join-Path $work 'native-temp'
[IO.Directory]::CreateDirectory($privateTemp)|Out-Null
$env:TEMP=$privateTemp;$env:TMP=$privateTemp
$result=[ordered]@{schema_version=1;status='RUNNING';flow_status='RUNNING';timing_closed=$false
    directory=$work;input_hashes=[ordered]@{};evidence_hashes=[ordered]@{};output_hashes=[ordered]@{}
    native_commands=$commands;source_unchanged=$false;error=$null;timing=$null;runner_return_code=$null
    scope='CPU board PLL/pins post-route and bitstream; not programmed or physically tested'
    placement_seed=$PlacementSeed;hold_fix_iterations=$HoldFixIterations;board_validated=$false;programmed=$false;bitstream_generated=$false
    started_utc=[DateTime]::UtcNow.ToString('o')}
$resultPath=Join-Path $work 'result.json'
Save-TrihaJson $resultPath $result
$timer=[Diagnostics.Stopwatch]::StartNew()
Write-Host "CPU_BOARD_ROUTE_RUN directory=$work"
try {
    Assert-TrihaAdaptation $root
    foreach($item in @(@('system',$FirmwareRunDirectory),@('clocks',$ClockRunDirectory))){
        $directory=(Resolve-Path -LiteralPath $item[1]).Path
        $evidencePath=Join-Path $directory 'result.json'
        $evidence=Get-Content -LiteralPath $evidencePath -Raw|ConvertFrom-Json
        $expectedTest=if($item[0] -eq 'system'){$FirmwareTest}else{'clocks'}
        if($evidence.status -ne 'PASS' -or $evidence.test -ne $expectedTest -or $evidence.fault -ne 'none' -or
           -not $evidence.source_unchanged -or -not $evidence.external_unchanged -or $evidence.runner_return_code -ne 0){
            throw 'Need unchanged passing actual board clocks and system simulation.'
        }
        if($expectedTest -eq 'coremark'){
            if(-not $evidence.short_simulation_passed -or $evidence.release_iterations -ne 5000 -or
               $evidence.preflight_iterations -ne 5 -or $evidence.full_run_simulated -or
               (Get-TrihaHash (Join-Path $directory 'firmware.elf')) -ne $evidence.deployment_firmware_sha256 -or
               (Get-TrihaHash (Join-Path $directory 'sram.hex')) -ne $evidence.deployment_sram_sha256){
                throw 'CoreMark release/preflight binding failed.'
            }
        }
        foreach($entry in $evidence.input_hashes.PSObject.Properties){
            if((Get-TrihaHash (Join-Path $root $entry.Name)) -ne $entry.Value){throw "Validation source drift: $($entry.Name)"}
        }
        foreach($entry in $evidence.external_hashes.PSObject.Properties){
            if((Get-TrihaHash $entry.Name) -ne $entry.Value){throw "Validation tool/model drift: $($entry.Name)"}
        }
        $result.evidence_hashes[$evidencePath]=Get-TrihaHash $evidencePath
        foreach($entry in $evidence.output_hashes.PSObject.Properties){
            $path=Join-Path $directory $entry.Name
            if((Get-TrihaHash $path) -ne $entry.Value){throw "Validation output drift: $path"}
            $result.evidence_hashes[$path]=$entry.Value
        }
        $result[$item[0]+'_directory']=$directory
    }
    $result['firmware_profile']=$FirmwareTest
    if($FirmwareTest -eq 'coremark'){
        $software=Get-Content (Join-Path $result.system_directory 'result.json') -Raw|ConvertFrom-Json
        if($software.optimization -ne '-O2' -or $software.cpu_core_luts -le 0){throw 'Need O2 CoreMark with bound CPU-only LUT count.'}
        $result['cpu_core_luts_expected']=[int]$software.cpu_core_luts
    }
    foreach($name in @('rom.hex','sram.hex','firmware.elf')){
        [IO.File]::Copy((Join-Path $result.system_directory $name),(Join-Path $work $name))
    }
    $pllSource=Join-Path $result.clocks_directory 'ip/cpu_board_pll.v'
    [IO.Directory]::CreateDirectory((Join-Path $work 'ip'))|Out-Null
    [IO.File]::Copy($pllSource,(Join-Path $work 'ip/cpu_board_pll.v'))
    $recipeName='fpga/pg2l100h/project/cpu_board.json'
    $recipe=Get-Content (Join-Path $root $recipeName) -Raw|ConvertFrom-Json
    $core=Get-Content (Join-Path $root $recipe.core_manifest) -Raw|ConvertFrom-Json
    $soc=Get-Content (Join-Path $root $recipe.soc_manifest) -Raw|ConvertFrom-Json
    if($recipe.period_ns -ne 10 -or $recipe.top -ne 'triha_cpu_board_top'){throw 'Wrong board route recipe.'}
    if($recipe.PSObject.Properties.Name -contains 'refineplacement_iterations'){
        if($recipe.refineplacement_iterations -lt 10 -or $recipe.refineplacement_iterations -gt 50){
            throw 'PDS RefinePlacement Iteration must be within 10..50.'
        }
    }
    $names=@($core.sources)+@($core.headers)+@($soc.sources)+@($soc.headers)+@($recipe.sources)+@($recipe.physical_constraints)+@(
        $recipeName,$recipe.core_manifest,$recipe.soc_manifest,$recipe.constraints,'config/cpu_board.json','config/soc_map.json',
        'rtl/cpu/ADAPTATIONS.json','rtl/cpu/vendor/UPSTREAM.json','scripts/soc/run_dual_board_route.ps1',
        'scripts/soc/gen_board.py',
        'fpga/pg2l100h/constraints/video_ddr_bist.fdc','fpga/pg2l100h/ip/video_reference_manifest.json',
        'scripts/cpu/route_reports.ps1','scripts/cpu/pds_reports.ps1','scripts/cpu/firmware_common.ps1')
    foreach($name in $names|Select-Object -Unique){
        if([IO.Path]::IsPathRooted($name) -or $name.Contains('..')){throw 'Unsafe route input.'}
        $source=Join-Path $root $name;$target=Join-Path $work ('src/'+$name)
        $result.input_hashes[$name]=Get-TrihaHash $source
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target))|Out-Null
        [IO.File]::Copy($source,$target)
        if((Get-TrihaHash $target) -ne $result.input_hashes[$name]){throw 'Snapshot drift.'}
    }
    function TclPath([string] $Path){'{'+$Path.Replace('\','/')+'}'}
    $lines=@("set_arch -family $($core.family) -device $($core.device) -speedgrade $($core.speedgrade) -package $($core.package)")
    foreach($name in @($core.sources)+@($soc.sources)+@($recipe.sources)){
        $lines+='add_design '+(TclPath (Join-Path $work ('src/'+$name)))
    }
    $lines+='add_design '+(TclPath (Join-Path $work 'ip/cpu_board_pll.v'))
    $lines+='add_constraint '+(TclPath (Join-Path $work ('src/'+$recipe.constraints)))
    foreach($name in @($recipe.physical_constraints)){$lines+='add_constraint '+(TclPath (Join-Path $work ('src/'+$name)))}
    $includes=@($core.include_directory,'rtl/soc/include')|ForEach-Object {TclPath (Join-Path $work ('src/'+$_))}
    $lines+='compile -top_module triha_cpu_board_top -include_path {'+($includes -join ' ')+'}'
    $lines+='synthesize -ads -write_verilog TRUE'
    $lines+='dev_map -detail'
    $route="pnr -action_timeout $($recipe.pnr_action_minutes) -optimize_multi_corner_timing -fix_hold_violation -fix_hold_violation_iterations $HoldFixIterations -gplace_seed $PlacementSeed -dump_router_congestion_plot TRUE"
    if($recipe.slack_prior_in_global_router){$route+=' -slack_prior_in_global_router TRUE'}
    if($recipe.PSObject.Properties.Name -contains 'refineplacement_iterations'){
        $route+=" -refineplacement_iteration $($recipe.refineplacement_iterations)"
    }
    if($recipe.placement_trials -gt 1){
        $route+=" -gplace_times $($recipe.placement_trials) -seed_step 1 -saved_outcome 1 -parallel $($recipe.placement_parallelism)"
    }
    if($recipe.route_constraint_iterations -gt 0){
        $route+=" -enable_route_constraint_iterate -route_constraint_iterate_times $($recipe.route_constraint_iterations) -route_constraint_slack 0.200 -route_constraint_max_timing_path 20"
    }
    if($recipe.PSObject.Properties.Name -contains 'lut6d_packing_strategy'){
        if($recipe.lut6d_packing_strategy -lt 0 -or $recipe.lut6d_packing_strategy -gt 3){throw 'PDS LUT6D packing strategy must be within 0..3.'}
        $route+=" -logic_optimize_lut6d_combing_strategy $($recipe.lut6d_packing_strategy)"
    }
    if($recipe.PSObject.Properties.Name -contains 'route_mode'){
        if($recipe.route_mode -notin @('normal','performance')){throw 'Unsupported board routing mode.'}
        $route+=" -mode $($recipe.route_mode)"
    }
    if($recipe.PSObject.Properties.Name -contains 'placement_decongestion'){
        if($recipe.placement_decongestion -lt 0 -or $recipe.placement_decongestion -gt 9){throw 'PDS placement decongestion must be within 0..9.'}
        $route+=" -plc_decongestion $($recipe.placement_decongestion)"
    }
    $lines+=$route
    $lines+='report_timing -max_path 20'
    $script=Join-Path $work 'build.tcl'
    [IO.File]::WriteAllText($script,($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
    $result['pds_shell_sha256']=Get-TrihaHash $PdsShell
    $result['pds_version']=(Invoke-TrihaNative -Executable $PdsShell -CommandArguments @('-version') -RunDirectory $work -Label 'pds-version' -Records $commands).Trim()
    $output=Invoke-TrihaNative -Executable $PdsShell -CommandArguments @('-file',$script,'-work_dir',$work,'-project_name','cpu_board') -RunDirectory $work -Label 'pds-board' -Records $commands -TimeoutSeconds $recipe.outer_seconds
    Assert-TrihaPdsStages $output 'map'
    foreach($stage in @('pnr','report_timing')){
        if($output -notmatch ('(?m)^Executing : '+$stage+'(?: [^\r\n]*)? successfully\.\s*$')){throw "Missing route stage: $stage"}
    }
    $compileText=[IO.File]::ReadAllText((Join-Path $work 'compile/run.log'))
    $result['elaborated_cpu_configuration']=Assert-TrihaPdsConfiguration ($compileText.Replace('triha_cpu_board_top/u_soc/u_core','triha_core')) 1 1 1
    $result['elaborated_predictor_configuration']=Assert-TrihaPdsPredictorConfiguration ($compileText.Replace('triha_cpu_board_top/u_soc/u_core','triha_core'))
    foreach($scope in @('triha_cpu_board_top/u_soc/u_core/u_cpu','triha_cpu_board_top/u_soc/u_core/u_cpu/u_issue')){
        $blocks=[regex]::Matches($compileText,'(?ms)^I: Module instance \{'+[regex]::Escape($scope)+'\} parameter value:\r?\n(.*?)(?=^I:|\z)')
        if($blocks.Count -ne 1){throw 'Missing/duplicate early-MUL elaborated scope.'}
        $values=[regex]::Matches($blocks[0].Groups[1].Value,"(?m)^\s*EARLY_MUL_BYPASS = (1|32)'b([01]+)\s*$")
        if($values.Count -ne 1 -or [Convert]::ToUInt32($values[0].Groups[2].Value,2) -ne 1){throw 'Early-MUL bypass was not actually enabled.'}
    }
    $result['early_mul_bypass']=$true
    $result.elaborated_cpu_configuration['EARLY_MUL_BYPASS']=1
    $cpuRows=[regex]::Matches([IO.File]::ReadAllText((Join-Path $work 'synthesize/triha_cpu_board_top.snr')),'(?m)^\|[ +]*u_core\s+\|\s+(\d+)\s+\|')
    if($cpuRows.Count -ne 1){throw 'Missing/duplicate CPU hierarchy LUT count.'}
    $result['cpu_core_luts_actual']=[int]$cpuRows[0].Groups[1].Value
    if($FirmwareTest -eq 'coremark' -and $result.cpu_core_luts_actual -ne $result.cpu_core_luts_expected){
        throw 'CPU-only LUT count changed; rebuild UART metric against this actual report.'
    }
    $unconstrained=@([regex]::Matches($output,"(?m)^W: Timing-408[67]: Port '([^']+)' is not constrained.*$")|Where-Object {$_.Groups[1].Value -notin @('ref_clk_pi','ref_clk_ni')})
    if($unconstrained.Count -ne 0){throw 'A functional board port lacks timing constraints.'}
    $report=Join-Path $work 'report_timing/triha_cpu_board_top.rtr'
    $result['timing_report']=$report
    $result.timing=Get-TrihaRouteTiming ([IO.File]::ReadAllText($report))
    $result['mapped_system_resources']=Get-TrihaPdsMappedResources ([IO.File]::ReadAllText((Join-Path $work 'device_map/triha_cpu_board_top.dmr')))
    if($result.mapped_system_resources.drm -lt 8){throw 'SRAM did not map to native memory.'}
    $result.flow_status='PASS';$result.timing_closed=$result.timing.met
    if($result.timing_closed){
        # PDS parses Tcl before executing queued stages. Inspect the completed
        # report in the host, then request bitstream in a separate invocation.
        $bitScript=Join-Path $work 'bitstream.tcl'
        $bestSeeds=[regex]::Matches($output,'The Best Seed is (\d+)\.')
        $routedDb=if($bestSeeds.Count -eq 1){Join-Path $work ("place_route/seed_$($bestSeeds[0].Groups[1].Value)/triha_cpu_board_top_pnr.adf")}else{Join-Path $work 'place_route/triha_cpu_board_top_pnr.adf'}
        $result['bitstream_input_db']=$routedDb
        $result['bitstream_input_db_sha256']=Get-TrihaHash $routedDb
        $bitLines=@("set_arch -family $($core.family) -device $($core.device) -speedgrade $($core.speedgrade) -package $($core.package)",
            ('gen_bit_stream -force_to_run -input_db_file '+(TclPath $routedDb)+' -scbv {High Voltage}'))
        [IO.File]::WriteAllText($bitScript,($bitLines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
        $bitOutput=Invoke-TrihaNative -Executable $PdsShell -CommandArguments @('-file',$bitScript,'-work_dir',$work,'-project_name','cpu_board') -RunDirectory $work -Label 'pds-bitstream' -Records $commands -TimeoutSeconds 180
        if($bitOutput -match '(?im)^\s*(E:|ERROR[: ]|FATAL[: ])' -or $bitOutput -notmatch '(?m)^Executing : gen_bit_stream(?: [^\r\n]*)? successfully\.\s*$'){throw 'Bitstream tool error or missing success.'}
        foreach($suffix in @('sbit','smsk')){
            $path=Join-Path $work ('generate_bitstream/triha_cpu_board_top.'+$suffix)
            if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing bitstream/verify mask $suffix"}
        }
        $result.bitstream_generated=$true;$result.status='PASS'
    } else {$result.status='TIMING_FAIL'}
} catch {$result.status='FAIL';$result.flow_status='FAIL';$result.error=$_.Exception.Message}
finally {
    $result.source_unchanged=$true
    foreach($name in $result.input_hashes.Keys){if((Get-TrihaHash (Join-Path $root $name)) -ne $result.input_hashes[$name]){$result.source_unchanged=$false}}
    foreach($name in $result.evidence_hashes.Keys){if((Get-TrihaHash $name) -ne $result.evidence_hashes[$name]){$result.source_unchanged=$false}}
    if(-not $result.source_unchanged){$result.status='FAIL';$result.timing_closed=$false;$result.error='Board route inputs changed.'}
    foreach($file in Get-ChildItem -LiteralPath $work -File -Recurse){if($file.FullName -ne $resultPath){$result.output_hashes[[IO.Path]::GetRelativePath($work,$file.FullName).Replace('\','/')]=Get-TrihaHash $file.FullName}}
    $result.runner_return_code=if($result.status -eq 'PASS'){0}elseif($result.status -eq 'TIMING_FAIL'){2}else{1}
    $result['finished_utc']=[DateTime]::UtcNow.ToString('o');$result['elapsed_seconds']=[Math]::Round($timer.Elapsed.TotalSeconds,3)
    Save-TrihaJson $resultPath $result
    Write-Host "CPU_BOARD_ROUTE $($result.status) result=$resultPath"
    if($result.error){Write-Host $result.error}
}
exit $result.runner_return_code

#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string] $FirmwareRunDirectory,
    [string] $PdsShell='D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'firmware_common.ps1')
. (Join-Path $PSScriptRoot 'pds_reports.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$work=Join-Path $root ('build/cpu/ddr-map-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
[IO.Directory]::CreateDirectory($work)|Out-Null
$commands=[Collections.Generic.List[object]]::new()
$result=[ordered]@{status='RUNNING';stage='map';input_hashes=[ordered]@{};external_hashes=[ordered]@{}
    output_hashes=[ordered]@{};firmware_hashes=[ordered]@{};native_commands=$commands
    source_unchanged=$false;external_unchanged=$false;pinned_unchanged=$false
    timing_closed=$false;programmed=$false;runner_return_code=$null
    scope='CPU+local memory+paired Cache+CDC+DDR bridge native area; excludes scan fixture; not timing, physical DDR or board acceptance'}
$resultPath=Join-Path $work 'result.json'
Save-TrihaJson $resultPath $result
Write-Host "CPU_DDR_PDS_RUN directory=$work"
$timer=[Diagnostics.Stopwatch]::StartNew()
try {
    Assert-TrihaAdaptation $root
    $python=(Get-Command python -ErrorAction Stop).Source
    $result.external_hashes[$python]=Get-TrihaHash $python
    $bindingText=Invoke-TrihaNative -Executable $python -CommandArguments @((Join-Path $root 'scripts/cpu/prepare_ddr.py'),'--directory',$work) -RunDirectory $work -Label 'binding' -Records $commands
    $binding=$bindingText|ConvertFrom-Json
    $result['binding']=$binding
    $result.external_hashes[$binding.git]=$binding.git_sha256
    $firmware=(Resolve-Path -LiteralPath $FirmwareRunDirectory).Path
    $fw=Get-Content -LiteralPath (Join-Path $firmware 'result.json') -Raw|ConvertFrom-Json
    if($fw.status -ne 'PASS' -or $fw.test -ne 'system' -or $fw.fault -ne 'none' -or -not $fw.cache_enable -or
       -not $fw.source_unchanged -or -not $fw.external_unchanged -or -not $fw.pinned_unchanged -or $fw.runner_return_code -ne 0){throw 'Need passing CPU100/DDR125 system execution.'}
    foreach($entry in $fw.input_hashes.PSObject.Properties){
        if((Get-TrihaHash (Join-Path $root $entry.Name)) -ne $entry.Value){throw "System source drift: $($entry.Name)"}
    }
    foreach($file in @('rom.hex','sram.hex','firmware.elf','result.json')){
        $source=Join-Path $firmware $file;$digest=Get-TrihaHash $source
        if($file -ne 'result.json' -and $digest -ne $fw.output_hashes.$file){throw 'Firmware output drift.'}
        $result.firmware_hashes[$source]=$digest
        [IO.File]::Copy($source,(Join-Path $work $(if($file -eq 'result.json'){'firmware-result.json'}else{$file})))
    }
    $manifest='fpga/pg2l100h/project/cpu_ddr_map.json'
    $project=Get-Content -LiteralPath (Join-Path $root $manifest) -Raw|ConvertFrom-Json
    if($project.top -ne 'triha_cpu_ddr_map_top' -or $project.device -ne 'PG2L100H'){throw 'Wrong DDR area target.'}
    $files=@($project.sources)+@($project.headers)+@($project.constraints)+@($manifest,'config/cpu_ddr.json',
        'config/cpu_cache.json','config/cpu_cache_soc.json','config/soc_map.json','rtl/cpu/ADAPTATIONS.json',
        'rtl/cpu/CACHE_ADAPTATIONS.json','scripts/cpu/prepare_ddr.py','scripts/cpu/run_ddr_pds.ps1',
        'scripts/cpu/firmware_common.ps1','scripts/cpu/pds_reports.ps1')
    foreach($file in $files|Select-Object -Unique){
        if([IO.Path]::IsPathRooted($file) -or $file.Contains('..')){throw 'Unsafe DDR input.'}
        $source=Join-Path $root $file;$dest=Join-Path $work ('src/'+$file)
        $result.input_hashes[$file]=Get-TrihaHash $source
        [IO.Directory]::CreateDirectory((Split-Path -Parent $dest))|Out-Null
        [IO.File]::Copy($source,$dest)
    }
    function TclPath([string] $Path){'{'+$Path.Replace('\','/')+'}'}
    $lines=@("set_arch -family $($project.family) -device $($project.device) -speedgrade $($project.speedgrade) -package $($project.package)")
    foreach($file in $project.pinned_sources){$lines+='add_design '+(TclPath (Join-Path $work ('pinned/'+$file)))}
    foreach($file in $project.sources){$lines+='add_design '+(TclPath (Join-Path $work ('src/'+$file)))}
    foreach($file in $project.constraints){$lines+='add_constraint '+(TclPath (Join-Path $work ('src/'+$file)))}
    $includes=@($project.include_directories)|ForEach-Object {TclPath (Join-Path $work ('src/'+$_))}
    $lines+='compile -top_module triha_cpu_ddr_map_top -include_path {'+($includes -join ' ')+'}'
    $lines+=@('synthesize -ads -write_verilog TRUE','dev_map -detail')
    $script=Join-Path $work 'build.tcl'
    [IO.File]::WriteAllText($script,($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
    $result.external_hashes[$PdsShell]=Get-TrihaHash $PdsShell
    $result['tool_version']=Invoke-TrihaNative -Executable $PdsShell -CommandArguments @('-version') -RunDirectory $work -Label 'version' -Records $commands
    $output=Invoke-TrihaNative -Executable $PdsShell -CommandArguments @('-file',$script,'-work_dir',$work,'-project_name','cpu_ddr') -RunDirectory $work -Label 'pds' -Records $commands -TimeoutSeconds 600
    Assert-TrihaPdsStages $output 'map'
    $text=[IO.File]::ReadAllText((Join-Path $work 'synthesize/triha_cpu_ddr_map_top.snr'))
    $result['fixture_inclusive_resources']=Get-TrihaPdsResources $text
    if($result.fixture_inclusive_resources.latches -ne 0){throw 'Unexpected inferred latches.'}
    $result['hierarchy_resources']=[ordered]@{}
    foreach($instance in @('u_system','u_soc','u_core','u_cache','u_memory','u_cdc','u_bridge')){
        $matchesFound=[regex]::Matches($text,'(?m)^\|[ +]*'+[regex]::Escape($instance)+'\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+([\d.]+)')
        if($matchesFound.Count -ne 1){throw "Missing/duplicate DDR hierarchy: $instance"}
        $g=$matchesFound[0].Groups
        $result.hierarchy_resources[$instance]=[ordered]@{lut=[int]$g[1].Value;registers=[int]$g[2].Value;distributed_ram=[int]$g[3].Value;apm=[int]$g[4].Value;drm=[double]::Parse($g[5].Value,[Globalization.CultureInfo]::InvariantCulture)}
    }
    $result['mapped_fixture_inclusive_resources']=Get-TrihaPdsMappedResources ([IO.File]::ReadAllText((Join-Path $work 'device_map/triha_cpu_ddr_map_top.dmr')))
    $result.status='PASS'
} catch {$result.status='FAIL';$result['error']=$_.Exception.Message}
finally {
    $result.source_unchanged=$true;$result.external_unchanged=$true;$result.pinned_unchanged=$true
    foreach($file in $result.input_hashes.Keys){if((Get-TrihaHash (Join-Path $root $file)) -ne $result.input_hashes[$file]){$result.source_unchanged=$false}}
    foreach($file in $result.firmware_hashes.Keys){if((Get-TrihaHash $file) -ne $result.firmware_hashes[$file]){$result.source_unchanged=$false}}
    foreach($file in $result.external_hashes.Keys){if((Get-TrihaHash $file) -ne $result.external_hashes[$file]){$result.external_unchanged=$false}}
    if($result.Contains('binding')){foreach($entry in $result.binding.files.PSObject.Properties){if((Get-TrihaHash $entry.Value.path) -ne $entry.Value.sha256){$result.pinned_unchanged=$false}}}
    if(-not $result.source_unchanged -or -not $result.external_unchanged -or -not $result.pinned_unchanged){$result.status='FAIL';$result['error']='DDR mapping inputs changed.'}
    foreach($file in Get-ChildItem -LiteralPath $work -File -Recurse){if($file.FullName -ne $resultPath){$result.output_hashes[[IO.Path]::GetRelativePath($work,$file.FullName).Replace('\','/')]=Get-TrihaHash $file.FullName}}
    $result.runner_return_code=if($result.status -eq 'PASS'){0}else{1}
    $result['elapsed_seconds']=[Math]::Round($timer.Elapsed.TotalSeconds,3)
    Save-TrihaJson $resultPath $result
    Write-Host $result.status
    if($result.Contains('error')){Write-Host $result.error}
}
exit $result.runner_return_code

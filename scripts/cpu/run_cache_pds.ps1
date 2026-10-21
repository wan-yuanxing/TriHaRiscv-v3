#requires -Version 7.0
[CmdletBinding()]
param([ValidateSet('cache','cpu-cache','cpu-soc')][string] $Target='cache',
    [switch] $CacheBypass,
    [string] $FirmwareRunDirectory,
    [string] $PdsShell='D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'firmware_common.ps1')
. (Join-Path $PSScriptRoot 'pds_reports.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$work=Join-Path $root ('build/cpu/cache-map-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$commands=[Collections.Generic.List[object]]::new()
$result=[ordered]@{status='RUNNING';stage='map';directory=$work;input_hashes=[ordered]@{}
    external_hashes=[ordered]@{};output_hashes=[ordered]@{};native_commands=$commands
    source_unchanged=$false;external_unchanged=$false;resources=$null;primitive_usage=$null
    timing_closed=$false;programmed=$false;runner_return_code=$null
    scope='Paired I/D Cache and DDR transport only; excludes CPU; no routed timing or board acceptance'}
$resultPath=Join-Path $work 'result.json'
$result['target']=$Target
$result['cache_enable']=-not [bool]$CacheBypass
if($Target -eq 'cpu-cache'){$result.scope='CPU+I/D Cache+DDR transport; serial area fixture excluded; no routed timing or board acceptance'}
if($Target -eq 'cpu-soc'){$result.scope='Local CPU+ROM+SRAM+MMIO+I/D Cache+transport; serial area fixture excluded; no routed timing or board acceptance'}
Save-TrihaJson $resultPath $result
Write-Host "CPU_CACHE_PDS_RUN directory=$work"
$timer=[Diagnostics.Stopwatch]::StartNew()
try {
    $python=(Get-Command python -ErrorAction Stop).Source
    $result.external_hashes[$python]=Get-TrihaHash $python
    $validationText=Invoke-TrihaNative -Executable $python -CommandArguments @((Join-Path $root 'scripts/cpu/check_cache.py'),'--json') -RunDirectory $work -Label 'preflight' -Records $commands
    $cacheValidation=$validationText | ConvertFrom-Json
    if($cacheValidation.status -ne 'PASS'){throw 'Cache source/policy preflight failed.'}
    Assert-TrihaAdaptation $root
    $name=switch($Target){
        'cache' {'fpga/pg2l100h/project/cpu_cache.json'}
        'cpu-cache' {'fpga/pg2l100h/project/cpu_cached_core.json'}
        'cpu-soc' {'fpga/pg2l100h/project/cpu_cached_soc_map.json'}
    }
    $project=Get-Content -LiteralPath (Join-Path $root $name) -Raw | ConvertFrom-Json
    $expectedTop=switch($Target){'cache' {'triha_cache_map_top'} 'cpu-cache' {'triha_cached_core_map_top'} 'cpu-soc' {'triha_cached_soc_map_top'}}
    $areaInstance=switch($Target){'cache' {'u_cache'} 'cpu-cache' {'u_subsystem'} 'cpu-soc' {'u_system'}}
    if($project.top -ne $expectedTop -or $project.device -ne 'PG2L100H'){throw 'Wrong Cache target.'}
    $files=@($project.sources)+@($project.constraints)+@($name,'config/cpu_cache.json',
        'config/cpu_cache_sources.f','scripts/cpu/run_cache_pds.ps1','scripts/cpu/pds_reports.ps1',
        'scripts/cpu/firmware_common.ps1','rtl/cpu/vendor/CACHE_UPSTREAM.json','rtl/cpu/CACHE_ADAPTATIONS.json')
    $files+=@($cacheValidation.validated_paths)
    if($Target -ne 'cache'){$files+=@($project.headers)+@('rtl/cpu/ADAPTATIONS.json','fpga/pg2l100h/project/cpu_core.json')}
    if($Target -eq 'cpu-soc'){
        $files+=@('config/cpu_cache_soc.json','config/soc_map.json','scripts/cpu/gen_cache_soc.py')
        $firmware=(Resolve-Path -LiteralPath $FirmwareRunDirectory).Path
        $fw=Get-Content -LiteralPath (Join-Path $firmware 'result.json') -Raw|ConvertFrom-Json
        if($fw.status -ne 'PASS' -or $fw.test -ne 'runtime' -or $fw.fault -ne 'none' -or
            -not $fw.source_unchanged -or -not $fw.external_unchanged -or
            $fw.cache_enable -ne (-not [bool]$CacheBypass) -or $fw.runner_return_code -ne 0){throw 'Need matching successful Cache SoC firmware run.'}
        foreach($entry in $fw.input_hashes.PSObject.Properties){
            if((Get-TrihaHash (Join-Path $root $entry.Name)) -ne $entry.Value){throw "Firmware source drift: $($entry.Name)"}
        }
        $result['firmware_hashes']=[ordered]@{}
        foreach($file in @('rom.hex','sram.hex','firmware.elf','result.json')){
            $source=Join-Path $firmware $file
            $digest=Get-TrihaHash $source
            if($file -ne 'result.json' -and $digest -ne $fw.output_hashes.$file){throw 'Firmware output drift.'}
            $result.firmware_hashes[$source]=$digest
            [IO.File]::Copy($source,(Join-Path $work $(if($file -eq 'result.json'){'firmware-result.json'}else{$file})))
        }
    }
    foreach($file in $files){
        if($file.Contains('..') -or [IO.Path]::IsPathRooted($file)){throw 'Unsafe Cache input.'}
        $source=Join-Path $root $file
        $result.input_hashes[$file]=Get-TrihaHash $source
        $frozen=Join-Path $work ('src/'+$file)
        [IO.Directory]::CreateDirectory((Split-Path -Parent $frozen))|Out-Null
        [IO.File]::Copy($source,$frozen,$true)
    }
    function TclPath([string] $path){'{'+$path.Replace('\','/')+'}'}
    $lines=@("set_arch -family $($project.family) -device $($project.device) -speedgrade $($project.speedgrade) -package $($project.package)")
    foreach($file in $project.sources){$lines+='add_design '+(TclPath (Join-Path $work ('src/'+$file)))}
    foreach($file in $project.constraints){$lines+='add_constraint '+(TclPath (Join-Path $work ('src/'+$file)))}
    $compile="compile -top_module $($project.top)"
    if($Target -eq 'cpu-cache'){$compile+=' -include_path {{'+(Join-Path $work ('src/'+$project.include_directory)).Replace('\','/')+'}}'}
    if($Target -eq 'cpu-soc'){
        $includes=@($project.include_directories)|ForEach-Object {TclPath (Join-Path $work ('src/'+$_))}
        $compile+=' -include_path {'+($includes -join ' ')+'}'
    }
    if($Target -ne 'cache'){$compile+=' -defined_parameters {CACHE_ENABLE '+[int](-not [bool]$CacheBypass)+'}'}
    elseif($CacheBypass){throw 'Cache bypass area comparison requires CPU+Cache target.'}
    $lines+=@($compile,'synthesize -ads -write_verilog TRUE','dev_map -detail')
    $script=Join-Path $work 'build.tcl'
    [IO.File]::WriteAllText($script,($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
    $result.external_hashes[$PdsShell]=Get-TrihaHash $PdsShell
    $result['tool_version']=Invoke-TrihaNative -Executable $PdsShell -CommandArguments @('-version') -RunDirectory $work -Label 'version' -Records $commands
    $output=Invoke-TrihaNative -Executable $PdsShell -CommandArguments @('-file',$script,'-work_dir',$work,'-project_name','cpu_cache') -RunDirectory $work -Label 'pds' -Records $commands -TimeoutSeconds 600
    Assert-TrihaPdsStages $output 'map'
    $report=Join-Path $work "synthesize/$($project.top).snr"
    $text=[IO.File]::ReadAllText($report)
    $result['fixture_inclusive_resources']=Get-TrihaPdsResources $text
    $cacheRows=[regex]::Matches($text,'(?m)^\|[ +]*'+[regex]::Escape($areaInstance)+'\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+([\d.]+)')
    if($cacheRows.Count -ne 1){throw 'Missing or duplicate Cache-only hierarchy row.'}
    $groups=$cacheRows[0].Groups
    $result.resources=[ordered]@{lut=[int]$groups[1].Value;registers=[int]$groups[2].Value
        distributed_ram=[int]$groups[3].Value;apm=[int]$groups[4].Value
        drm=[double]::Parse($groups[5].Value,[Globalization.CultureInfo]::InvariantCulture)}
    if($Target -eq 'cpu-soc'){
        $result['hierarchy_resources']=[ordered]@{}
        foreach($instance in @('u_core','u_cache','u_memory')){
            $rows=[regex]::Matches($text,'(?m)^\|[ +]*'+[regex]::Escape($instance)+'\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+([\d.]+)')
            if($rows.Count -ne 1){throw "Missing/duplicate system area row: $instance"}
            $g=$rows[0].Groups
            $result.hierarchy_resources[$instance]=[ordered]@{lut=[int]$g[1].Value;registers=[int]$g[2].Value;distributed_ram=[int]$g[3].Value;apm=[int]$g[4].Value;drm=[double]::Parse($g[5].Value,[Globalization.CultureInfo]::InvariantCulture)}
        }
    }
    $result.primitive_usage=Get-TrihaPdsCells $text
    if($result.fixture_inclusive_resources.latches -ne 0 -or (-not $CacheBypass -and $result.resources.drm -lt 8) -or $result.resources.lut -le 0){throw 'Cache did not map to expected native memory or inferred latches.'}
    $result['mapped_fixture_inclusive_resources']=Get-TrihaPdsMappedResources ([IO.File]::ReadAllText((Join-Path $work "device_map/$($project.top).dmr")))
    $result.status='PASS'
} catch {
    $result.status='FAIL';$result['error']=$_.Exception.Message
} finally {
    $result.source_unchanged=$true
    foreach($file in $result.input_hashes.Keys){if((Get-TrihaHash (Join-Path $root $file)) -ne $result.input_hashes[$file]){$result.source_unchanged=$false}}
    $result.external_unchanged=$true
    foreach($file in $result.external_hashes.Keys){if((Get-TrihaHash $file) -ne $result.external_hashes[$file]){$result.external_unchanged=$false}}
    if($Target -eq 'cpu-soc' -and $result.Contains('firmware_hashes')){
        foreach($file in $result.firmware_hashes.Keys){if((Get-TrihaHash $file) -ne $result.firmware_hashes[$file]){$result.source_unchanged=$false}}
    }
    if(-not $result.source_unchanged -or -not $result.external_unchanged){$result.status='FAIL';$result['error']='Cache inputs changed during mapping.'}
    foreach($file in Get-ChildItem -LiteralPath $work -File -Recurse){
        if($file.FullName -ne $resultPath){$relative=[IO.Path]::GetRelativePath($work,$file.FullName).Replace('\','/');$result.output_hashes[$relative]=Get-TrihaHash $file.FullName}
    }
    $result.runner_return_code=if($result.status -eq 'PASS'){0}else{1}
    $result['elapsed_seconds']=[Math]::Round($timer.Elapsed.TotalSeconds,3)
    Save-TrihaJson $resultPath $result
}
Write-Host $result.status
exit $result.runner_return_code

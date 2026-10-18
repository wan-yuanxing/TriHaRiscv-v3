#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('single','dual','both')][string] $Mode = 'single',
    [ValidateSet('synth','map')][string] $Stage = 'synth',
    [string] $PdsShell = 'D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe',
    [ValidateRange(30,1800)][int] $ProcessTimeoutSeconds = 900
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'firmware_common.ps1')
. (Join-Path $PSScriptRoot 'pds_reports.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ($env:TRIHA_PDS_SHELL) { $PdsShell = $env:TRIHA_PDS_SHELL }
$modes = if ($Mode -eq 'both') { @('single','dual') } else { @($Mode) }
$accepted = $true
foreach ($selected in $modes) {
    $work = Join-Path $root ('build/cpu/pds-' + $selected + '-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
    [IO.Directory]::CreateDirectory($work) | Out-Null
    $commands = [Collections.Generic.List[object]]::new()
    $result = [ordered]@{
        schema_version=1;status='RUNNING';mode=$selected;stage=$Stage
        scope='CPU-only component; no test TCM or SoC; no physical timing acceptance'
        directory=$work;started_utc=[DateTime]::UtcNow.ToString('o')
        input_hashes=[ordered]@{};output_hashes=[ordered]@{};native_commands=$commands
        resources=$null;primitive_usage=$null;source_unchanged=$false;error=$null
        routed=$false;timing_closed=$false;board_validated=$false;runner_return_code=$null
    }
    $resultPath = Join-Path $work 'result.json'
    Save-TrihaJson $resultPath $result
    $timer = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "CPU_PDS_RUN mode=$selected stage=$Stage directory=$work"
    try {
        $manifestName = 'fpga/pg2l100h/project/cpu_core.json'
        $manifest = Get-Content -LiteralPath (Join-Path $root $manifestName) -Raw | ConvertFrom-Json
        if ($manifest.top -ne 'triha_core' -or $manifest.device -ne 'PG2L100H') { throw 'Wrong CPU top/device.' }
        $dual = [int]$manifest.modes.$selected
        if ($dual -ne [int]($selected -eq 'dual')) { throw 'Issue-width parameter mismatch.' }
        $result['dual_issue'] = $dual
        $result['device'] = "$($manifest.device)/$($manifest.package)/$($manifest.speedgrade)"
        $names = @($manifest.sources) + @($manifest.headers) + @($manifest.constraints) + @($manifestName,
            'scripts/cpu/run_pds.ps1','scripts/cpu/pds_reports.ps1','scripts/cpu/firmware_common.ps1',
            'rtl/cpu/vendor/UPSTREAM.json')
        foreach ($name in $names) {
            if ($name.Contains('..') -or [IO.Path]::IsPathRooted($name)) { throw 'Unsafe input path.' }
            $source = Join-Path $root $name
            $result.input_hashes[$name] = Get-TrihaHash $source
            $snapshot = Join-Path $work ('src/' + $name)
            [IO.Directory]::CreateDirectory((Split-Path -Parent $snapshot)) | Out-Null
            [IO.File]::Copy($source,$snapshot)
            if ((Get-TrihaHash $snapshot) -ne $result.input_hashes[$name]) { throw "Snapshot mismatch: $name" }
        }
        foreach ($name in $manifest.sources) {
            if (-not $name.StartsWith('rtl/cpu/') -or $name -match '/tb/|tcm_mem|trace_sim|xilinx') {
                throw "Non-core source in CPU-only target: $name"
            }
        }
        $vendor = Get-Content -LiteralPath (Join-Path $work 'src/rtl/cpu/vendor/UPSTREAM.json') -Raw | ConvertFrom-Json
        foreach ($name in @($manifest.sources) + @($manifest.headers)) {
            if ($name.StartsWith('rtl/cpu/vendor/')) {
                $key = $name.Substring('rtl/cpu/vendor/'.Length)
                if ($result.input_hashes[$name] -ne $vendor.files.$key) { throw "Vendor hash mismatch: $name" }
            }
        }
        function TclPath([string] $Path) { '{' + $Path.Replace('\','/') + '}' }
        $lines = @("set_arch -family $($manifest.family) -device $($manifest.device) -speedgrade $($manifest.speedgrade) -package $($manifest.package)")
        foreach ($name in $manifest.sources) { $lines += 'add_design ' + (TclPath (Join-Path $work ('src/' + $name))) }
        foreach ($name in $manifest.constraints) { $lines += 'add_constraint ' + (TclPath (Join-Path $work ('src/' + $name))) }
        $includePath = TclPath (Join-Path $work ('src/' + $manifest.include_directory))
        # PDS Generics use name/value pairs; '=' is for compiler directives.
        $lines += "compile -top_module triha_core -include_path {$includePath} -defined_parameters {DUAL_ISSUE $dual}"
        $lines += 'synthesize -ads -write_verilog TRUE'
        if ($Stage -eq 'map') { $lines += 'dev_map -detail' }
        $script = Join-Path $work 'build.tcl'
        [IO.File]::WriteAllText($script,($lines -join "`n") + "`n",[Text.UTF8Encoding]::new($false))
        $result['pds_shell_sha256'] = Get-TrihaHash $PdsShell
        $result['pds_version'] = (Invoke-TrihaNative -Executable $PdsShell -CommandArguments @('-version') `
            -RunDirectory $work -Label 'version' -Records $commands).Trim()
        $output = Invoke-TrihaNative -Executable $PdsShell `
            -CommandArguments @('-file',$script,'-work_dir',$work,'-project_name','cpu_core') `
            -RunDirectory $work -Label 'pds' -Records $commands -TimeoutSeconds $ProcessTimeoutSeconds
        Assert-TrihaPdsStages $output $Stage
        $compileText = [IO.File]::ReadAllText((Join-Path $work 'compile/run.log'))
        $result['elaborated_configuration'] = Assert-TrihaPdsConfiguration $compileText $dual
        $report = Join-Path $work 'synthesize/triha_core.snr'
        $text = [IO.File]::ReadAllText($report)
        $result.resources = Get-TrihaPdsResources $text
        $result.primitive_usage = Get-TrihaPdsCells $text
        if ($result.resources.latches -ne 0 -or $result.resources.registers -le 0 -or $result.resources.lut -le 0) {
            throw 'Unexpected latch, empty, or optimized-away CPU.'
        }
        if ($text -notmatch 'cpu_clk\s+10\.0000') { throw '100MHz synthesis clock was not applied.' }
        $result['synthesis_report'] = $report
        if ($Stage -eq 'map') {
            $mappedReport = Join-Path $work 'device_map/triha_core.dmr'
            $result['mapped_resources'] = Get-TrihaPdsMappedResources ([IO.File]::ReadAllText($mappedReport))
            $result['map_minus_synthesis'] = [ordered]@{}
            foreach ($key in $result.mapped_resources.Keys) {
                # Device mapping may remove/duplicate cells; report both stages.
                $result.map_minus_synthesis[$key] = $result.mapped_resources[$key] - $result.resources[$key]
            }
            if ($result.mapped_resources.lut -le 0 -or $result.mapped_resources.registers -le 0) {
                throw 'CPU disappeared during device mapping.'
            }
            $result['mapping_report'] = $mappedReport
        }
        $result['warnings'] = @([regex]::Matches($output,'(?m)^W:.*$') | ForEach-Object { $_.Value })
        $result.status = 'PASS'
    } catch {
        $result.status = 'FAIL'
        $result.error = $_.Exception.Message
    } finally {
        $unchanged = $true
        foreach ($name in $result.input_hashes.Keys) {
            if (-not (Test-Path -LiteralPath (Join-Path $root $name)) -or
                (Get-TrihaHash (Join-Path $root $name)) -ne $result.input_hashes[$name]) { $unchanged = $false }
        }
        $result.source_unchanged = $unchanged
        if (-not $unchanged) { $result.status='FAIL';$result.error='Inputs changed during PDS execution.' }
        foreach ($file in Get-ChildItem -LiteralPath $work -File -Recurse) {
            if ($file.FullName -ne $resultPath) {
                $relative = [IO.Path]::GetRelativePath($work,$file.FullName).Replace('\','/')
                $result.output_hashes[$relative] = Get-TrihaHash $file.FullName
            }
        }
        $result.runner_return_code = if ($result.status -eq 'PASS') { 0 } else { 1 }
        $result['finished_utc'] = [DateTime]::UtcNow.ToString('o')
        $result['elapsed_seconds'] = [Math]::Round($timer.Elapsed.TotalSeconds,3)
        Save-TrihaJson $resultPath $result
        Write-Host "CPU_PDS $($result.status) result=$resultPath"
        if ($result.error) { Write-Host $result.error }
        if ($result.status -ne 'PASS') { $accepted = $false }
    }
}
if ($accepted) { exit 0 } else { exit 1 }

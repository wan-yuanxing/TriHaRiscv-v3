#requires -Version 7.0
<#
    Windows-native ModelSim CPU smoke. Uses installed tools and a pinned ELF.
    All native commands run with a wall-clock bound in a fresh build directory.
#>
[CmdletBinding()]
param(
    [ValidateSet('single', 'dual', 'fail', 'timeout', 'all')]
    [string] $Case = 'all',
    [string] $ModelSimBin = 'D:/modeltech64_2020.4/win64',
    [ValidateRange(1, 300)]
    [int] $ProcessTimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'simulation_common.ps1')
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$vendorRoot = Join-Path $projectRoot 'rtl/cpu/vendor'
$buildRoot = Join-Path $projectRoot 'build/cpu'
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Write-JsonFile([string] $Path, $Value) {
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12) + "`n", $utf8)
}

function Get-Sha256([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Export-SmokeImage([string] $Destination) {
    $elfPath = Join-Path $vendorRoot 'tb/tb_core_icarus/test.elf'
    $elf = [System.IO.File]::ReadAllBytes($elfPath)
    if ($elf.Length -lt 52 -or $elf[0] -ne 127 -or $elf[1] -ne 69 -or
        $elf[2] -ne 76 -or $elf[3] -ne 70 -or $elf[4] -ne 1 -or $elf[5] -ne 1 -or
        [BitConverter]::ToUInt16($elf, 18) -ne 243 -or
        [BitConverter]::ToUInt32($elf, 24) -ne 2147483648) {
        throw 'Pinned smoke must be little-endian ELF32 RISC-V at 0x80000000.'
    }
    $image = [byte[]]::new(131072)
    $phOffset = [uint64][BitConverter]::ToUInt32($elf, 28)
    $phSize = [uint64][BitConverter]::ToUInt16($elf, 42)
    $phCount = [uint64][BitConverter]::ToUInt16($elf, 44)
    if ($phSize -lt 32 -or $phOffset + $phSize * $phCount -gt $elf.Length) {
        throw 'Invalid ELF program-header table.'
    }
    $loaded = 0
    for ($segment = 0; $segment -lt $phCount; $segment++) {
        $header = [int]($phOffset + $segment * $phSize)
        if ([BitConverter]::ToUInt32($elf, $header) -ne 1) { continue }
        $offset = [uint64][BitConverter]::ToUInt32($elf, $header + 4)
        $address = [uint64][BitConverter]::ToUInt32($elf, $header + 12)
        $fileSize = [uint64][BitConverter]::ToUInt32($elf, $header + 16)
        $memorySize = [uint64][BitConverter]::ToUInt32($elf, $header + 20)
        if ($address -lt 2147483648 -or $fileSize -gt $memorySize -or
            $offset + $fileSize -gt $elf.Length -or
            $address - 2147483648 + $memorySize -gt $image.Length) {
            throw "ELF load segment outside the test TCM: $segment"
        }
        [Buffer]::BlockCopy($elf, [int]$offset, $image,
            [int]($address - 2147483648), [int]$fileSize)
        $loaded++
    }
    if ($loaded -eq 0) { throw 'ELF has no loadable segments.' }
    [System.IO.File]::WriteAllBytes($Destination, $image)
}

function Invoke-CpuCase([string] $Name) {
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')
    $runRoot = Join-Path $buildRoot "$Name-$stamp"
    [System.IO.Directory]::CreateDirectory($runRoot) | Out-Null
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $nativeRecords = [System.Collections.Generic.List[object]]::new()
    $result = [ordered]@{
        status = 'RUNNING'; scope = 'pinned ELF smoke and issue observations'
        case = $Name; started_utc = [DateTime]::UtcNow.ToString('o')
        run_directory = $runRoot; tool_version = $null
        upstream_revision = $null; input_hashes = [ordered]@{}
        native_commands = $nativeRecords; output_hashes = [ordered]@{}
        error = $null; source_unchanged = $false; measurement = $null
        gcc_build_executed = $false; coremark_measured = $false
        retirement_correctness_proven = $false; soc_integrated = $false
        pds_executed = $false; board_validated = $false
    }
    $resultPath = Join-Path $runRoot 'result.json'
    Write-JsonFile $resultPath $result

    function Invoke-Native([string] $Name, [string[]] $Arguments, [string] $Label) {
        $executable = Join-Path $ModelSimBin "$Name.exe"
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            throw "Installed ModelSim executable not found: $executable"
        }
        $info = [System.Diagnostics.ProcessStartInfo]::new()
        $info.FileName = $executable
        $info.WorkingDirectory = $runRoot
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $info
        $record = [ordered]@{ tool = $executable; arguments = $Arguments
            return_code = $null; timed_out = $false }
        $nativeRecords.Add($record)
        try {
            $process.Start() | Out-Null
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit($ProcessTimeoutSeconds * 1000)) {
                $record.timed_out = $true
                $process.Kill($true)
                $process.WaitForExit()
            }
            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            [System.IO.File]::WriteAllText((Join-Path $runRoot "$Label.stdout.log"), $stdout, $utf8)
            [System.IO.File]::WriteAllText((Join-Path $runRoot "$Label.stderr.log"), $stderr, $utf8)
            $record.return_code = $process.ExitCode
            if ($record.timed_out) { throw "$Name exceeded $ProcessTimeoutSeconds seconds." }
            if ($process.ExitCode -ne 0) { throw "$Name returned $($process.ExitCode); see $Label logs." }
            return $stdout + $stderr
        } finally {
            $process.Dispose()
        }
    }

    try {
        $manifestPath = Join-Path $vendorRoot 'UPSTREAM.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $result.upstream_revision = $manifest.revision
        $result.input_hashes['rtl/cpu/vendor/UPSTREAM.json'] = Get-Sha256 $manifestPath
        foreach ($entry in $manifest.files.PSObject.Properties) {
            $relative = 'rtl/cpu/vendor/' + $entry.Name
            $actual = Get-Sha256 (Join-Path $projectRoot $relative)
            if ($actual -ne $entry.Value) { throw "Upstream hash mismatch: $relative" }
            $result.input_hashes[$relative] = $actual
        }
        $result['external_input_hashes']=[ordered]@{}
        $primitiveSources=@(Get-TrihaPrimitiveModels -Root $projectRoot -LocalHashes $result.input_hashes -ExternalHashes $result.external_input_hashes)
        $filelistPath = Join-Path $projectRoot 'config/cpu_sources.f'
        $sources = @(Get-Content -LiteralPath $filelistPath | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') })
        foreach ($relative in @($sources) + @('config/cpu_sources.f',
                'scripts/cpu/run.ps1', 'scripts/cpu/run_modelsim.do')) {
            $inputPath = Join-Path $projectRoot $relative
            $result.input_hashes[$relative] = if (Test-Path -LiteralPath $inputPath) {
                Get-Sha256 $inputPath
            } else { 'MISSING' }
        }
        $imagePath = Join-Path $runRoot 'tcm.bin'
        Export-SmokeImage $imagePath
        $version = Invoke-Native 'vsim' @('-version') 'version'
        $result.tool_version = $version.Trim()
        Invoke-Native 'vmap' @('-c') 'vmap' | Out-Null
        Invoke-Native 'vlib' @('work') 'vlib' | Out-Null
        $compileArguments = @('-work', 'work',
            ('+incdir+' + (Join-Path $vendorRoot 'src/core')))
        $compileArguments += @($sources | ForEach-Object { Join-Path $projectRoot $_ }) + $primitiveSources
        Invoke-Native 'vlog' $compileArguments 'compile' | Out-Null
        $dual = if ($Name -eq 'dual') { 1 } else { 0 }
        $programFail = if ($Name -eq 'fail') { 1 } else { 0 }
        $maxCycles = if ($Name -eq 'timeout') { 8 } else { 100000 }
        $simulateArguments = @('-c', '-onfinish', 'exit', '-t', '1ps',
            '-voptargs=+acc', "-gDUAL_ISSUE=$dual", "-gPROGRAM_FAIL=$programFail",
            "-gMAX_CYCLES=$maxCycles", 'work.tb_triha_core',
            ('+MEM_IMAGE=' + $imagePath.Replace('\', '/')),
            '-do', (Join-Path $projectRoot 'scripts/cpu/run_modelsim.do'))
        $output = Invoke-Native 'vsim' $simulateArguments 'simulation'
        if ($output -match 'CPU_SMOKE_FAIL reason=timeout') { throw 'RTL cycle timeout.' }
        $exitMatches = [regex]::Matches($output, '(?m)^(?:# )?CPU_PROGRAM_EXIT code=(\d+)\s*$')
        if ($exitMatches.Count -ne 1) { throw 'Missing or repeated real program exit.' }
        $result['program_exit_code'] = [int]$exitMatches[0].Groups[1].Value
        if ($result.program_exit_code -ne 0) { throw "Program exited with code $($result.program_exit_code)." }
        if ($output -match 'CPU_SMOKE_FAIL|\*\* (?:Error|Fatal)|Incorrect') {
            throw 'RTL or simulator reported a failure.'
        }
        $measurement = [regex]::Match($output,
            'CPU_SMOKE_PASS dual=(\d+) cycles=(\d+) issued=(\d+) pairs=(\d+)')
        if (-not $measurement.Success) { throw 'Missing CPU smoke completion marker.' }
        $result.measurement = [ordered]@{
            dual_issue = [int]$measurement.Groups[1].Value
            cycles = [int]$measurement.Groups[2].Value
            issued = [int]$measurement.Groups[3].Value
            paired_cycles = [int]$measurement.Groups[4].Value
            issued_is_not_instret = $true
        }
        if ($result.measurement.dual_issue -ne $dual -or $result.measurement.cycles -le 0 -or
            $result.measurement.issued -le 0 -or
            ($dual -eq 0 -and $result.measurement.paired_cycles -ne 0) -or
            ($dual -eq 1 -and $result.measurement.paired_cycles -le 0)) {
            throw 'Invalid issue observations.'
        }
        foreach ($marker in @('1. Initialised data', '2. Multiply', '3. Divide',
            '4. Shift left', '5. Shift right', '6. Shift right arithmetic',
            '7. Signed comparision', '8. Word access', '9. Byte access', '10. Comparision')) {
            if (-not $output.Contains($marker)) { throw "Missing upstream check output: $marker" }
        }
        $result.status = 'PASS'
    } catch {
        $result.status = 'FAIL'
        $result.error = $_.Exception.Message
    } finally {
        $unchanged = $true
        foreach ($relative in $result.input_hashes.Keys) {
            $inputPath = Join-Path $projectRoot $relative
            if ($result.input_hashes[$relative] -eq 'MISSING') {
                if (Test-Path -LiteralPath $inputPath) { $unchanged = $false }
            } elseif (-not (Test-Path -LiteralPath $inputPath) -or
                (Get-Sha256 $inputPath) -ne $result.input_hashes[$relative]) {
                $unchanged = $false
            }
        }
        if('external_input_hashes' -in $result.Keys -and -not (Test-TrihaPrimitiveHashes $result.external_input_hashes)){$unchanged=$false}
        $result.source_unchanged = $unchanged
        if (-not $unchanged) { $result.status = 'FAIL'; $result.error = 'Inputs changed during run.' }
        foreach ($file in Get-ChildItem -LiteralPath $runRoot -File -Filter '*.log') {
            $result.output_hashes[$file.Name] = Get-Sha256 $file.FullName
        }
        $imagePath = Join-Path $runRoot 'tcm.bin'
        if (Test-Path -LiteralPath $imagePath) { $result.output_hashes['tcm.bin'] = Get-Sha256 $imagePath }
        $result['finished_utc'] = [DateTime]::UtcNow.ToString('o')
        $result['elapsed_seconds'] = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
        $result['runner_return_code'] = if ($result.status -eq 'PASS') { 0 } else { 1 }
        Write-JsonFile $resultPath $result
        Write-Host "CPU_CASE $Name $($result.status) result=$resultPath"
        if ($result.error) { Write-Host $result.error }
    }
    return [pscustomobject]$result
}

[System.IO.Directory]::CreateDirectory($buildRoot) | Out-Null
if ($Case -ne 'all') {
    $caseResult = Invoke-CpuCase $Case
    exit $caseResult.runner_return_code
}
$allResults = @('single', 'dual', 'fail', 'timeout') | ForEach-Object { Invoke-CpuCase $_ }
$accepted = $allResults.Count -eq 4
foreach ($item in $allResults) {
    $expected = if ($item.case -in @('single', 'dual')) { 'PASS' } else { 'FAIL' }
    if ($item.status -ne $expected -or -not $item.source_unchanged) { $accepted = $false }
    if ($item.case -eq 'fail' -and ($item.error -ne 'Program exited with code 1.')) { $accepted = $false }
    if ($item.case -eq 'timeout' -and ($item.error -ne 'RTL cycle timeout.')) { $accepted = $false }
}
$summary = [ordered]@{
    status = if ($accepted) { 'PASS' } else { 'FAIL' }
    scope = 'two smoke modes plus actual failing-program and timeout rejection'
    recorded_utc = [DateTime]::UtcNow.ToString('o'); cases = $allResults
    coremark_measured = $false; pds_executed = $false; board_validated = $false
}
$summaryPath = Join-Path $buildRoot ('summary-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ') + '.json')
Write-JsonFile $summaryPath $summary
Write-Host "CPU_SUITE $($summary.status) summary=$summaryPath"
if ($accepted) { exit 0 } else { exit 1 }

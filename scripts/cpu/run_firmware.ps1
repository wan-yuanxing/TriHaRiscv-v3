#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('runtime','retire','coremark')][string] $Program = 'coremark',
    [ValidateSet('single','dual','both')][string] $Mode = 'single',
    [ValidateSet('performance','validation')][string] $RunKind = 'performance',
    [ValidateRange(1,1000000)][int] $Iterations = 5,
    [ValidateSet('none','crc','count','trap')][string] $Fault = 'none',
    [string] $ModelSimBin = 'D:/modeltech64_2020.4/win64',
    [ValidateRange(10,600)][int] $SimulationTimeoutSeconds = 180
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'firmware_common.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$runRoot = Join-Path $root ('build/cpu/firmware-' + $Program + '-' +
    [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
[IO.Directory]::CreateDirectory($runRoot) | Out-Null
$commands = [Collections.Generic.List[object]]::new()
$result = [ordered]@{
    schema_version=1;status='RUNNING';program=$Program;mode=$Mode;run_kind=$RunKind;fault=$Fault
    iterations=$Iterations;run_directory=$runRoot;started_utc=[DateTime]::UtcNow.ToString('o')
    input_hashes=[ordered]@{};output_hashes=[ordered]@{};native_commands=$commands
    source_unchanged=$false;compiler=$null;compiler_version=$null;compiler_flags=$null
    elf_sha256=$null;memory='128KiB test TCM; BSS poisoned before startup'
    executions=@();error=$null;runner_return_code=$null
    formal_coremark_score=$false;pds_executed=$false;board_validated=$false
    retirement_scope='WB completion events; directed probe, not complete architectural proof'
}
$timer = [Diagnostics.Stopwatch]::StartNew()
$resultPath = Join-Path $runRoot 'result.json'
Save-TrihaJson $resultPath $result
Write-Host "CPU_FIRMWARE_RUN program=$Program mode=$Mode directory=$runRoot"
function Native([string] $Exe, [string[]] $Arguments, [string] $Label, [int] $Timeout = 60) {
    Invoke-TrihaNative -Executable $Exe -CommandArguments $Arguments -RunDirectory $runRoot `
        -Label $Label -Records $commands -TimeoutSeconds $Timeout
}

try {
    if (($Fault -eq 'crc' -and $Program -ne 'coremark') -or
        ($Fault -eq 'count' -and $Program -ne 'retire') -or
        ($Fault -eq 'trap' -and $Program -ne 'runtime')) { throw 'Fault does not match the selected test.' }
    foreach ($manifestRelative in @('rtl/cpu/vendor/UPSTREAM.json','sw/benchmarks/coremark/UPSTREAM.json')) {
        $manifestPath = Join-Path $root $manifestRelative
        $result.input_hashes[$manifestRelative] = Get-TrihaHash $manifestPath
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $base = if ($manifestRelative.StartsWith('rtl/')) { 'rtl/cpu/vendor/' } else { 'sw/benchmarks/coremark/src/' }
        foreach ($entry in $manifest.files.PSObject.Properties) {
            $relative = $base + $entry.Name
            $actual = Get-TrihaHash (Join-Path $root $relative)
            if ($actual -ne $entry.Value) { throw "Source hash mismatch: $relative" }
            $result.input_hashes[$relative] = $actual
        }
    }
    $filelist = @(Get-Content (Join-Path $root 'config/cpu_sources.f') |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    $localInputs = @($filelist) + @('config/cpu_sources.f','config/cpu_toolchain.json',
        'scripts/cpu/run_firmware.ps1','scripts/cpu/firmware_common.ps1','scripts/cpu/run_modelsim.do',
        'sw/runtime/crt0.S','sw/runtime/triha_tcm.ld','sw/runtime/triha_runtime.h',
        'sw/runtime/triha_runtime.c','sw/tests/runtime_smoke.c','sw/tests/retire_probe.S',
        'sw/benchmarks/coremark/port/core_portme.h','sw/benchmarks/coremark/port/core_portme.c')
    foreach ($relative in $localInputs) { $result.input_hashes[$relative] = Get-TrihaHash (Join-Path $root $relative) }
    $config = Get-Content (Join-Path $root 'config/cpu_toolchain.json') -Raw | ConvertFrom-Json
    $gcc = if ($env:TRIHA_RISCV_GCC) { $env:TRIHA_RISCV_GCC } else { $config.compiler }
    $gccBin = Split-Path -Parent $gcc
    $result.compiler = $gcc
    $result['compiler_sha256'] = Get-TrihaHash $gcc
    $result.compiler_version = (Native $gcc @('--version') 'gcc-version').Trim()
    $flags = @('-march=rv32im_zicsr','-mabi=ilp32','-std=gnu99','-O3','-mcmodel=medany',
        '-mno-relax','-msmall-data-limit=0','-ffreestanding','-fno-builtin',
        '-ffunction-sections','-fdata-sections','-Wall','-Wextra','-Werror=implicit-function-declaration')
    $result.compiler_flags = $flags
    $library = (Native $gcc @('-march=rv32im_zicsr','-mabi=ilp32','-print-libgcc-file-name') 'libgcc').Trim()
    $result['libgcc_path'] = $library
    $result['libgcc_sha256'] = Get-TrihaHash $library
    $sources = @()
    if ($Program -eq 'retire') {
        $sources = @('sw/tests/retire_probe.S')
    } else {
        $sources = @('sw/runtime/crt0.S','sw/runtime/triha_runtime.c')
        if ($Program -eq 'runtime') {
            $sources += 'sw/tests/runtime_smoke.c'
            $flags += ('-DTRIHA_RUNTIME_TRAP=' + [int]($Fault -eq 'trap'))
        } else {
            $port = Join-Path $root 'sw/benchmarks/coremark/port'
            $benchmark = Join-Path $root 'sw/benchmarks/coremark/src'
            $header = '#define TRIHA_COMPILER_FLAGS "' + ($result.compiler_flags -join ' ') + '"' + "`n"
            [IO.File]::WriteAllText((Join-Path $runRoot 'core_build_config.h'), $header, [Text.UTF8Encoding]::new($false))
            $flags += @("-DITERATIONS=$Iterations",'-DTOTAL_DATA_SIZE=2000','-DCORE_DEBUG=0',
                ('-DPERFORMANCE_RUN=' + [int]($RunKind -eq 'performance')),
                ('-DVALIDATION_RUN=' + [int]($RunKind -eq 'validation')),
                '-I',$port,'-I',$benchmark,'-I',$runRoot)
            $formatter = [IO.File]::ReadAllText((Join-Path $benchmark 'barebones/ee_printf.c'))
            $uartPattern = '(?s)void uart_send_char\(char c\) \{.*?\n\}\s*(?=int ee_printf)'
            if ([regex]::Matches($formatter,$uartPattern).Count -ne 1 -or
                [regex]::Matches($formatter,'#ifdef HAS_FLOAT').Count -ne 2 -or
                [regex]::Matches($formatter,'va_start\(args, fmt\);').Count -ne 1) {
                throw 'Formatter adapter no longer matches the fixed source.'
            }
            $formatter = [regex]::Replace($formatter,$uartPattern,"void uart_send_char(char c);`n`n")
            $formatter = $formatter.Replace('#ifdef HAS_FLOAT','#if HAS_FLOAT')
            $formatter = $formatter.Replace('va_start(args, fmt);',"triha_coremark_note(fmt);`n  va_start(args, fmt);")
            $generatedFormatter = Join-Path $runRoot 'ee_printf.c'
            [IO.File]::WriteAllText($generatedFormatter,$formatter,[Text.UTF8Encoding]::new($false))
            $main = Join-Path $benchmark 'core_main.c'
            if ($Fault -eq 'crc') {
                $mainText = [IO.File]::ReadAllText($main)
                if ([regex]::Matches($mainText,'\(ee_u16\)0xe714').Count -ne 1) { throw 'CRC negative source anchor changed.' }
                $main = Join-Path $runRoot 'core_main_crc_fault.c'
                [IO.File]::WriteAllText($main,$mainText.Replace('(ee_u16)0xe714','(ee_u16)0xe715'),[Text.UTF8Encoding]::new($false))
            }
            $sources += @($main,$generatedFormatter,'sw/benchmarks/coremark/port/core_portme.c')
            $sources += @('core_list_join.c','core_matrix.c','core_state.c','core_util.c') |
                ForEach-Object { Join-Path $benchmark $_ }
        }
    }
    $sources = @($sources | ForEach-Object { if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $root $_ } })
    $elfPath = Join-Path $runRoot 'firmware.elf'
    $compileArguments = @($flags) + @('-I',(Join-Path $root 'sw/runtime'),'-nostdlib',
        '-T',(Join-Path $root 'sw/runtime/triha_tcm.ld'),'-Wl,--gc-sections,--build-id=none',
        ('-Wl,-Map=' + (Join-Path $runRoot 'firmware.map')),'-o',$elfPath) + $sources + @('-lgcc')
    Native $gcc $compileArguments 'firmware-build' | Out-Null
    $result.elf_sha256 = Get-TrihaHash $elfPath
    Native (Join-Path $gccBin 'riscv-none-elf-readelf.exe') @('-h','-A','-l',$elfPath) 'elf' | Out-Null
    Native (Join-Path $gccBin 'riscv-none-elf-objdump.exe') @('-d',$elfPath) 'disassembly' | Out-Null
    $imagePath = Join-Path $runRoot 'tcm.bin'
    Export-TrihaElf $elfPath $imagePath
    $probeArguments = @()
    if ($Program -eq 'retire') {
        $symbols = Native (Join-Path $gccBin 'riscv-none-elf-nm.exe') @('-n',$elfPath) 'symbols'
        $begin = (Get-TrihaMatch $symbols '(?m)^([0-9a-fA-F]+)\s+\w\s+probe_begin\s*$').Groups[1].Value
        $end = (Get-TrihaMatch $symbols '(?m)^([0-9a-fA-F]+)\s+\w\s+probe_end\s*$').Groups[1].Value
        $expected = if ($Fault -eq 'count') { 15 } else { 14 }
        $probeArguments = @("+PROBE_START=$begin","+PROBE_END=$end","+PROBE_EXPECTED=$expected",'+TRACE_RETIRE')
    }
    $vsim = Join-Path $ModelSimBin 'vsim.exe'
    $result['modelsim_version'] = (Native $vsim @('-version') 'modelsim-version').Trim()
    Native (Join-Path $ModelSimBin 'vmap.exe') @('-c') 'vmap' | Out-Null
    Native (Join-Path $ModelSimBin 'vlib.exe') @('work') 'vlib' | Out-Null
    $vlogArguments = @('-work','work',('+incdir+' + (Join-Path $root 'rtl/cpu/vendor/src/core'))) +
        @($filelist | ForEach-Object { Join-Path $root $_ })
    Native (Join-Path $ModelSimBin 'vlog.exe') $vlogArguments 'rtl-build' | Out-Null
    $modes = if ($Mode -eq 'both') { @('single','dual') } else { @($Mode) }
    foreach ($selected in $modes) {
        Write-Host "CPU_FIRMWARE_SIM mode=$selected"
        $dual = [int]($selected -eq 'dual')
        $arguments = @('-c','-onfinish','exit','-t','1ps','-voptargs=+acc',
            "-gDUAL_ISSUE=$dual",'-gFIRMWARE_MODE=1','-gMAX_CYCLES=20000000',
            'work.tb_triha_core',('+MEM_IMAGE=' + $imagePath.Replace('\','/')),
            '-do',(Join-Path $root 'scripts/cpu/run_modelsim.do')) + $probeArguments
        $output = Native $vsim $arguments "simulation-$selected" $SimulationTimeoutSeconds
        $execution = [ordered]@{mode=$selected;status='FAIL';program_exit_code=$null;measurement=$null}
        $result.executions += $execution
        $exitMatch = Get-TrihaMatch $output '(?m)^(?:# )?CPU_PROGRAM_EXIT code=(\d+)\s*$'
        $execution.program_exit_code = [int]$exitMatch.Groups[1].Value
        if ($execution.program_exit_code -ne 0) { throw "Program exited with code $($execution.program_exit_code)." }
        if ($output -match 'CPU_SMOKE_FAIL|CPU_TRAP|\*\* (Error|Fatal)') { throw 'Firmware or observer reported failure.' }
        $completed = Get-TrihaMatch $output 'CPU_FIRMWARE_PASS dual=(\d+) cycles=(\d+) issued=(\d+) pairs=(\d+)'
        if ([int]$completed.Groups[1].Value -ne $dual) { throw 'Wrong issue configuration.' }
        $execution['issue_observation'] = [ordered]@{
            total_cycles=[long]$completed.Groups[2].Value
            issued=[long]$completed.Groups[3].Value
            paired_cycles=[long]$completed.Groups[4].Value
            issued_is_not_instret=$true
        }
        if ($Program -eq 'runtime' -and $output -notmatch 'CPU_RUNTIME_PASS') { throw 'Runtime test did not complete.' }
        if ($Program -eq 'retire' -and $output -notmatch 'CPU_RETIRE_PROBE count=14 expected=14') {
            throw 'Retirement observer failed its directed check.'
        }
        if ($Program -eq 'coremark') {
            $window = Get-TrihaMatch $output 'CPU_MEASURE cycles=(\d+) retired=(\d+) reads=(\d+)'
            $ticks = [long](Get-TrihaMatch $output 'Total ticks\s*:\s*(\d+)').Groups[1].Value
            $iterationsActual = [int](Get-TrihaMatch $output 'Iterations\s*:\s*(\d+)').Groups[1].Value
            if ($ticks -le 0 -or $ticks -ne [long]$window.Groups[1].Value -or
                [int]$window.Groups[3].Value -ne 2 -or $iterationsActual -ne $Iterations) {
                throw 'Software timer and observer window disagree.'
            }
            $expectedCrc = if ($RunKind -eq 'performance') {
                @('e9f5','e714','1fd7','8e3a')
            } else { @('18f2','e3c1','0747','8d84') }
            $patterns = @('seedcrc\s*:\s*0x([0-9a-fA-F]+)',
                '\[0\]crclist\s*:\s*0x([0-9a-fA-F]+)',
                '\[0\]crcmatrix\s*:\s*0x([0-9a-fA-F]+)',
                '\[0\]crcstate\s*:\s*0x([0-9a-fA-F]+)')
            $crcs = @()
            for ($index=0; $index -lt 4; ++$index) {
                $crc = (Get-TrihaMatch $output $patterns[$index]).Groups[1].Value.ToLowerInvariant().PadLeft(4,'0')
                if ($crc -ne $expectedCrc[$index]) { throw "Benchmark CRC mismatch at index $index." }
                $crcs += $crc
            }
            $shortRun = $ticks -lt 1000000000
            $statusPattern = 'CPU_COREMARK_STATUS errors=0 short=' + [int]$shortRun
            if ($output -notmatch $statusPattern) { throw 'CoreMark platform status did not pass.' }
            $errorLines = [regex]::Matches($output,'(?m)^.*ERROR!.*$')
            foreach ($line in $errorLines) {
                if ($line.Value -notmatch 'ERROR! Must execute for at least 10 secs for a valid result!') {
                    throw 'Unexpected CoreMark error output.'
                }
            }
            if ($shortRun -and $errorLines.Count -ne 1) { throw 'Original short-duration warning missing.' }
            $retired = [long]$window.Groups[2].Value
            $execution.measurement = [ordered]@{
                cycles=$ticks;wb_completed=$retired;observed_ipc=([double]$retired/$ticks)
                coremark_per_mhz_short_estimate=([double]$Iterations*1000000/$ticks)
                crc=$crcs;short_duration_warning=$shortRun;official_score=$false
            }
            Write-Host "CPU_COREMARK mode=$selected cycles=$ticks wb_completed=$retired estimate=$($execution.measurement.coremark_per_mhz_short_estimate)"
        }
        $execution.status = 'PASS'
    }
    $result.status = 'PASS'
} catch {
    $result.status = 'FAIL'
    $result.error = $_.Exception.Message
} finally {
    $unchanged = $true
    foreach ($relative in $result.input_hashes.Keys) {
        $path = Join-Path $root $relative
        if (-not (Test-Path -LiteralPath $path) -or (Get-TrihaHash $path) -ne $result.input_hashes[$relative]) {
            $unchanged = $false
        }
    }
    $result.source_unchanged = $unchanged
    if (-not $unchanged) { $result.status='FAIL';$result.error='Inputs changed during the run.' }
    foreach ($file in Get-ChildItem -LiteralPath $runRoot -File) {
        if ($file.Name -ne 'result.json') { $result.output_hashes[$file.Name] = Get-TrihaHash $file.FullName }
    }
    $result['finished_utc'] = [DateTime]::UtcNow.ToString('o')
    $result['elapsed_seconds'] = [Math]::Round($timer.Elapsed.TotalSeconds,3)
    $result.runner_return_code = if ($result.status -eq 'PASS') { 0 } else { 1 }
    Save-TrihaJson $resultPath $result
    Write-Host "CPU_FIRMWARE $($result.status) result=$resultPath"
    if ($result.error) { Write-Host $result.error }
}
if ($result.status -eq 'PASS') { exit 0 } else { exit 1 }

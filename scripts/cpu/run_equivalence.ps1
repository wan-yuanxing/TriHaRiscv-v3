#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('single','dual','both')][string] $Mode = 'both',
    [switch] $BrokenDual,
    [switch] $CompareIdleBus,
    [ValidateRange(1,2147483647)][int] $Seed = 1
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'firmware_common.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$work = Join-Path $root ('build/cpu/equivalence-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$commands = [Collections.Generic.List[object]]::new()
$result = [ordered]@{status='RUNNING';mode=$Mode;broken_dual=[bool]$BrokenDual;seed=$Seed
    directory=$work;input_hashes=[ordered]@{};output_hashes=[ordered]@{};native_commands=$commands
    source_unchanged=$false;executions=@();error=$null;runner_return_code=$null
    register_redirect=0;compare_idle_bus=[bool]$CompareIdleBus
    scope='legacy redirect request/control and active/stalled payload cycle differential simulation; registered redirect uses run_redirect.ps1; not complete ISA/formal proof'}
$resultPath = Join-Path $work 'result.json'
Save-TrihaJson $resultPath $result
Write-Host "CPU_EQ_RUN mode=$Mode seed=$Seed directory=$work"
function Native([string] $Exe,[string[]] $Arguments,[string] $Label) {
    Invoke-TrihaNative -Executable $Exe -CommandArguments $Arguments -RunDirectory $work -Label $Label -Records $commands -TimeoutSeconds 90
}
try {
    Assert-TrihaAdaptation $root
    if ($BrokenDual -and $Mode -ne 'dual') { throw 'BrokenDual is a dual-mode negative only.' }
    $sources = @(Get-Content (Join-Path $root 'config/cpu_sources.f') |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    # Candidate is explicit even during the RED check when it does not exist.
    $sources = @($sources | Where-Object { $_ -ne 'tb/cpu/tb_triha_core.v' })
    if ('rtl/cpu/triha_cpu.v' -notin $sources) { $sources += 'rtl/cpu/triha_cpu.v' }
    $sources += 'tb/cpu/tb_cpu_equivalence.v'
    foreach ($name in $sources + @('sw/tests/control_stress.S','sw/runtime/triha_tcm.ld',
        'scripts/cpu/run_equivalence.ps1','scripts/cpu/firmware_common.ps1','scripts/cpu/run_modelsim.do',
        'config/cpu_sources.f','config/cpu_toolchain.json','rtl/cpu/ADAPTATIONS.json',
        'rtl/cpu/vendor/src/core/biriscv_defs.v','rtl/cpu/vendor/UPSTREAM.json')) {
        if (Test-Path -LiteralPath (Join-Path $root $name)) { $result.input_hashes[$name] = Get-TrihaHash (Join-Path $root $name) }
    }
    $config = Get-Content (Join-Path $root 'config/cpu_toolchain.json') -Raw | ConvertFrom-Json
    $gcc = if ($env:TRIHA_RISCV_GCC) { $env:TRIHA_RISCV_GCC } else { $config.compiler }
    $result['compiler_sha256'] = Get-TrihaHash $gcc
    $bin = Split-Path -Parent $gcc
    $elf = Join-Path $work 'control.elf'
    Native $gcc @('-march=rv32im_zicsr_zifencei','-mabi=ilp32','-mcmodel=medany','-mno-relax','-nostdlib',
        '-T',(Join-Path $root 'sw/runtime/triha_tcm.ld'),'-Wl,--build-id=none','-o',$elf,
        (Join-Path $root 'sw/tests/control_stress.S')) 'firmware' | Out-Null
    $symbols = Native (Join-Path $bin 'riscv-none-elf-nm.exe') @('-n',$elf) 'symbols'
    $faultPc = (Get-TrihaMatch $symbols '(?m)^([0-9a-f]+)\s+\w\s+fetch_fault_target\s*$').Groups[1].Value
    $image = Join-Path $work 'tcm.bin'
    Export-TrihaElf $elf $image
    $modelsim = 'D:/modeltech64_2020.4/win64'
    Native (Join-Path $modelsim 'vmap.exe') @('-c') 'vmap' | Out-Null
    Native (Join-Path $modelsim 'vlib.exe') @('work') 'vlib' | Out-Null
    Native (Join-Path $modelsim 'vlog.exe') (@('-work','work',('+incdir+' + (Join-Path $root 'rtl/cpu/vendor/src/core'))) +
        @($sources | ForEach-Object { Join-Path $root $_ })) 'compile' | Out-Null
    foreach ($selected in $(if ($Mode -eq 'both') { @('single','dual') } else { @($Mode) })) {
        $dual = [int]($selected -eq 'dual')
        $output = Native (Join-Path $modelsim 'vsim.exe') @('-c','-onfinish','exit','-t','1ps','-voptargs=+acc',
            "-gDUAL_ISSUE=$dual",('-gBROKEN_DUAL=' + [int][bool]$BrokenDual),'work.tb_cpu_equivalence',
            $(if($CompareIdleBus){'+COMPARE_IDLE_BUS'}else{'+TRANSACTION_BUS'}),
            ('+MEM_IMAGE=' + $image.Replace('\','/')),"+FETCH_FAULT_PC=$faultPc","+SEED=$Seed",
            '-do',(Join-Path $root 'scripts/cpu/run_modelsim.do')) "simulation-$selected"
        if ($output -match 'CPU_EQ_FAIL|\*\* (Error|Fatal)') { throw 'Differential test reported failure.' }
        $pass = Get-TrihaMatch $output 'CPU_EQ_PASS dual=(\d+) cycles=(\d+) traps=(\d+) i_stalls=(\d+) d_stalls=(\d+)'
        $result.executions += [ordered]@{mode=$selected;status='PASS';cycles=[int]$pass.Groups[2].Value
            trap_mask=[int]$pass.Groups[3].Value;i_stalls=[int]$pass.Groups[4].Value;d_stalls=[int]$pass.Groups[5].Value}
    }
    $result.status = 'PASS'
} catch { $result.status='FAIL';$result.error=$_.Exception.Message }
finally {
    $result.source_unchanged = $true
    foreach ($name in $result.input_hashes.Keys) {
        if ((Get-TrihaHash (Join-Path $root $name)) -ne $result.input_hashes[$name]) { $result.source_unchanged=$false }
    }
    if (-not $result.source_unchanged) { $result.status='FAIL';$result.error='Inputs changed.' }
    foreach ($file in Get-ChildItem -LiteralPath $work -File) {
        if ($file.FullName -ne $resultPath) { $result.output_hashes[$file.Name] = Get-TrihaHash $file.FullName }
    }
    $result.runner_return_code = if ($result.status -eq 'PASS') { 0 } else { 1 }
    Save-TrihaJson $resultPath $result
    Write-Host "CPU_EQ $($result.status) result=$resultPath"
    if ($result.error) { Write-Host $result.error }
}
exit $result.runner_return_code

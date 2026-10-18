#requires -Version 7.0
<# Verify the installed Windows compiler by linking and inspecting RV32 ELF files. #>
[CmdletBinding()]
param([string] $Compiler = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$configPath = Join-Path $projectRoot 'config/cpu_toolchain.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if (-not $Compiler) {
    $Compiler = if ($env:TRIHA_RISCV_GCC) { $env:TRIHA_RISCV_GCC } else { $config.compiler }
}
$runRoot = Join-Path $projectRoot ('build/cpu/toolchain-check-' +
    [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
[IO.Directory]::CreateDirectory($runRoot) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$result = [ordered]@{
    status = 'RUNNING'; scope = 'native Windows RV32 compile/link and ELF inspection'
    recorded_utc = [DateTime]::UtcNow.ToString('o'); compiler = $Compiler
    run_directory = $runRoot; version = $null; dumpmachine = $null
    archive_sha256 = $config.archive_sha256; compiler_sha256 = $null
    runner_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    config_sha256 = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
    profiles = @(); output_hashes = [ordered]@{}; error = $null
    software_executed = $false; coremark_measured = $false
}

try {
    if (-not (Test-Path -LiteralPath $Compiler -PathType Leaf)) {
        throw "Windows RISC-V GCC not found: $Compiler"
    }
    $compilerBin = Split-Path -Parent $Compiler
    $readelf = Join-Path $compilerBin 'riscv-none-elf-readelf.exe'
    $objdump = Join-Path $compilerBin 'riscv-none-elf-objdump.exe'
    $result.version = ((& $Compiler --version) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'GCC version command failed.' }
    $result.dumpmachine = ((& $Compiler -dumpmachine) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'GCC target command failed.' }
    $result.compiler_sha256 = (Get-FileHash -LiteralPath $Compiler -Algorithm SHA256).Hash.ToLowerInvariant()
    $sourcePath = Join-Path $runRoot 'rv32_probe.c'
    $source = @'
typedef unsigned int u32;
volatile u32 input_a = 17;
volatile u32 input_b = 23;
volatile u32 signature;

void _start(void)
{
    signature = input_a * input_b + 7;
    for (;;) {}
}
'@
    [IO.File]::WriteAllText($sourcePath, $source, $utf8)
    foreach ($architecture in @($config.baseline_march, $config.performance_march)) {
        $elfPath = Join-Path $runRoot "$architecture.elf"
        $arguments = @("-march=$architecture", "-mabi=$($config.abi)", '-O2',
            '-ffreestanding', '-nostdlib',
            '-Wl,-Ttext=0x80000000,-e,_start,--build-id=none',
            '-o', $elfPath, $sourcePath, '-lgcc')
        $output = & $Compiler @arguments 2>&1
        $compileCode = $LASTEXITCODE
        [IO.File]::WriteAllText((Join-Path $runRoot "$architecture.compile.log"),
            ($output | Out-String), $utf8)
        if ($compileCode -ne 0) { throw "RV32 compile/link failed: $architecture" }
        $bytes = [IO.File]::ReadAllBytes($elfPath)
        if ($bytes[4] -ne 1 -or [BitConverter]::ToUInt16($bytes, 18) -ne 243 -or
            [BitConverter]::ToUInt32($bytes, 24) -ne 2147483648) {
            throw 'Output is not an ELF32 RISC-V executable at the test entry.'
        }
        $elfReport = (& $readelf -h -A $elfPath) | Out-String
        if ($LASTEXITCODE -ne 0 -or $elfReport -notmatch 'ELF32' -or
            $elfReport -notmatch 'RISC-V' -or $elfReport -notmatch 'rv32i') {
            throw 'RV32 ELF header/attribute inspection failed.'
        }
        [IO.File]::WriteAllText((Join-Path $runRoot "$architecture.readelf.log"), $elfReport, $utf8)
        $disassembly = (& $objdump -d $elfPath) | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'RV32 disassembly failed.' }
        [IO.File]::WriteAllText((Join-Path $runRoot "$architecture.disassembly.log"), $disassembly, $utf8)
        $result.profiles += [ordered]@{
            march = $architecture; mabi = $config.abi; compile_return_code = $compileCode
            elf_class = 'ELF32'; machine = 'RISC-V'
            elf_sha256 = (Get-FileHash -LiteralPath $elfPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $result.status = 'PASS'
} catch {
    $result.status = 'FAIL'
    $result.error = $_.Exception.Message
} finally {
    foreach ($file in Get-ChildItem -LiteralPath $runRoot -File) {
        $result.output_hashes[$file.Name] =
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    [IO.File]::WriteAllText((Join-Path $runRoot 'result.json'),
        ($result | ConvertTo-Json -Depth 8) + "`n", $utf8)
    Write-Host "CPU_TOOLCHAIN $($result.status) result=$(Join-Path $runRoot 'result.json')"
    if ($result.error) { Write-Host $result.error }
}
if ($result.status -eq 'PASS') { exit 0 } else { exit 1 }

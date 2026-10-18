# Native process and ELF helpers; no shell evaluation or additional packages.
function Get-TrihaHash([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Save-TrihaJson([string] $Path, $Value) {
    $text = ($Value | ConvertTo-Json -Depth 14).Replace("`r`n", "`n") + "`n"
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

function Invoke-TrihaNative {
    param([string] $Executable, [string[]] $CommandArguments,
        [string] $RunDirectory, [string] $Label, $Records, [int] $TimeoutSeconds = 60)
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        throw "Executable not found: $Executable"
    }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.WorkingDirectory = $RunDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $CommandArguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $record = [ordered]@{tool=$Executable;arguments=$CommandArguments;pid=$null
        return_code=$null;timed_out=$false;elapsed_seconds=$null}
    $Records.Add($record)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $process.Start() | Out-Null
        $record.pid = $process.Id
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $record.timed_out = $true
            $process.Kill($true)
            $process.WaitForExit()
        }
        $stdout = $outTask.GetAwaiter().GetResult()
        $stderr = $errTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $RunDirectory "$Label.stdout.log"), $stdout,
            [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $RunDirectory "$Label.stderr.log"), $stderr,
            [Text.UTF8Encoding]::new($false))
        $record.return_code = $process.ExitCode
        $record.elapsed_seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
        if ($record.timed_out) { throw "$Label wall-clock timeout after $TimeoutSeconds seconds." }
        if ($record.return_code -ne 0) { throw "$Label returned $($record.return_code); inspect its logs." }
        return $stdout + $stderr
    } finally {
        $process.Dispose()
    }
}

function Export-TrihaElf([string] $ElfPath, [string] $Destination) {
    $elf = [IO.File]::ReadAllBytes($ElfPath)
    if ($elf.Length -lt 52 -or $elf[0] -ne 127 -or $elf[1] -ne 69 -or
        $elf[2] -ne 76 -or $elf[3] -ne 70 -or $elf[4] -ne 1 -or $elf[5] -ne 1 -or
        [BitConverter]::ToUInt16($elf,18) -ne 243 -or
        [BitConverter]::ToUInt32($elf,24) -ne 2147483648) { throw 'Invalid RV32 test ELF.' }
    $image = [byte[]]::new(131072)
    [Array]::Fill($image, [byte]165)
    $offset = [uint64][BitConverter]::ToUInt32($elf,28)
    $size = [uint64][BitConverter]::ToUInt16($elf,42)
    $count = [uint64][BitConverter]::ToUInt16($elf,44)
    if ($size -lt 32 -or $offset + $size * $count -gt $elf.Length) { throw 'Invalid ELF segment table.' }
    $loaded = 0
    for ($index = 0; $index -lt $count; ++$index) {
        $header = [int]($offset + $size * $index)
        if ([BitConverter]::ToUInt32($elf,$header) -ne 1) { continue }
        $fileOffset = [uint64][BitConverter]::ToUInt32($elf,$header+4)
        $address = [uint64][BitConverter]::ToUInt32($elf,$header+12)
        $fileSize = [uint64][BitConverter]::ToUInt32($elf,$header+16)
        $memorySize = [uint64][BitConverter]::ToUInt32($elf,$header+20)
        if ($address -lt 2147483648 -or $fileSize -gt $memorySize -or
            $fileOffset + $fileSize -gt $elf.Length -or
            $address - 2147483648 + $memorySize -gt $image.Length) {
            throw 'ELF segment exceeds test TCM.'
        }
        [Buffer]::BlockCopy($elf,[int]$fileOffset,$image,[int]($address-2147483648),[int]$fileSize)
        ++$loaded
    }
    if ($loaded -eq 0) { throw 'No ELF load segments.' }
    [IO.File]::WriteAllBytes($Destination,$image)
}

function Get-TrihaMatch([string] $Text, [string] $Pattern) {
    $matchesFound = [regex]::Matches($Text,$Pattern)
    if ($matchesFound.Count -ne 1) { throw "Expected exactly one result matching: $Pattern" }
    return $matchesFound[0]
}

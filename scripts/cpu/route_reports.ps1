# Actual final PDS timing summaries; never infer frequency from tool status.
function Get-TrihaRouteTiming([string] $Text,[double] $RequestedPeriodNs=10.0) {
    if([double]::IsNaN($RequestedPeriodNs) -or [double]::IsInfinity($RequestedPeriodNs) -or $RequestedPeriodNs -le 0){throw 'Invalid requested clock period.'}
    if($Text -notmatch 'Timing analysis mode\s*:\s*multi corner'){throw 'Final multi-corner report missing.'}
    $clock=[regex]::Matches($Text,'(?m)^\s*cpu_clk\s+([\d.]+)\s+\{0\.0000\s+([\d.]+)\}')
    if($clock.Count -ne 1){throw 'Missing/duplicate final CPU clock.'}
    $actualPeriod=[double]::Parse($clock[0].Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
    $actualHalf=[double]::Parse($clock[0].Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)
    # PDS quantizes the clock to1ps. Check the exact quantized period rather
    # than accepting an arbitrary tolerance or silently accepting another clock.
    $quantized=[Math]::Round($RequestedPeriodNs,3,[MidpointRounding]::AwayFromZero)
    if([Math]::Abs($actualPeriod-$quantized) -gt 0.00005 -or [Math]::Abs($actualHalf-$actualPeriod/2) -gt 0.00005){throw 'Actual report clock differs from frozen requested period.'}
    $rows=@()
    foreach($corner in @('Slow','Fast')) {
        foreach($kind in @('Setup','Hold','Minimum Pulse Width')) {
            $header=[regex]::Escape("$kind Summary($corner Corner):")
            $blocks=[regex]::Matches($Text,'(?ms)^'+$header+'\r?\n(.*?)(?=^={10,}\s*$)')
            if($blocks.Count -ne 1){throw "Missing/duplicate final section: $kind/$corner"}
            $pattern=if($kind -eq 'Minimum Pulse Width') {
                '(?m)^\s*cpu_clk\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$'
            } else {
                '(?m)^\s*cpu_clk\s+cpu_clk\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$'
            }
            $found=[regex]::Matches($blocks[0].Groups[1].Value,$pattern)
            if($found.Count -ne 1){throw "Missing CPU timing row: $kind/$corner"}
            $rows += [ordered]@{corner=$corner;check=$kind
                slack_ns=[double]::Parse($found[0].Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
                total_negative_slack_ns=[double]::Parse($found[0].Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)
                failing_endpoints=[long]$found[0].Groups[3].Value;endpoints=[long]$found[0].Groups[4].Value}
        }
    }
    $perf=[regex]::Matches($Text,'(?m)^\s*cpu_clk\s+(\d+\.\d+) MHz\s+\d+\.\d+ MHz\s+(\d+\.\d+)\s+\d+\.\d+\s+(-?\d+\.\d+)\s*$')
    if($perf.Count -ne 1){throw 'Missing final performance summary.'}
    $frequency=[double]::Parse($perf[0].Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
    $perfPeriod=[double]::Parse($perf[0].Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)
    if([Math]::Abs($perfPeriod-$actualPeriod) -gt 0.00005 -or [Math]::Abs($frequency-1000.0/$actualPeriod) -gt 0.0001){throw 'Inconsistent performance frequency/clock period.'}
    $slack=[double]::Parse($perf[0].Groups[3].Value,[Globalization.CultureInfo]::InvariantCulture)
    $worst=($rows|Where-Object {$_.check -eq 'Setup'}|ForEach-Object {[double]$_.slack_ns}|Measure-Object -Minimum).Minimum
    $consistent=[Math]::Abs($slack-$worst) -le 0.001
    $met=$Text -match 'Design Summary\s*:\s*All Constraints Met\.'
    foreach($row in $rows){if($row.slack_ns -lt 0 -or $row.failing_endpoints -ne 0 -or $row.endpoints -le 0){$met=$false}}
    return [ordered]@{met=($met -and $consistent -and $slack -ge 0);corners=$rows
        performance_slack_ns=$slack;worst_setup_ns=$worst;performance_consistent=$consistent
        requested_period_ns=$RequestedPeriodNs;reported_period_ns=$actualPeriod;reported_frequency_mhz=$frequency
        period_quantization_ns=($actualPeriod-$RequestedPeriodNs)
        all_constraints_met=($Text -match 'Design Summary\s*:\s*All Constraints Met\.')}
}

# Actual final PDS timing summaries; never infer frequency from tool status.
function Get-TrihaRouteTiming([string] $Text) {
    if($Text -notmatch 'Timing analysis mode\s*:\s*multi corner' -or
       $Text -notmatch '(?m)^\s*cpu_clk\s+10\.0000\s+\{0\.0000 5\.0000\}') {
        throw 'Final 10ns multi-corner report missing.'
    }
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
    $perf=[regex]::Matches($Text,'(?m)^\s*cpu_clk\s+100\.0000 MHz\s+\d+\.\d+ MHz\s+10\.0000\s+\d+\.\d+\s+(-?\d+\.\d+)\s*$')
    if($perf.Count -ne 1){throw 'Missing 100MHz performance summary.'}
    $slack=[double]::Parse($perf[0].Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
    $worst=($rows|Where-Object {$_.check -eq 'Setup'}|ForEach-Object {[double]$_.slack_ns}|Measure-Object -Minimum).Minimum
    $consistent=[Math]::Abs($slack-$worst) -le 0.001
    $met=$Text -match 'Design Summary\s*:\s*All Constraints Met\.'
    foreach($row in $rows){if($row.slack_ns -lt 0 -or $row.failing_endpoints -ne 0 -or $row.endpoints -le 0){$met=$false}}
    return [ordered]@{met=($met -and $consistent -and $slack -ge 0);corners=$rows
        performance_slack_ns=$slack;worst_setup_ns=$worst;performance_consistent=$consistent
        all_constraints_met=($Text -match 'Design Summary\s*:\s*All Constraints Met\.')}
}

#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'route_reports.ps1')
$text="Timing analysis mode : multi corner`n cpu_clk 10.0000 {0.0000 5.0000} Declared`n Performance Summary:`n cpu_clk 100.0000 MHz 102.0408 MHz 10.0000 9.8000 0.200`nDesign Summary : All Constraints Met.`n"
foreach($corner in @('Slow','Fast')) {
    foreach($kind in @('Setup','Hold')) {
        $text+="$kind Summary($corner Corner):`n Clock headers`n cpu_clk cpu_clk 0.200 0.000 0 6000`n====================`n"
    }
    $text+="Minimum Pulse Width Summary($corner Corner):`n Clock headers`n cpu_clk 4.000 0.000 0 6000`n====================`n"
}
$value=Get-TrihaRouteTiming $text
if(-not $value.met -or $value.corners.Count -ne 6){throw 'Positive timing parse failed.'}
$bad=$text.Replace('cpu_clk cpu_clk 0.200','cpu_clk cpu_clk -0.100').Replace('9.8000 0.200','10.1000 -0.100').Replace('All Constraints Met','Some Constraints Violated')
if((Get-TrihaRouteTiming $bad).met){throw 'Negative slack was accepted.'}
if((Get-TrihaRouteTiming ($text.Replace('9.8000 0.200','9.0000 1.000'))).met){throw 'Mismatched performance slack was accepted.'}
$rejected=$false
try{Get-TrihaRouteTiming ($text.Replace('Minimum Pulse Width Summary(Fast Corner):','Missing final section:'))|Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'Missing Fast pulse width was accepted.'}
$lower=$text.Replace('10.0000 {0.0000 5.0000}','10.5260 {0.0000 5.2630}').Replace('100.0000 MHz 102.0408 MHz 10.0000','95.0029 MHz 102.0408 MHz 10.5260')
$value=Get-TrihaRouteTiming $lower -RequestedPeriodNs (1000.0/95)
if(-not $value.met -or $value.reported_period_ns -ne 10.526){throw 'Explicit95MHz clock quantization was rejected.'}
foreach($item in @(
    @{text=$lower;period=10.0},
    @{text=$text;period=(1000.0/95)},
    @{text=$lower.Replace('95.0029 MHz','100.0000 MHz');period=(1000.0/95)},
    @{text=$lower;period=[double]::NaN}
)) {
    $rejected=$false
    try{Get-TrihaRouteTiming $item.text -RequestedPeriodNs $item.period|Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Inconsistent frequency/clock metadata was accepted.'}
}
Write-Host 'CPU_ROUTE_REPORT_TEST PASS'

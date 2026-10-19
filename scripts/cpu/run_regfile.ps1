#requires -Version 7.0
[CmdletBinding()]
param([ValidateSet('legacy','candidate')][string] $Backend='candidate',
    [ValidateSet('simulation','map')][string] $Stage='simulation', [switch] $Broken)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'firmware_common.ps1')
. (Join-Path $PSScriptRoot 'pds_reports.ps1')
. (Join-Path $PSScriptRoot 'simulation_common.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$work=Join-Path $root ('build/cpu/regfile-'+$Backend+'-'+$Stage+'-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
[IO.Directory]::CreateDirectory($work)|Out-Null
$records=[Collections.Generic.List[object]]::new()
$r=[ordered]@{status='RUNNING';backend=$Backend;stage=$Stage;broken=[bool]$Broken;directory=$work
    input_hashes=[ordered]@{};external_input_hashes=[ordered]@{};output_hashes=[ordered]@{}
    native_commands=$records;source_unchanged=$false;resources=$null;distributed_ram=$null;error=$null;runner_return_code=$null
    scope='Single-issue register-file component semantics and resource mapping, not CPU timing acceptance'}
$resultPath=Join-Path $work 'result.json'
Save-TrihaJson $resultPath $r
Write-Host "CPU_REGFILE_RUN backend=$Backend stage=$Stage directory=$work"
try {
    $module=if($Backend -eq 'legacy'){'biriscv_regfile'}else{'triha_regfile'}
    $sources=@('rtl/cpu/vendor/src/core/biriscv_regfile.v')
    if($Backend -eq 'candidate'){$sources+='rtl/cpu/triha_regfile.v'}
    $inputs=$sources+@('tb/cpu/tb_regfile.v','scripts/cpu/run_regfile.ps1',
        'scripts/cpu/firmware_common.ps1','scripts/cpu/pds_reports.ps1','scripts/cpu/simulation_common.ps1','scripts/cpu/run_modelsim.do','config/cpu_primitives.json')
    foreach($name in $inputs){$r.input_hashes[$name]=Get-TrihaHash (Join-Path $root $name)}
    if($Stage -eq 'simulation') {
        $modelSources=@()
        if($Backend -eq 'candidate') {
            $modelSources=@(Get-TrihaPrimitiveModels -Root $root -LocalHashes $r.input_hashes -ExternalHashes $r.external_input_hashes)
        }
        $bin='D:/modeltech64_2020.4/win64'
        foreach($pair in @(@('vmap.exe','-c'),@('vlib.exe','work'))) {
            Invoke-TrihaNative -Executable (Join-Path $bin $pair[0]) -CommandArguments @($pair[1]) -RunDirectory $work -Label $pair[0] -Records $records|Out-Null
        }
        $vlogArguments=@('-work','work',"+define+RF_MODULE=$module")+@($sources|ForEach-Object {Join-Path $root $_})+$modelSources+@(Join-Path $root 'tb/cpu/tb_regfile.v')
        Invoke-TrihaNative -Executable (Join-Path $bin 'vlog.exe') -CommandArguments $vlogArguments -RunDirectory $work -Label 'compile' -Records $records|Out-Null
        $out=Invoke-TrihaNative -Executable (Join-Path $bin 'vsim.exe') -CommandArguments @('-c','-onfinish','exit','-voptargs=+acc',('-gBROKEN='+[int][bool]$Broken),'work.tb_regfile','-do',(Join-Path $root 'scripts/cpu/run_modelsim.do')) -RunDirectory $work -Label 'simulation' -Records $records
        if($out -notmatch 'REGFILE_PASS' -or $out -match 'REGFILE_FAIL|\*\* (Error|Fatal)'){throw 'Register-file oracle rejected output.'}
        $r['checks']=[int](Get-TrihaMatch $out 'REGFILE_PASS checks=\s*(\d+)').Groups[1].Value
    } else {
        $lines=@('set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676')
        foreach($name in $sources) {
            $source=Join-Path $root $name;$snapshot=Join-Path $work ('src/'+$name)
            [IO.Directory]::CreateDirectory((Split-Path -Parent $snapshot))|Out-Null
            [IO.File]::Copy($source,$snapshot)
            if((Get-TrihaHash $snapshot) -ne $r.input_hashes[$name]){throw 'Snapshot mismatch.'}
            $lines+='add_design {'+$snapshot.Replace('\','/')+'}'
        }
        $lines+="compile -top_module $module -defined_parameters {SUPPORT_DUAL_ISSUE 0 SUPPORT_REGFILE_XILINX 0}"
        $lines+='synthesize -ads -write_verilog TRUE';$lines+='dev_map -detail'
        $tcl=Join-Path $work 'build.tcl'
        [IO.File]::WriteAllText($tcl,($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
        $out=Invoke-TrihaNative -Executable 'D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe' -CommandArguments @('-file',$tcl,'-work_dir',$work,'-project_name','rf_component') -RunDirectory $work -Label 'pds' -Records $records -TimeoutSeconds 180
        Assert-TrihaPdsStages $out 'map'
        $text=[IO.File]::ReadAllText((Join-Path $work "device_map/$module.dmr"))
        $r.resources=Get-TrihaPdsMappedResources $text
        $r.distributed_ram=[int](Get-TrihaMatch $text '(?m)^\| Distributed RAM\s*\|\s*(\d+)\s*\|').Groups[1].Value
        if($r.distributed_ram -le 0 -or $r.resources.registers -gt 64){throw 'Distributed RAM / <=64 FF component mapping goal not met.'}
    }
    $r.status='PASS'
} catch {$r.status='FAIL';$r.error=$_.Exception.Message}
finally {
    $r.source_unchanged=$true
    foreach($name in $r.input_hashes.Keys){if((Get-TrihaHash (Join-Path $root $name)) -ne $r.input_hashes[$name]){$r.source_unchanged=$false}}
    foreach($name in $r.external_input_hashes.Keys){if((Get-TrihaHash $name) -ne $r.external_input_hashes[$name]){$r.source_unchanged=$false}}
    if(-not $r.source_unchanged){$r.status='FAIL';$r.error='Component inputs changed.'}
    foreach($file in Get-ChildItem -LiteralPath $work -File -Recurse){if($file.FullName -ne $resultPath){$r.output_hashes[[IO.Path]::GetRelativePath($work,$file.FullName).Replace('\','/')]=Get-TrihaHash $file.FullName}}
    $r.runner_return_code=if($r.status -eq 'PASS'){0}else{1}
    Save-TrihaJson $resultPath $r
    Write-Host "CPU_REGFILE $($r.status) result=$resultPath"
    if($r.error){Write-Host $r.error}
}
exit $r.runner_return_code

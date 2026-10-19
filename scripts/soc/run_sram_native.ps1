#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$FirmwareRunDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../cpu/firmware_common.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$work=Join-Path $root ('build/soc/native-sram-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
[IO.Directory]::CreateDirectory($work)|Out-Null
$commands=[Collections.Generic.List[object]]::new()
$result=[ordered]@{status='RUNNING';directory=$work;input_hashes=[ordered]@{};external_hashes=[ordered]@{};output_hashes=[ordered]@{};commands=$commands;source_unchanged=$false}
function Native([string]$Exe,[string[]]$Arguments,[string]$Label,[int]$Timeout=120){
    $result.external_hashes[$Exe]=Get-TrihaHash $Exe
    Invoke-TrihaNative -Executable $Exe -CommandArguments $Arguments -RunDirectory $work -Label $Label -Records $commands -TimeoutSeconds $Timeout
}
Write-Host "SRAM_NATIVE_RUN directory=$work"
try {
    $firmware=(Resolve-Path $FirmwareRunDirectory).Path
    $firmwareResult=Get-Content (Join-Path $firmware 'result.json') -Raw|ConvertFrom-Json
    if($firmwareResult.status -ne 'PASS' -or (Get-TrihaHash (Join-Path $firmware 'sram.hex')) -ne $firmwareResult.output_hashes.'sram.hex'){throw 'Invalid firmware image binding.'}
    [IO.File]::Copy((Join-Path $firmware 'sram.hex'),(Join-Path $work 'sram.hex'))
    $result['image_sha256']=Get-TrihaHash (Join-Path $work 'sram.hex')
    foreach($name in @('rtl/soc/triha_sram.v','tb/soc/tb_sram_native.v','scripts/soc/run_sram_native.ps1','scripts/cpu/firmware_common.ps1','scripts/cpu/run_modelsim.do')){
        $result.input_hashes[$name]=Get-TrihaHash (Join-Path $root $name)
        $destination=Join-Path $work ('src/'+$name)
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))|Out-Null
        [IO.File]::Copy((Join-Path $root $name),$destination)
    }
    $source=(Join-Path $work 'src/rtl/soc/triha_sram.v').Replace('\','/')
    $tcl=@('set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676',"add_design {$source}",
        'compile -top_module triha_sram','synthesize -ads -write_verilog TRUE','dev_map -detail')
    [IO.File]::WriteAllText((Join-Path $work 'build.tcl'),($tcl -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
    $pds='D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe'
    $output=Native $pds @('-file',(Join-Path $work 'build.tcl'),'-work_dir',$work,'-project_name','sram_native') 'pds' 300
    foreach($stage in @('compile','synthesize','dev_map')){if($output -notmatch ('(?m)^Executing : '+$stage+'(?: [^\r\n]*)? successfully\.')){throw "Missing native stage: $stage"}}
    $snr=[IO.File]::ReadAllText((Join-Path $work 'synthesize/triha_sram.snr'))
    $models=@()
    foreach($cell in [regex]::Matches($snr,'(?m)^(GTP_\w+)\s+\d+ uses?\s*$')){
        $path='D:/pango/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation/'+$cell.Groups[1].Value+'.v'
        $result.external_hashes[$path]=Get-TrihaHash $path;$models+=$path
    }
    # GTP_LUT6D is implemented by these library submodules, which are not
    # counted as separately instantiated synthesis cells.
    foreach($name in @('GTP_LUT5','GTP_MUX2LUT6','INT_LUTMUX2_UDP','INT_LUTMUX4_UDP')){
        $path='D:/pango/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation/'+$name+'.v'
        if($path -notin $models){$result.external_hashes[$path]=Get-TrihaHash $path;$models+=$path}
    }
    if($snr -notmatch 'GTP_DRM36K_E1\s+16 uses'){throw 'Expected sixteen native SRAM blocks.'}
    $sim='D:/modeltech64_2020.4/win64/'
    Native ($sim+'vmap.exe') @('-c') 'vmap'|Out-Null
    Native ($sim+'vlib.exe') @('work') 'vlib'|Out-Null
    $vm=Join-Path $work 'synthesize/triha_sram_syn.vm'
    Native ($sim+'vlog.exe') (@($vm,(Join-Path $work 'src/tb/soc/tb_sram_native.v'))+$models) 'vlog'|Out-Null
    $arguments=@('-c','-onfinish','exit','-t','1ps','work.tb_sram_native','-do',(Join-Path $work 'src/scripts/cpu/run_modelsim.do'))
    $normal=Native ($sim+'vsim.exe') $arguments 'simulation' 120
    if($normal -notmatch 'SRAM_NATIVE_PASS checks=12296' -or $normal -match 'SRAM_NATIVE_FAIL|ERROR:|\*\* (Error|Fatal)'){throw 'Native SRAM functional test failed.'}
    $negative=Native ($sim+'vsim.exe') ($arguments+@('+FAULT_READ')) 'simulation-negative' 120
    if($negative -notmatch 'SRAM_NATIVE_FAIL' -or $negative -match 'SRAM_NATIVE_PASS'){throw 'Native SRAM corruption was not detected.'}
    $result.status='PASS'
    $result['checks']=12296
    $result['corruption_rejected']=$true
} catch {$result.status='FAIL';$result['error']=$_.Exception.Message}
finally {
    $result.source_unchanged=$true
    foreach($name in $result.input_hashes.Keys){if((Get-TrihaHash (Join-Path $root $name)) -ne $result.input_hashes[$name]){$result.source_unchanged=$false}}
    foreach($name in $result.external_hashes.Keys){if((Get-TrihaHash $name) -ne $result.external_hashes[$name]){$result.source_unchanged=$false}}
    if(-not $result.source_unchanged){$result.status='FAIL';$result['error']='Inputs changed.'}
    foreach($file in Get-ChildItem $work -File -Recurse){if($file.Name -ne 'result.json'){$result.output_hashes[[IO.Path]::GetRelativePath($work,$file.FullName).Replace('\','/')]=Get-TrihaHash $file.FullName}}
    Save-TrihaJson (Join-Path $work 'result.json') $result
    Write-Host "SRAM_NATIVE $($result.status) result=$work/result.json"
    if('error' -in $result.Keys){Write-Host $result.error}
}
exit $(if($result.status -eq 'PASS'){0}else{1})

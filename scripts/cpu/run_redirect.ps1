#requires -Version 7.0
[CmdletBinding()]
param([ValidateSet('frontend','payload','muldata','csrdata','mularith','training','loadbypass','requestdata','lanedata','divarith','fifodata','bypasstag','pcupdate','ordered')][string] $Test='frontend',
    [ValidateSet('single','dual','both')][string] $Mode='both',
    [ValidateRange(1,2147483647)][int] $Seed=37,
    [switch] $LegacyFrontend, [switch] $Interrupt, [switch] $Broken, [switch] $LegacyDivider, [switch] $LegacyFifo)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'simulation_common.ps1')
. (Join-Path $PSScriptRoot 'firmware_common.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$work=Join-Path $root ('build/cpu/redirect-'+$Test+'-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
[IO.Directory]::CreateDirectory($work)|Out-Null
$commands=[Collections.Generic.List[object]]::new()
$result=[ordered]@{status='RUNNING';test=$Test;mode=$Mode;seed=$Seed;interrupt=[bool]$Interrupt
    broken=[bool]$Broken;legacy_frontend=[bool]$LegacyFrontend;legacy_divider=[bool]$LegacyDivider;legacy_fifo=[bool]$LegacyFifo;directory=$work
    input_hashes=[ordered]@{};output_hashes=[ordered]@{};native_commands=$commands
    source_unchanged=$false;executions=@();error=$null;runner_return_code=$null
    scope='directed ordered WB/store/synchronous exception comparison; not full ISA/formal proof'}
$resultPath=Join-Path $work 'result.json'
Save-TrihaJson $resultPath $result
Write-Host "CPU_REDIRECT_RUN test=$Test directory=$work"
function Native([string] $Exe,[string[]] $Arguments,[string] $Label) {
    Invoke-TrihaNative -Executable $Exe -CommandArguments $Arguments -RunDirectory $work -Label $Label -Records $commands -TimeoutSeconds 90
}
try {
    $result['external_input_hashes']=[ordered]@{}
    $primitiveSources=@(Get-TrihaPrimitiveModels -Root $root -LocalHashes $result.input_hashes -ExternalHashes $result.external_input_hashes)
    Assert-TrihaAdaptation $root
    $sources=@(Get-Content (Join-Path $root 'config/cpu_sources.f') | ForEach-Object {$_.Trim()} |
        Where-Object {$_ -and -not $_.StartsWith('#') -and $_ -ne 'tb/cpu/tb_triha_core.v'})
    $sources+='tb/cpu/tb_frontend_redirect.v'
    if($Test -eq 'payload'){$sources+='tb/cpu/tb_issue_payload.v'}
    if($Test -in @('muldata','csrdata')){$sources+='tb/cpu/tb_unit_payload.v'}
    if($Test -eq 'mularith'){$sources+='tb/cpu/tb_multiplier_payload.v'}
    if($Test -eq 'training'){$sources+='tb/cpu/tb_predictor_training.v'}
    if($Test -eq 'loadbypass'){$sources+='tb/cpu/tb_load_bypass.v'}
    if($Test -eq 'requestdata'){$sources+='tb/cpu/tb_request_payload.v'}
    if($Test -eq 'lanedata'){$sources+='tb/cpu/tb_issue_lane.v'}
    if($Test -eq 'divarith'){$sources+='tb/cpu/tb_divider_arithmetic.v'}
    if($Test -eq 'fifodata'){$sources+='tb/cpu/tb_fifo_payload.v'}
    if($Test -eq 'bypasstag'){$sources+='tb/cpu/tb_bypass_tag.v'}
    if($Test -eq 'pcupdate'){$sources+='tb/cpu/tb_pc_update.v'}
    if($Test -eq 'ordered'){$sources+='tb/cpu/tb_cpu_ordered.v'}
    foreach($name in $sources+@('scripts/cpu/run_redirect.ps1','scripts/cpu/firmware_common.ps1',
        'scripts/cpu/run_modelsim.do','sw/tests/control_stress.S','sw/runtime/triha_tcm.ld',
        'config/cpu_sources.f','config/cpu_toolchain.json','rtl/cpu/ADAPTATIONS.json',
        'rtl/cpu/vendor/UPSTREAM.json','rtl/cpu/vendor/src/core/biriscv_defs.v')) {
        $result.input_hashes[$name]=Get-TrihaHash (Join-Path $root $name)
    }
    $modelsim='D:/modeltech64_2020.4/win64'
    Native (Join-Path $modelsim 'vmap.exe') @('-c') 'vmap'|Out-Null
    if($Test -ne 'ordered') {
        Native (Join-Path $modelsim 'vlib.exe') @('work') 'vlib'|Out-Null
        $module=if($LegacyFrontend){'biriscv_frontend'}else{'triha_frontend'}
        $defines=@("+define+CPU_FRONTEND_MODULE=$module")
        if($Test -eq 'divarith'){$defines+=('+define+DIV_MODULE='+$(if($LegacyDivider){'biriscv_divider'}else{'triha_divider'}))}
        if($Test -eq 'fifodata'){$defines+=('+define+FIFO_MODULE='+$(if($LegacyFifo){'fetch_fifo'}else{'triha_fetch_fifo'}));if(-not $LegacyFifo){$defines+='+define+FIFO_HAS_HINT'}}
        Native (Join-Path $modelsim 'vlog.exe') (@('-work','work',('+incdir+'+(Join-Path $root 'rtl/cpu/vendor/src/core')))+$defines+@($sources|ForEach-Object{Join-Path $root $_})+$primitiveSources) 'compile'|Out-Null
        $top=switch($Test){frontend{'work.tb_frontend_redirect'} payload{'work.tb_issue_payload'} mularith{'work.tb_multiplier_payload'} training{'work.tb_predictor_training'} loadbypass{'work.tb_load_bypass'} requestdata{'work.tb_request_payload'} lanedata{'work.tb_issue_lane'} divarith{'work.tb_divider_arithmetic'} fifodata{'work.tb_fifo_payload'} bypasstag{'work.tb_bypass_tag'} pcupdate{'work.tb_pc_update'} default{'work.tb_unit_payload'}}
        $marker=switch($Test){frontend{'FRONTEND_PASS'} payload{'ISSUE_PAYLOAD_PASS'} mularith{'MUL_PAYLOAD_PASS'} training{'TRAINING_PASS'} loadbypass{'LOAD_BYPASS_PASS'} requestdata{'REQUEST_PAYLOAD_PASS'} lanedata{'ISSUE_LANE_PASS'} divarith{'DIV_ARITH_PASS'} fifodata{'FIFO_PAYLOAD_PASS'} bypasstag{'BYPASS_TAG_PASS'} pcupdate{'PC_UPDATE_PASS'} default{'UNIT_PAYLOAD_PASS'}}
        $generics=if($Test -in @('muldata','csrdata')){@('-gTEST_CSR='+[int]($Test -eq 'csrdata'))}else{@()}
        if($Test -eq 'mularith'){$generics=@('-gCORRUPT_RESULT='+[int][bool]$Broken)}
        if($Test -in @('divarith','fifodata','pcupdate')){$generics=@('-gBROKEN='+[int][bool]$Broken)}
        $out=Native (Join-Path $modelsim 'vsim.exe') (@('-c','-onfinish','exit','-voptargs=+acc')+$generics+@(
            $top,'-do',(Join-Path $root 'scripts/cpu/run_modelsim.do'))) $Test
        if($out -notmatch $marker -or $out -match '(FRONTEND|ISSUE_PAYLOAD|UNIT_PAYLOAD|MUL_PAYLOAD|TRAINING|LOAD_BYPASS|REQUEST_PAYLOAD|ISSUE_LANE|DIV_ARITH|FIFO_PAYLOAD|BYPASS_TAG|PC_UPDATE)_FAIL|\*\* (Error|Fatal)'){throw 'Component contract failed.'}
        $result.executions+=@{test=$Test;status='PASS'}
    } else {
        $config=Get-Content (Join-Path $root 'config/cpu_toolchain.json') -Raw|ConvertFrom-Json
        $gcc=if($env:TRIHA_RISCV_GCC){$env:TRIHA_RISCV_GCC}else{$config.compiler}
        $result['compiler_sha256']=Get-TrihaHash $gcc
        $elf=Join-Path $work 'control.elf'
        $flags=@('-march=rv32im_zicsr_zifencei','-mabi=ilp32','-mcmodel=medany','-mno-relax','-nostdlib')
        if(-not $Interrupt){$flags+='-DNO_EXTERNAL_IRQ'}
        Native $gcc ($flags+@('-T',(Join-Path $root 'sw/runtime/triha_tcm.ld'),'-Wl,--build-id=none','-o',$elf,(Join-Path $root 'sw/tests/control_stress.S'))) 'firmware'|Out-Null
        $symbols=Native (Join-Path (Split-Path -Parent $gcc) 'riscv-none-elf-nm.exe') @('-n',$elf) 'symbols'
        $faultPc=(Get-TrihaMatch $symbols '(?m)^([0-9a-f]+)\s+\w\s+fetch_fault_target\s*$').Groups[1].Value
        $image=Join-Path $work 'tcm.bin'
        Export-TrihaElf $elf $image
        foreach($kind in @('golden','candidate')) {
            Native (Join-Path $modelsim 'vlib.exe') @($kind) "vlib-$kind"|Out-Null
            $module=if($kind -eq 'golden'){'riscv_core'}else{'triha_cpu'}
            Native (Join-Path $modelsim 'vlog.exe') (@('-work',$kind,("+define+CPU_TEST_MODULE=$module"),
                ('+incdir+'+(Join-Path $root 'rtl/cpu/vendor/src/core')))+@($sources|ForEach-Object{Join-Path $root $_})+$primitiveSources) "compile-$kind"|Out-Null
            foreach($selected in $(if($Mode -eq 'both'){@('single','dual')}else{@($Mode)})) {
                $dual=[int]($selected -eq 'dual')
                $prefix="$kind-$selected"
                $out=Native (Join-Path $modelsim 'vsim.exe') @('-c','-onfinish','exit','-voptargs=+acc',
                    "-gDUAL_ISSUE=$dual",('-gIRQ_TEST='+[int][bool]$Interrupt),
                    ('-gBROKEN='+[int]([bool]$Broken -and $kind -eq 'candidate')),
                    "$kind.tb_cpu_ordered",('+MEM_IMAGE='+$image.Replace('\','/')),"+FETCH_FAULT_PC=$faultPc",
                    "+SEED=$Seed","+TRACE_PREFIX=$prefix",'-do',(Join-Path $root 'scripts/cpu/run_modelsim.do')) $prefix
                if($out -match 'CPU_ORDER_FAIL|\*\* (Error|Fatal)'){throw 'Ordered CPU self-check failed.'}
                $pass=Get-TrihaMatch $out 'CPU_ORDER_PASS dual=(\d+) cycles=(\d+) traps=(\d+) retired=(\d+) stores=(\d+) delayed=(\d+)'
                $result.executions+=@{kind=$kind;mode=$selected;cycles=[int]$pass.Groups[2].Value;trap_mask=[int]$pass.Groups[3].Value
                    retired=[int]$pass.Groups[4].Value;stores=[int]$pass.Groups[5].Value;delayed=[int]$pass.Groups[6].Value;status='PASS'}
            }
        }
        if(-not $Interrupt) {
            foreach($selected in $(if($Mode -eq 'both'){@('single','dual')}else{@($Mode)})) {
                foreach($trace in @('wb','store','exception')) {
                    $a=Get-TrihaHash (Join-Path $work "golden-$selected.$trace.log")
                    $b=Get-TrihaHash (Join-Path $work "candidate-$selected.$trace.log")
                    if($a -ne $b){throw "Ordered $selected $trace trace mismatch."}
                }
            }
        }
    }
    $result.status='PASS'
} catch {$result.status='FAIL';$result.error=$_.Exception.Message}
finally {
    $result.source_unchanged=$true
    foreach($name in $result.input_hashes.Keys){if((Get-TrihaHash (Join-Path $root $name)) -ne $result.input_hashes[$name]){$result.source_unchanged=$false}}
    if('external_input_hashes' -in $result.Keys -and -not (Test-TrihaPrimitiveHashes $result.external_input_hashes)){$result.source_unchanged=$false}
    if(-not $result.source_unchanged){$result.status='FAIL';$result.error='Inputs changed.'}
    foreach($file in Get-ChildItem -LiteralPath $work -File){if($file.FullName -ne $resultPath){$result.output_hashes[$file.Name]=Get-TrihaHash $file.FullName}}
    $result.runner_return_code=if($result.status -eq 'PASS'){0}else{1}
    Save-TrihaJson $resultPath $result
    Write-Host "CPU_REDIRECT $($result.status) result=$resultPath"
    if($result.error){Write-Host $result.error}
}
exit $result.runner_return_code

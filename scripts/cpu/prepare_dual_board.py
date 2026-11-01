"""Freeze accepted dual CPU inputs and reuse board deployment tools in build/."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
MANIFEST='docs/verification/cpu/dualissue_btb_address_control_sources.json'
ACCEPTED='build/cpu/dual-btb-address-io-physical-v83'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_digest(data,expected,label):
    if hashlib.sha256(data).hexdigest()!=expected:raise ValueError(label+' hash mismatch')


def require_dual_soc(text):
    modes=re.findall(r'\.DUAL_ISSUE\s*\(\s*([01])\s*\)',text)
    if modes!=['1']:raise ValueError('Need exactly one actual dual-issue core binding')


def replace_once(text,old,new):
    if text.count(old)!=1:raise ValueError('Unexpected deployment template: '+old)
    return text.replace(old,new)


def dual_testbench(text):
    text=replace_once(text,'integer cycles = 0, bit_index, reads = 0;','integer cycles = 0, bit_index, reads = 0, paired = 0;')
    text=replace_once(text,'if (u_dut.u_soc.u_core.u_cpu.EARLY_MUL_BYPASS != 1 ||',
        'if (u_dut.u_soc.u_core.u_cpu.SUPPORT_DUAL_ISSUE != 1 ||\n            u_dut.u_soc.u_core.DUAL_ISSUE != 1 ||\n            u_dut.u_soc.u_core.u_cpu.EARLY_MUL_BYPASS != 1 ||')
    text=replace_once(text,'single_issue=1 indexed_btb=1','dual_issue=1 indexed_btb=1')
    text=replace_once(text,'cycles = cycles + 1;',
        'cycles = cycles + 1;\n        if (`PROFILE_ISSUE.opcode_b_issue_r) paired = paired + 1;')
    start=text.index('            if (`PROFILE_ISSUE.pipe0_valid_wb_w) begin')
    end=text.index('            if ((|u_dut.u_soc.data_wstrb)',start)
    lane1=text[start:end].replace('pipe0_','pipe1_')
    text=text[:end]+lane1+text[end:]
    text=replace_once(text,'cycles > 20000000 || u_dut.u_soc.u_core.u_cpu.u_issue.pipe1_valid_wb_w','cycles > 20000000')
    text=replace_once(text,'timeout/dual lane','timeout')
    text=replace_once(text,'        if (u_dut.exit_code !== 0 || reads != 2)',
        '        if (paired == 0) $fatal(1,"CPU_COREMARK_SIM_FAIL no_actual_dual_pair");\n        $display("CPU_BOARD_DUAL_PAIR_PASS pairs=%0d",paired);\n        if (u_dut.exit_code !== 0 || reads != 2)')
    return text


def registered_status_leds(text):
    text=replace_once(text,'output wire [3:0] led_o','output reg  [3:0] led_o')
    return replace_once(text,
        "    assign led_o = {done && (exit_code != 8'b0), done && (exit_code == 8'b0),\n                    cpu_reset_n, heartbeat_q[25]};",
        "    // Register the status decode before the slow physical LED outputs.\n"
        "    always @(posedge cpu_clk or negedge cpu_reset_n) begin\n"
        "        if (!cpu_reset_n)\n"
        "            led_o <= 4'b0;\n"
        "        else\n"
        "            led_o <= {done && (exit_code != 8'b0), done && (exit_code == 8'b0),\n"
        "                      1'b1, heartbeat_q[25]};\n"
        "    end")


def prepare(output, register_status_leds=False):
    output=output.resolve()
    if output.exists() or not output.is_relative_to(ROOT/'build/cpu'):
        raise ValueError('Use a fresh build/cpu frozen-project directory')
    acceptance=json.loads((ROOT/'docs/verification/cpu/dualissue_btb_address_control.json').read_text(encoding='utf-8'))
    if not acceptance['timing_closed'] or acceptance['physical']['timing']['reported_period_ns']!=10:
        raise ValueError('Need accepted original100MHz CPU')
    manifest=json.loads((ROOT/MANIFEST).read_text(encoding='utf-8'))
    candidate=ROOT/'build/cpu/btb-address-reconstructed-v83'
    for name,entry in manifest['sources'].items():require_digest((candidate/name).read_bytes(),entry['candidate_sha256'],name)
    accepted=ROOT/ACCEPTED
    require_dual_soc((accepted/'src/rtl/soc/triha_minimal_soc.v').read_text(encoding='utf-8'))
    core=json.loads((ROOT/'fpga/pg2l100h/project/cpu_core.json').read_text())
    soc=json.loads((ROOT/'fpga/pg2l100h/project/cpu_minimal_soc_compact.json').read_text())
    board=json.loads((ROOT/'fpga/pg2l100h/project/cpu_board.json').read_text())
    names=set(core['sources']+core['headers']+soc['sources']+soc['headers']+board['sources']+board['physical_constraints'])
    names.update(manifest['sources'])
    names.update(['config/cpu_board.json','config/soc_map.json','config/cpu_toolchain.json','config/cpu_primitives.json',
        'fpga/pg2l100h/project/cpu_core.json','fpga/pg2l100h/project/cpu_minimal_soc_compact.json',
        'fpga/pg2l100h/project/cpu_board.json',board['constraints'],'rtl/cpu/ADAPTATIONS.json','rtl/cpu/vendor/UPSTREAM.json',
        'fpga/pg2l100h/constraints/video_ddr_bist.fdc','fpga/pg2l100h/ip/video_reference_manifest.json',
        'tb/soc/tb_cpu_board_clock.v','tb/soc/tb_cpu_board.v','tb/soc/cpu_board_pll_model.v',
        'tb/soc/tb_cpu_coremark.v','sw/tests/cpu_board.c','sw/benchmarks/coremark/UPSTREAM.json',
        'sw/benchmarks/coremark/port/core_portme.c','sw/benchmarks/coremark/port/core_portme.h'])
    for pattern in ['scripts/soc/*.py','scripts/soc/*.ps1','sw/runtime/*']:
        names.update(p.relative_to(ROOT).as_posix() for p in ROOT.glob(pattern) if p.is_file())
    for name in ['firmware_common.ps1','pds_reports.ps1','route_reports.ps1','run_modelsim.do']:
        names.add('scripts/cpu/'+name)
    for name in json.loads((ROOT/'rtl/cpu/vendor/UPSTREAM.json').read_text())['files']:
        names.add('rtl/cpu/vendor/'+name)
    for name in json.loads((ROOT/'sw/benchmarks/coremark/UPSTREAM.json').read_text())['files']:
        names.add('sw/benchmarks/coremark/src/'+name)
    for entry in json.loads((ROOT/'rtl/cpu/ADAPTATIONS.json').read_text())['adaptations']:
        names.update([entry['base'],entry['derived']])
    origins={};original_hashes={}
    for name in sorted(names):
        source=ROOT/name
        if name in manifest['sources']:source=candidate/name
        elif name.startswith('rtl/soc/') and (accepted/'src'/name).exists():source=accepted/'src'/name
        target=output/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
        origins[name]=str(source);original_hashes[name]=sha(source)
    require_dual_soc((output/'rtl/soc/triha_minimal_soc.v').read_text(encoding='utf-8'))
    adapted={}
    def write(name,text):
        (output/name).parent.mkdir(parents=True,exist_ok=True)
        (output/name).write_text(text,encoding='utf-8',newline='\n');adapted[name]=sha(output/name)
    if register_status_leds:
        name='fpga/pg2l100h/rtl/triha_cpu_board_top.v'
        write(name,registered_status_leds((output/name).read_text(encoding='utf-8')))
    metadata=json.loads((output/'rtl/cpu/ADAPTATIONS.json').read_text())
    for entry in metadata['adaptations']:
        require_digest((output/entry['base']).read_bytes(),entry['base_sha256'],entry['base'])
        actual=sha(output/entry['derived'])
        if actual!=entry['derived_sha256']:
            entry['derived_sha256']=actual
            entry['changes'].append('Frozen v83 dual-board build overlay; exact accepted CPU source manifest binding retained.')
    write('rtl/cpu/ADAPTATIONS.json',json.dumps(metadata,indent=2)+'\n')
    recipe=json.loads((output/'fpga/pg2l100h/project/cpu_board.json').read_text())
    recipe['physical_constraints']=[]
    recipe['slack_prior_in_global_router']=False
    recipe['placement_parallelism']=1
    for name in ['refineplacement_iterations','lut6d_packing_strategy','route_mode','placement_decongestion']:recipe.pop(name,None)
    recipe['scope']='Frozen v83 dual CPU with original board pins/HIGH PLL100MHz/IO/hold; free placement, no inherited single-core PAP regions'
    write('fpga/pg2l100h/project/cpu_board.json',json.dumps(recipe,indent=2)+'\n')
    source=(ROOT/'scripts/soc/run_board.py').read_text(encoding='utf-8')
    source=replace_once(source,'"scripts/soc/run_board.py"','"scripts/soc/run_dual_board.py"')
    source=replace_once(source,'"tb/soc/tb_cpu_coremark.v"','"tb/cpu/tb_dual_board_coremark.v"')
    source=replace_once(source,'single_issue=1 indexed_btb=1','dual_issue=1 indexed_btb=1')
    source=replace_once(source,"            result['predictor'] = dict(btb=512", "            actual_pairs = re.findall(r'CPU_BOARD_DUAL_PAIR_PASS pairs=(\\d+)', log)\n            if len(actual_pairs) != 1 or int(actual_pairs[0]) <= 0:\n                raise RuntimeError('Missing real dual issue pairs')\n            result['actual_dual_pairs'] = int(actual_pairs[0])\n            result['actual_dual_issue'] = 1\n            result['predictor'] = dict(btb=512")
    write('scripts/soc/run_dual_board.py',source)
    write('tb/cpu/tb_dual_board_coremark.v',dual_testbench((ROOT/'tb/soc/tb_cpu_coremark.v').read_text(encoding='utf-8')))
    source=(ROOT/'scripts/soc/run_board_route.ps1').read_text(encoding='utf-8')
    source=replace_once(source,"'scripts/soc/run_board_route.ps1'","'scripts/soc/run_dual_board_route.ps1'")
    source=replace_once(source,"'triha_core')) 0 1 1","'triha_core')) 1 1 1")
    source=replace_once(source,"$commands=[Collections.Generic.List[object]]::new()", "$commands=[Collections.Generic.List[object]]::new()\n$privateTemp=Join-Path $work 'native-temp'\n[IO.Directory]::CreateDirectory($privateTemp)|Out-Null\n$env:TEMP=$privateTemp;$env:TMP=$privateTemp")
    write('scripts/soc/run_dual_board_route.ps1',source)
    source=(ROOT/'scripts/soc/package_board.py').read_text(encoding='utf-8').replace('single-issue','in-order dual-issue').replace('expect roughly17 seconds','wait at least10 seconds; actual duration is measured')
    write('scripts/soc/package_dual_board.py',source)
    port=(output/'sw/benchmarks/coremark/port/core_portme.c').read_text(encoding='utf-8')
    marker='    triha_puts("CoreMark running; precise scores follow the CRC report.\\n");'
    port=replace_once(port,marker,'    triha_puts("CPU_COREMARK_CONFIG stages=6 issue=2 memory=SRAM cache=0\\n");\n'+marker)
    write('sw/benchmarks/coremark/port/core_portme.c',port)
    for name,entry in manifest['sources'].items():require_digest((output/name).read_bytes(),entry['candidate_sha256'],name)
    for name,digest in original_hashes.items():require_digest(Path(origins[name]).read_bytes(),digest,'original '+name)
    record=dict(status='FROZEN_NOT_PROGRAMMED',project=str(output),accepted_cpu=ACCEPTED,
        accepted_result_sha256=sha(accepted/'result.json'),cpu_manifest=MANIFEST,cpu_manifest_sha256=sha(ROOT/MANIFEST),
        preparation_tool_sha256=sha(Path(__file__)),origins=origins,original_hashes=original_hashes,adapted_files=adapted,
        project_files={p.relative_to(output).as_posix():sha(p) for p in output.rglob('*') if p.is_file()},
        actual_dual_issue=1,cpu_hz=100000000,release_iterations=5000,preflight_iterations=5,optimization='-O2',
        board_status_leds_registered=register_status_leds,
        serial_port_opened=False,scope='Disposable explicit frozen build package; existing board validators/programmer retained, no root RTL edits')
    (output.parent/'prepared-board.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8',newline='\n')
    return output


def bootstrap(project):
    project=project.resolve();record=json.loads((project.parent/'prepared-board.json').read_text())
    for name,digest in record['project_files'].items():require_digest((project/name).read_bytes(),digest,name)
    work=project/'build/soc/dual-bootstrap-firmware';work.mkdir(parents=True,exist_ok=False)
    selected=[n for n in record['project_files'] if n.startswith(('sw/','config/'))]
    for name in selected:
        target=work/'src'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(project/name,target)
    sys.path.insert(0,str(project/'scripts/soc'))
    from coremark_board import build
    commands=[]
    def native(exe,args,label,timeout=120):
        command=[str(exe),*map(str,args)];r=subprocess.run(command,cwd=work,capture_output=True,timeout=timeout,creationflags=subprocess.CREATE_NO_WINDOW)
        (work/(label+'.log')).write_bytes(r.stdout+r.stderr);commands.append(dict(command=command,return_code=r.returncode))
        if r.returncode:raise RuntimeError(label+' failed')
        return (r.stdout+r.stderr).decode('utf-8',errors='replace')
    build(work,work,native,5000,cpu_luts=0)
    shutil.copyfile(ROOT/ACCEPTED/'rom.hex',work/'rom.hex')
    (work/'bootstrap.json').write_text(json.dumps(dict(status='BUILD_ONLY',commands=commands,programmed=False,serial_port_opened=False),indent=2)+'\n',encoding='utf-8',newline='\n')
    return work


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('mode',choices=['prepare','bootstrap']);parser.add_argument('directory',type=Path)
    parser.add_argument('--register-status-leds',action='store_true');args=parser.parse_args()
    print('DUAL_BOARD_'+args.mode.upper(),prepare(args.directory,args.register_status_leds) if args.mode=='prepare' else bootstrap(args.directory))

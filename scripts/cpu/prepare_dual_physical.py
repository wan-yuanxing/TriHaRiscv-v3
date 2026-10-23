"""Freeze real local-memory dual-issue PDS inputs without starting PDS."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[2]


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def verify_file_hashes(work, row):
    work=Path(work).resolve()
    if row['cpu_mode']!=1 or row['period_ns']!=10:
        raise ValueError('Expected dual issue at original 100MHz')
    for base,entries in [(work/'src',row['input_hashes']),(work,row['files'])]:
        for name,digest in entries.items():
            path=(base/name).resolve()
            if Path(name).is_absolute() or not path.is_relative_to(base.resolve()):
                raise ValueError('Frozen path escapes package')
            if sha(path)!=digest:raise ValueError('Frozen input drift: '+name)
    return row


def verify_package(work):
    work=Path(work).resolve()
    row=json.loads((work/'prepared.json').read_text(encoding='utf-8'))
    required={'simulation','simulation_result_sha256','status','pds_started','cpu_mode','period_ns','input_hashes','files'}
    if not required.issubset(row) or row['status']!='PREPARED_NOT_EXECUTED' or row['pds_started']:
        raise ValueError('Missing mandatory bound simulation/preparation evidence')
    if set(row['files'])!={'build.tcl','rom.hex','sram.hex','firmware.elf'}:
        raise ValueError('Incomplete physical firmware/Tcl evidence')
    verify_file_hashes(work,row)
    simulation=Path(row['simulation'])
    if sha(simulation/'result.json')!=row['simulation_result_sha256']:
        raise ValueError('Bound simulation result drift')
    evidence=json.loads((simulation/'result.json').read_text(encoding='utf-8'))
    actual=re.findall(r'SOC_DUAL_CONFIG actual=(\d+) pairs=(\d+)',(simulation/'simulation.log').read_text(encoding='utf-8'))
    if len(actual)!=1 or actual[0][0]!='1' or int(actual[0][1])<=0:
        raise ValueError('Bound simulation lacks actual dual pairing')
    check_simulation(dict(evidence,actual_dual_issue=int(actual[0][0])))
    for name,digest in evidence['output_hashes'].items():
        if sha(simulation/name)!=digest:raise ValueError('Bound simulation output drift: '+name)
    for name in ('rom.hex','sram.hex','firmware.elf'):
        if row['files'][name]!=evidence['output_hashes'][name]:
            raise ValueError('Physical firmware differs from measured image: '+name)
    core=json.loads((simulation/'src/fpga/pg2l100h/project/cpu_core.json').read_text(encoding='utf-8'))
    recipe=json.loads((ROOT/'fpga/pg2l100h/project/cpu_minimal_soc.json').read_text(encoding='utf-8'))
    names=set(core['sources']+core['headers']+recipe['sources']+recipe['headers'])
    if set(row['input_hashes'])!=names|{recipe['constraints']}:
        raise ValueError('Physical source set differs from measured boundary')
    for name in names:
        if row['input_hashes'][name]!=evidence['input_hashes'][name]:
            raise ValueError('Physical input differs from measured source: '+name)
    if row['input_hashes'][recipe['constraints']]!=sha(ROOT/recipe['constraints']):
        raise ValueError('Physical constraints differ from original system constraints')
    expected=tcl(work,core,core['sources']+recipe['sources'],recipe['constraints'])
    if (work/'build.tcl').read_text(encoding='utf-8')!=expected:
        raise ValueError('Physical Tcl differs from bounded route recipe')
    return row


def check_simulation(row):
    if row.get('status')!='PASS' or not row.get('source_unchanged') or not row.get('external_unchanged') or row.get('runner_return_code')!=0:
        raise ValueError('Need successful unchanged real-memory simulation')
    if row.get('test')!='coremark' or row.get('fault')!='none' or row.get('actual_dual_issue')!=1:
        raise ValueError('Need real dual-issue CoreMark evidence')


def tcl(work,core,sources,fdc):
    def path(p):return '{'+(work/'src'/p).as_posix()+'}'
    lines=[f"set_arch -family {core['family']} -device {core['device']} -speedgrade {core['speedgrade']} -package {core['package']}"]
    lines += ['add_design '+path(p) for p in sources]
    lines += ['add_constraint '+path(fdc)]
    lines += ['compile -top_module triha_minimal_soc -include_path {'+path('rtl/cpu/vendor/src/core')+' '+path('rtl/soc/include')+'}',
        'synthesize -ads -write_verilog TRUE','dev_map -detail',
        'pnr -action_timeout 10 -optimize_multi_corner_timing -fix_hold_violation -gplace_seed 1 -dump_router_congestion_plot TRUE',
        'report_timing -max_path 100']
    return '\n'.join(lines)+'\n'


def prepare(simulation,output):
    simulation=simulation.resolve();output=output.resolve()
    if output.exists() or not output.is_relative_to(ROOT/'build/cpu'):
        raise ValueError('Use a new directory below build/cpu')
    row=json.loads((simulation/'result.json').read_text(encoding='utf-8'))
    log=(simulation/'simulation.log').read_text(encoding='utf-8')
    actual=re.findall(r'SOC_DUAL_CONFIG actual=(\d+) pairs=(\d+)',log)
    if len(actual)!=1 or actual[0][0]!='1' or int(actual[0][1])<=0:
        raise ValueError('Missing actual dual mode/pairing')
    check_simulation(dict(row,actual_dual_issue=int(actual[0][0])))
    for p,h in row['output_hashes'].items():
        if sha(simulation/p)!=h:raise ValueError('Simulation output drift: '+p)
    for p,h in row['input_hashes'].items():
        if sha(simulation/'src'/p)!=h:raise ValueError('Simulation source drift: '+p)
    log=(simulation/'simulation.log').read_text(encoding='utf-8')
    if not re.search(r'SOC_DUAL_CONFIG actual=1 pairs=[1-9][0-9]*',log):
        raise ValueError('Missing actual dual mode/pairing')
    core=json.loads((simulation/'src/fpga/pg2l100h/project/cpu_core.json').read_text(encoding='utf-8'))
    recipe=json.loads((ROOT/'fpga/pg2l100h/project/cpu_minimal_soc.json').read_text(encoding='utf-8'))
    candidate=json.loads((ROOT/'docs/verification/cpu/dualissue_pairing_sources.json').read_text(encoding='utf-8'))
    for p,h in candidate['sources'].items():
        if p not in core['sources']:continue
        if sha(simulation/'src'/p)!=h['candidate_sha256']:raise ValueError('CPU differs from benchmark candidate')
    if recipe['period_ns']!=10:raise ValueError('Clock budget changed')
    names=sorted(set(core['sources']+core['headers']+recipe['sources']+recipe['headers']))
    frozen={}
    for name in names:
        src=simulation/'src'/name;dst=output/'src'/name
        dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst);frozen[name]=sha(dst)
    fdc=recipe['constraints'];dst=output/'src'/fdc;dst.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(ROOT/fdc,dst);frozen[fdc]=sha(dst)
    for name in ['rom.hex','sram.hex','firmware.elf']:
        shutil.copyfile(simulation/name,output/name)
    (output/'build.tcl').write_text(tcl(output,core,core['sources']+recipe['sources'],fdc),encoding='utf-8',newline='\n')
    prepared=dict(status='PREPARED_NOT_EXECUTED',simulation=str(simulation),simulation_result_sha256=sha(simulation/'result.json'),
        cpu_mode=1,period_ns=10,boundary='Real 8KiB ROM/32KiB SRAM/MMIO, external system clock; no board pins or PLL',
        input_hashes=frozen,files={p.name:sha(p) for p in output.iterdir() if p.is_file()},
        timing_closed=False,pds_started=False,board_validated=False,
        required_acceptance=['compile hierarchy dual=1; six stages and predictor settings bound',
        'fresh compile/synthesize/dev_map/pnr/report_timing success',
        'Slow/Fast setup hold pulse-width all pass; performance slack consistent',
        'unchanged hashes; original 100MHz I/O/hold constraints',
        'u_core area only; memory/fixture area separately',
        'SRAM benchmark is distinct from 128KiB simulated TCM'])
    (output/'prepared.json').write_text(json.dumps(prepared,indent=2)+'\n',encoding='utf-8',newline='\n')
    return prepared

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('simulation',type=Path);parser.add_argument('output',type=Path,nargs='?');parser.add_argument('--verify',action='store_true')
    args=parser.parse_args()
    if args.verify:
        verify_package(args.simulation);print('FROZEN_PACKAGE_PASS')
    else:
        if args.output is None:parser.error('output is required for preparation')
        print(prepare(args.simulation,args.output)['status'])

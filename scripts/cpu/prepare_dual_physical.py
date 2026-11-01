"""Freeze real local-memory dual-issue PDS inputs without starting PDS."""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[2]


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def clock_period(clock_hz):
    if type(clock_hz) is not int or clock_hz not in (95000000,100000000):
        raise ValueError('Clock must be original 100MHz or explicit user-authorized 95MHz')
    return 1000000000/clock_hz


def clock_constraints(original,clock_hz):
    period=clock_period(clock_hz)
    if clock_hz==100000000:return original
    needle=b'create_clock -name cpu_clk -period 10.000 [get_ports {clk_i}]'
    if original.count(needle)!=1:raise ValueError('Expected one original 10ns clock declaration')
    replacement=b'create_clock -name cpu_clk -period '+f'{period:.9f}'.encode('ascii')+b' [get_ports {clk_i}]'
    return original.replace(needle,replacement)


def physical_constraints(compact=False,io_registers=False,central=False,datapath=False):
    if sum(bool(value) for value in (compact,io_registers,central,datapath))>1:
        raise ValueError('Choose region placement or output register packing separately')
    if compact:return ['fpga/pg2l100h/constraints/cpu_minimal_soc_compact.fdc']
    if central:return ['fpga/pg2l100h/constraints/cpu_minimal_soc_central.fdc']
    if datapath:return ['fpga/pg2l100h/constraints/cpu_minimal_soc_datapath.fdc']
    if io_registers:return ['fpga/pg2l100h/constraints/cpu_io_registers.fdc']
    return []


def verify_file_hashes(work, row):
    work=Path(work).resolve()
    expected=clock_period(row.get('clock_hz',100000000))
    if row['cpu_mode']!=1 or type(row['period_ns']) not in (int,float) or not math.isfinite(row['period_ns']) or abs(row['period_ns']-expected)>1e-9:
        raise ValueError('Expected dual issue with consistent explicit clock metadata')
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
    physical=row.get('physical_constraints',[])
    if physical not in ([],physical_constraints(compact=True),physical_constraints(io_registers=True),physical_constraints(central=True),physical_constraints(datapath=True)):
        raise ValueError('Unsupported physical constraint set')
    for name in physical:
        if row['input_hashes'].get(name)!=sha(ROOT/name):raise ValueError('Physical implementation attribute drift')
    if set(row['input_hashes'])!=names|{recipe['constraints']}|set(physical):
        raise ValueError('Physical source set differs from measured boundary')
    for name in names:
        if row['input_hashes'][name]!=evidence['input_hashes'][name]:
            raise ValueError('Physical input differs from measured source: '+name)
    expected_fdc=clock_constraints((ROOT/recipe['constraints']).read_bytes(),row.get('clock_hz',100000000))
    if row['input_hashes'][recipe['constraints']]!=hashlib.sha256(expected_fdc).hexdigest():
        raise ValueError('Physical constraints differ beyond the authorized clock period')
    minutes=row.get('pnr_minutes',10)
    if ('pnr_minutes' in row)!=('outer_seconds' in row) or type(minutes) is not int or not 1<=minutes<=60 or row.get('outer_seconds',900)!=minutes*60+300:
        raise ValueError('Invalid bounded PDS execution budget')
    expected=tcl(work,core,core['sources']+recipe['sources'],recipe['constraints'],minutes,physical,row.get('placement_seed',1),row.get('retiming',False))
    if (work/'build.tcl').read_text(encoding='utf-8')!=expected:
        raise ValueError('Physical Tcl differs from bounded route recipe')
    return row


def check_simulation(row):
    if row.get('status')!='PASS' or not row.get('source_unchanged') or not row.get('external_unchanged') or row.get('runner_return_code')!=0:
        raise ValueError('Need successful unchanged real-memory simulation')
    if row.get('test')!='coremark' or row.get('fault')!='none' or row.get('actual_dual_issue')!=1:
        raise ValueError('Need real dual-issue CoreMark evidence')


def checked_seed(placement_seed):
    if type(placement_seed) is not int or placement_seed not in (1,8):
        raise ValueError('Placement seed must be 1 or the bounded comparison seed 8')
    return placement_seed


def checked_retiming(retiming):
    if type(retiming) is not bool:
        raise ValueError('Retiming metadata must be boolean')
    return retiming


def tcl(work,core,sources,fdc,pnr_minutes=10,physical_constraints=(),placement_seed=1,retiming=False):
    placement_seed=checked_seed(placement_seed)
    retiming=checked_retiming(retiming)
    def path(p):return '{'+(work/'src'/p).as_posix()+'}'
    lines=[f"set_arch -family {core['family']} -device {core['device']} -speedgrade {core['speedgrade']} -package {core['package']}"]
    lines += ['add_design '+path(p) for p in sources]
    lines += ['add_constraint '+path(fdc)]
    lines += ['add_constraint '+path(name) for name in physical_constraints]
    lines += ['compile -top_module triha_minimal_soc -include_path {'+path('rtl/cpu/vendor/src/core')+' '+path('rtl/soc/include')+'}',
        'synthesize -ads -write_verilog TRUE'+(' -retiming' if retiming else ''),'dev_map -detail',
        f'pnr -action_timeout {pnr_minutes} -optimize_multi_corner_timing -fix_hold_violation -gplace_seed {placement_seed} -dump_router_congestion_plot TRUE',
        'report_timing -max_path 100']
    return '\n'.join(lines)+'\n'


def prepare(simulation,output,pnr_minutes=10,compact=False,io_registers=False,placement_seed=1,retiming=False,central=False,datapath=False,clock_hz=100000000):
    if type(pnr_minutes) is not int or not 1<=pnr_minutes<=60:raise ValueError('PNR minutes must be 1..60')
    period_ns=clock_period(clock_hz)
    placement_seed=checked_seed(placement_seed)
    retiming=checked_retiming(retiming)
    physical=physical_constraints(compact,io_registers,central,datapath)
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
    manifest_source=simulation/'src'/row['candidate_manifest'] if 'candidate_manifest' in row else ROOT/'docs/verification/cpu/dualissue_pairing_sources.json'
    candidate=json.loads(manifest_source.read_text(encoding='utf-8'))
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
    dst.write_bytes(clock_constraints((ROOT/fdc).read_bytes(),clock_hz));frozen[fdc]=sha(dst)
    for name in physical:
        dst=output/'src'/name;dst.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/name,dst);frozen[name]=sha(dst)
    for name in ['rom.hex','sram.hex','firmware.elf']:
        shutil.copyfile(simulation/name,output/name)
    (output/'build.tcl').write_text(tcl(output,core,core['sources']+recipe['sources'],fdc,pnr_minutes,physical,placement_seed,retiming),encoding='utf-8',newline='\n')
    prepared=dict(status='PREPARED_NOT_EXECUTED',simulation=str(simulation),simulation_result_sha256=sha(simulation/'result.json'),
        physical_constraints=physical,placement_seed=placement_seed,retiming=retiming,pnr_minutes=pnr_minutes,outer_seconds=pnr_minutes*60+300,cpu_mode=1,period_ns=period_ns,boundary='Real 8KiB ROM/32KiB SRAM/MMIO, external system clock; no board pins or PLL',
        input_hashes=frozen,files={p.name:sha(p) for p in output.iterdir() if p.is_file()},
        timing_closed=False,pds_started=False,board_validated=False,
        required_acceptance=['compile hierarchy dual=1; six stages and predictor settings bound',
        'fresh compile/synthesize/dev_map/pnr/report_timing success',
        'Slow/Fast setup hold pulse-width all pass; performance slack consistent',
        'unchanged hashes; original I/O/hold constraints; default 100MHz or explicit 95MHz clock',
        'u_core area only; memory/fixture area separately',
        'SRAM benchmark is distinct from 128KiB simulated TCM'])
    if clock_hz!=100000000:prepared['clock_hz']=clock_hz
    (output/'prepared.json').write_text(json.dumps(prepared,indent=2)+'\n',encoding='utf-8',newline='\n')
    return prepared

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('simulation',type=Path);parser.add_argument('output',type=Path,nargs='?');parser.add_argument('--verify',action='store_true');parser.add_argument('--pnr-minutes',type=int,default=10)
    parser.add_argument('--placement-seed',type=int,choices=[1,8],default=1,help='Original placement or one bounded seed-8 comparison; constraints unchanged')
    parser.add_argument('--retiming',action='store_true',help='Explicit ADS register-retiming diagnostic; RTL and constraints unchanged')
    parser.add_argument('--clock-hz',type=int,choices=[95000000,100000000],default=100000000,help='Original 100MHz or user-authorized 95MHz; change only the clock period')
    physical=parser.add_mutually_exclusive_group()
    physical.add_argument('--compact',action='store_true')
    physical.add_argument('--io-registers',action='store_true',help='Pack existing port FFs; no region or timing exceptions')
    physical.add_argument('--central',action='store_true',help='One central CPU clock region with existing IO register packing; no timing exceptions')
    physical.add_argument('--datapath-region',action='store_true',help='Constrain only critical datapath/queue; predictor and hard multiplier unconfined')
    args=parser.parse_args()
    if args.verify:
        verify_package(args.simulation);print('FROZEN_PACKAGE_PASS')
    else:
        if args.output is None:parser.error('output is required for preparation')
        print(prepare(args.simulation,args.output,args.pnr_minutes,args.compact,args.io_registers,args.placement_seed,args.retiming,args.central,args.datapath_region,args.clock_hz)['status'])

"""Native tests of the production CPU/router with explicitly fake peripherals."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/cpu'))
from admission_common import SIM, sha, save, validate
from run_isa_regression import native

PRODUCTION = [
    'rtl/soc/triha_sram.v', 'rtl/soc/triha_boot_rom.v',
    'rtl/soc/cpu_native_axil.v', 'rtl/soc/triha_application_router.v',
    'rtl/soc/triha_application_cpu.v',
]
TEST_INPUTS = ['tb/soc/tb_application_cpu.sv', 'sw/tests/application_control/start.S',
               'sw/tests/application_control/link.ld', 'scripts/soc/run_application_cpu.py',
               'scripts/cpu/admission_common.py', 'scripts/cpu/run_isa_regression.py',
               'scripts/cpu/run_modelsim.do', 'config/cpu_admission.json', 'config/cpu_toolchain.json']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=['router', 'cpu', 'all'], default='all')
    parser.add_argument('--broken', action='store_true', help='Corrupt Video model readback; expect host return 1')
    parser.add_argument('--minimal-control', type=int, choices=[0,1], default=0)
    args = parser.parse_args()
    work = ROOT / 'build/soc' / ('application_cpu-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    row = dict(status='RUNNING', suite=args.suite, broken=args.broken, input_hashes={},
               minimal_control_cpu=args.minimal_control, dual_issue=0,
               external_hashes={}, commands=[], runs=[], runner_return_code=1,
               scope='Production CPU/router/cache/local memories and two native AXI-Lite adapters; fake NPU/Video control endpoints and fake DDR only; no actual operator/video/shared fabric/CDC/physical timing acceptance')
    save(work/'result.json', row)
    print('APPLICATION_CPU_RUN', work, flush=True)

    def invoke(executable, options, label):
        executable = Path(executable)
        row['external_hashes'][str(executable)] = sha(executable)
        record, text = native(executable, options, work, work/(label+'.log'), 120)
        row['commands'].append(record)
        if record['timed_out']:
            raise RuntimeError(label+' wall timeout')
        return record, text

    try:
        admitted = validate()
        sources = admitted['core']['sources'] + admitted['cache_sources'] + PRODUCTION
        (work/'production_sources.f').write_text('+incdir+rtl/cpu/vendor/src/core\n'+'\n'.join(sources)+'\n', encoding='utf-8')
        names = sources + admitted['core']['headers'] + TEST_INPUTS
        for name in sorted(set(names)):
            source, target = ROOT/name, work/'src'/name
            if not source.is_file():
                raise RuntimeError('missing production/test source: '+name)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            row['input_hashes'][name] = sha(source)
        gcc = Path(json.loads((ROOT/'config/cpu_toolchain.json').read_text())['compiler'])
        record, text = invoke(gcc, ['-march=rv32im_zicsr_zifencei', '-mabi=ilp32', '-O2',
            '-mcmodel=medany', '-mno-relax', '-nostdlib', '-Wl,--build-id=none',
            '-T',work/'src/sw/tests/application_control/link.ld',
            '-o',work/'firmware.elf',work/'src/sw/tests/application_control/start.S'], 'firmware')
        if record['return_code']:
            raise RuntimeError('firmware build failed')
        elf = (work/'firmware.elf').read_bytes()
        if elf[:7] != b'\x7fELF\x01\x01\x01' or struct.unpack_from('<H',elf,18)[0] != 243:
            raise ValueError('expected RISC-V ELF32')
        if struct.unpack_from('<I',elf,24)[0] != 0x10000:
            raise ValueError('unexpected SRAM entry')
        sram = bytearray([0xa5]*32768)
        offset = struct.unpack_from('<I',elf,28)[0]
        size, count = struct.unpack_from('<HH',elf,42)
        for i in range(count):
            kind,start,va,pa,filesz,memsz = struct.unpack_from('<6I',elf,offset+i*size)
            if kind == 1:
                local = pa-0x10000
                if va!=pa or not 0<=local<=len(sram) or filesz>memsz or local+memsz>len(sram) or start+filesz>len(elf):
                    raise ValueError('firmware exceeds SRAM')
                sram[local:local+filesz] = elf[start:start+filesz]
        rom = bytearray(b'\x73\x00\x10\x00'*2048)
        rom[:8] = struct.pack('<II',0x000102b7,0x00028067)
        for name,image in [('rom',rom),('sram',sram)]:
            (work/(name+'.hex')).write_text(''.join(f'{int.from_bytes(image[n:n+8],"little"):016x}\n' for n in range(0,len(image),8)),encoding='utf-8')
        row['generated_hashes'] = {name:sha(work/name) for name in ['firmware.elf','rom.hex','sram.hex']}
        primitives = admitted['simulation_models']
        for model in primitives:
            row['external_hashes'][model['path']] = model['sha256']
        for tool,options in [('vsim',['-version']),('vmap',['-c']),('vlib',['work']),
                             ('vlog',['-sv','-mfcu','+incdir+'+(work/'src/rtl/cpu/vendor/src/core').as_posix(),
                                      *[work/'src'/p for p in sources+['tb/soc/tb_application_cpu.sv']],
                                      *[p['path'] for p in primitives]])]:
            record,text = invoke(SIM/(tool+'.exe'),options,tool)
            if record['return_code'] or '** Error' in text:
                raise RuntimeError(tool+' failed')
        for mode in (['router','cpu'] if args.suite=='all' else [args.suite]):
            record,text = invoke(SIM/'vsim.exe',['-c','-onfinish','exit','-voptargs=+acc',
                '-gCPU_MODE='+str(int(mode=='cpu')),'-gBROKEN='+str(int(args.broken)),
                '-gMINIMAL_CONTROL_CPU='+str(args.minimal_control),
                'work.tb_application_cpu','-do',work/'src/scripts/cpu/run_modelsim.do'],mode)
            marker = 'APPLICATION_'+('CPU' if mode=='cpu' else 'ROUTER')+'_PASS'
            negative_marker = 'APPLICATION_FAIL '+('firmware completion' if mode=='cpu' else 'data readback')
            negative = args.broken and negative_marker in text and '** Fatal' in text
            good = not record['return_code'] and marker in text and 'APPLICATION_FAIL' not in text
            row['runs'].append({'mode':mode,'status':'PASS' if good else 'FAIL',
                                'negative_rejected':negative,'native_return_code':record['return_code'],
                                'marker':next((s for s in text.splitlines() if marker in s or negative_marker in s),None)})
            if not good and not negative:
                raise RuntimeError(mode+' functional check failed')
        row.update(status='FAIL' if args.broken else 'PASS',runner_return_code=1 if args.broken else 0,
                   negative_rejected=args.broken and all(x['negative_rejected'] for x in row['runs']))
    except Exception as error:
        row.update(status='FAIL',error=str(error),runner_return_code=1)
    finally:
        row['source_unchanged'] = all(sha(ROOT/p)==h and sha(work/'src'/p)==h for p,h in row['input_hashes'].items())
        row['external_unchanged'] = all(sha(p)==h for p,h in row['external_hashes'].items())
        row['generated_unchanged'] = all(sha(work/p)==h for p,h in row.get('generated_hashes',{}).items())
        if not all(row[k] for k in ['source_unchanged','external_unchanged','generated_unchanged']):
            row.update(status='FAIL',error='inputs changed during run',runner_return_code=1)
        row['output_hashes'] = {p.relative_to(work).as_posix():sha(p) for p in work.rglob('*') if p.is_file() and p.name!='result.json'}
        save(work/'result.json',row)
    print(row['status'],row.get('error',''),row['runs'],work/'result.json',flush=True)
    return row['runner_return_code']


if __name__=='__main__':
    sys.exit(main())

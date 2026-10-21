"""CPU/DDR board wrapper DIGITAL simulation and O2 standalone self-test image."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import struct
import subprocess
import time

from run_cache import ROOT, SIM, save, sha
from prepare_ddr import materialize
from gen_ddr_board import generate
from review_cache_soc import verify_run


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--test', choices=['boot','no-init','init-loss','clock-stop','cpu-pll-loss'], default='boot')
    parser.add_argument('--fault', choices=['none','data'], default='none')
    args = parser.parse_args()
    mode = ['boot','no-init','init-loss','clock-stop','cpu-pll-loss'].index(args.test)
    work = ROOT/'build/cpu'/('ddr-board-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    print('CPU_DDR_BOARD_RUN', work, flush=True)
    row = dict(status='RUNNING', test=args.test, fault=args.fault, input_hashes={}, external_hashes={},
        output_hashes={}, commands=[], programmed=False, physical_ddr_validated=False,
        scope='Board wrapper DIGITAL substitutes and real O2 software; no analog training, actual PLL/PHY or timing acceptance')
    started = time.monotonic()
    save(work/'result.json', row)
    def native(exe, arguments, label, timeout=180):
        command = [str(exe), *[p.as_posix() if isinstance(p,Path) else str(p) for p in arguments]]
        record = dict(command=command, return_code=None, timed_out=False)
        row['commands'].append(record)
        row['external_hashes'][str(exe)] = sha(exe)
        process = subprocess.Popen(command,cwd=work,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        try:
            output,_ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            record['timed_out'] = True
            subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],capture_output=True)
            output,_ = process.communicate()
        record['return_code'] = process.returncode
        (work/(label+'.log')).write_bytes(output)
        if process.returncode or record['timed_out']:
            raise RuntimeError(f'{label} returned {process.returncode}; timed_out={record["timed_out"]}')
        return output.decode('utf-8',errors='replace')
    try:
        generate(check=True)
        row['binding'] = materialize(work)
        row['external_hashes'][row['binding']['git']] = row['binding']['git_sha256']
        base = json.loads((ROOT/'fpga/pg2l100h/project/cpu_cached_soc.json').read_text(encoding='utf-8'))
        sources = base['sources']+['rtl/soc/triha_axi128_cdc.v','rtl/soc/triha_cpu_ddr.v',
            'fpga/pg2l100h/rtl/triha_cpu_ddr_supervisor.v','fpga/pg2l100h/rtl/triha_cpu_ddr_board_top.v']
        paths = sources+base['headers']+['tb/soc/tb_cpu_ddr_board.v','tb/soc/cpu_board_pll_model.v',
            'tb/video/models/ddr_board_ip_model.sv','sw/tests/cpu_ddr_board.c','sw/runtime/crt0.S',
            'sw/runtime/triha_runtime.c','sw/runtime/triha_runtime.h','sw/runtime/triha_sram.ld',
            'sw/runtime/soc_map.h','sw/runtime/cpu_cache_map.h','sw/runtime/cpu_ddr_board.h',
            'rtl/soc/include/cpu_ddr_board_cfg.vh','scripts/cpu/run_ddr_board.py','scripts/cpu/run_cache.py',
            'scripts/cpu/prepare_ddr.py','scripts/cpu/gen_ddr_board.py','scripts/cpu/run_modelsim.do',
            'config/cpu_ddr_board.json','config/cpu_ddr.json','config/cpu_toolchain.json',
            'config/cpu_primitives.json','fpga/pg2l100h/project/cpu_cached_soc.json']
        primitives=[]
        for entry in json.loads((ROOT/'config/cpu_primitives.json').read_text(encoding='utf-8'))['simulation_models']:
            if sha(entry['path']) != entry['sha256']:
                raise ValueError('PDS primitive model changed')
            primitives.append(Path(entry['path']))
            row['external_hashes'][entry['path']] = entry['sha256']
        for name in sorted(set(paths)):
            if not (ROOT/name).is_file():
                continue
            row['input_hashes'][name] = sha(ROOT/name)
            dest=work/'src'/name
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(ROOT/name,dest)
        gcc=Path(json.loads((ROOT/'config/cpu_toolchain.json').read_text(encoding='utf-8'))['compiler'])
        native(gcc,['--version'],'gcc-version')
        flags=['-march=rv32im_zicsr','-mabi=ilp32','-O2','-mcmodel=medany','-mno-relax','-msmall-data-limit=0',
            '-ffreestanding','-fno-builtin','-ffunction-sections','-fdata-sections','-Wall','-Wextra','-DTRIHA_SOC_MMIO=1']
        row['compiler_flags']=flags
        native(gcc,flags+['-I',work/'src/sw/runtime','-nostdlib','-T',work/'src/sw/runtime/triha_sram.ld',
            '-Wl,--gc-sections,--build-id=none','-Wl,-Map='+str(work/'firmware.map'),'-o',work/'firmware.elf',
            work/'src/sw/runtime/crt0.S',work/'src/sw/runtime/triha_runtime.c',work/'src/sw/tests/cpu_ddr_board.c','-lgcc'],'firmware')
        elf=(work/'firmware.elf').read_bytes()
        image=bytearray([0xa5]*32768)
        off=struct.unpack_from('<I',elf,28)[0]
        size,count=struct.unpack_from('<HH',elf,42)
        if struct.unpack_from('<I',elf,24)[0] != 0x10000:
            raise ValueError('wrong SRAM entry')
        for n in range(count):
            kind,start,va,pa,filesz,memsz=struct.unpack_from('<6I',elf,off+n*size)
            if kind != 1: continue
            relative=pa-0x10000
            if va != pa or not 0 <= relative or filesz > memsz or relative+memsz > len(image):
                raise ValueError('software image outside SRAM')
            image[relative:relative+filesz]=elf[start:start+filesz]
        rom=bytearray(b'\x73\x00\x10\x00'*2048)
        rom[:8]=struct.pack('<II',0x000102b7,0x00028067)
        for name,data in [('rom',rom),('sram',image)]:
            (work/(name+'.hex')).write_text(''.join(f'{int.from_bytes(data[n:n+8],"little"):016x}\n' for n in range(0,len(data),8)),encoding='utf-8',newline='\n')
        model=(work/'src/tb/video/models/ddr_board_ip_model.sv').read_text(encoding='utf-8')
        if model.count('.MEMORY_SLOTS(128)') != 1 or model.count('.fault_mode(0)') != 1:
            raise ValueError('digital DDR model anchors changed')
        model=model.replace('.MEMORY_SLOTS(128)','.MEMORY_SLOTS(1024)').replace('.fault_mode(0)','.fault_mode(model_fault_mode)')
        model=model.replace('    reg model_init_enable=1,','    integer model_fault_mode=0;\n    reg model_init_enable=1,')
        (work/'ddr_board_model.sv').write_text(model,encoding='utf-8',newline='\n')
        native(SIM/'vsim.exe',['-version'],'modelsim-version')
        native(SIM/'vmap.exe',['-c'],'vmap');native(SIM/'vlib.exe',['work'],'vlib')
        native(SIM/'vlog.exe',['+incdir+'+(work/'src/rtl/soc/include').as_posix(),
            '+incdir+'+(work/'src/rtl/cpu/vendor/src/core').as_posix(),
            work/'pinned/rtl/video/video_async_fifo.sv',work/'pinned/rtl/video/axi128_hmic256.sv',
            work/'pinned/tb/video/models/ddr_native_model.sv',work/'ddr_board_model.sv',
            work/'src/tb/soc/cpu_board_pll_model.v',*[work/'src'/p for p in sources],
            work/'src/tb/soc/tb_cpu_ddr_board.v',*primitives],'compile')
        output=native(SIM/'vsim.exe',['-c','-onfinish','exit','-voptargs=+acc','-gTEST_MODE='+str(mode),
            '-gCORRUPT_DATA='+str(int(args.fault=='data')),'work.tb_cpu_ddr_board','-do',work/'src/scripts/cpu/run_modelsim.do'],'simulation',600)
        marker='CPU_DDR_BOARD_PASS' if mode==0 else 'CPU_DDR_BOARD_MONITOR_PASS'
        if marker not in output or any(s in output for s in ['CPU_DDR_BOARD_FAIL','** Fatal','** Error']):
            raise RuntimeError('digital board self-check failed')
        row.update(status='PASS',runner_return_code=0)
    except Exception as error:
        row.update(status='FAIL',runner_return_code=1,error=str(error))
    finally:
        row['source_unchanged']=all(sha(ROOT/p)==h for p,h in row['input_hashes'].items())
        row['external_unchanged']=all(sha(p)==h for p,h in row['external_hashes'].items())
        row['pinned_unchanged']=all(sha(p['path'])==p['sha256'] for p in row.get('binding',{}).get('files',{}).values())
        if not (row['source_unchanged'] and row['external_unchanged'] and row['pinned_unchanged']):
            row.update(status='FAIL',runner_return_code=1,error='board validation inputs changed')
        row['output_hashes']={p.relative_to(work).as_posix():sha(p) for p in work.rglob('*') if p.is_file() and p.name!='result.json'}
        row['elapsed_seconds']=round(time.monotonic()-started,3)
        save(work/'result.json',row)
    print(row['status'],row.get('error',''),flush=True)
    return row['runner_return_code']


if __name__=='__main__':
    raise SystemExit(main())

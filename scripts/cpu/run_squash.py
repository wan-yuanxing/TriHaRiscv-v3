"""Windows ModelSim whole-core wrong-path side-effect checks."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
from admission_common import sha, save, SIM, validate

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--negative', choices=['none','store','mmio','csr','load'], default='none')
    parser.add_argument('--delay', type=int, choices=[32,64], default=32)
    args = parser.parse_args()
    work = ROOT/'build/cpu'/('squash-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    row = dict(status='RUNNING',negative=args.negative,delay=args.delay,input_hashes={},external_hashes={},
               commands=[],output_hashes={},runner_return_code=1,
               scope='Six-stage single-issue CPU public-port functional simulation; memory/MMIO models, no cache/DDR/physical timing')
    print('CPU_SQUASH_RUN',work,flush=True)

    def native(exe, arguments, label):
        row['external_hashes'][str(exe)] = sha(exe)
        record = dict(command=[str(exe),*map(str,arguments)],return_code=None,timed_out=False)
        row['commands'].append(record)
        process = subprocess.Popen(record['command'],cwd=work,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        try:
            output,_ = process.communicate(timeout=90)
        except subprocess.TimeoutExpired:
            record['timed_out'] = True
            subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],capture_output=True)
            output,_ = process.communicate()
        record['return_code'] = process.returncode
        (work/(label+'.log')).write_bytes(output)
        if process.returncode or record['timed_out']:
            raise RuntimeError(f'{label}: return={process.returncode} timeout={record["timed_out"]}')
        return output.decode('utf-8',errors='replace')

    save(work/'result.json',row)
    try:
        admission = validate(ROOT)
        project = admission['core']
        sources = project['sources'] + ['tb/cpu/tb_cpu_squash.v']
        inputs = sources + project['headers'] + ['config/cpu_admission.json',
            'config/cpu_sources.f','config/cpu_toolchain.json','rtl/cpu/ADAPTATIONS.json',
            'rtl/cpu/vendor/LICENSE','rtl/cpu/vendor/UPSTREAM.json','sw/tests/squash_runtime.S',
            'sw/runtime/triha_tcm.ld','scripts/cpu/run_squash.py','scripts/cpu/admission_common.py']
        for name in sorted(set(inputs)):
            src = ROOT/name; dest = work/'src'/name
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(src,dest)
            row['input_hashes'][name] = sha(src)
        primitives = []
        for model in admission['simulation_models']:
            assert sha(model['path']) == model['sha256']
            primitives.append(model['path'])
            row['external_hashes'][model['path']] = model['sha256']
        gcc = Path(json.loads((ROOT/'config/cpu_toolchain.json').read_text())['compiler'])
        native(gcc,['--version'],'gcc-version')
        leak = dict(none=0,store=1,mmio=2,csr=3,load=0)[args.negative]
        native(gcc,['-march=rv32im_zicsr','-mabi=ilp32','-O2','-mcmodel=medany','-mno-relax',
            '-nostdlib','-Wl,--build-id=none','-T',work/'src/sw/runtime/triha_tcm.ld',
            '-DLEAK_BRANCH='+str(leak),'-Wl,-Map='+str(work/'firmware.map'),
            '-o',work/'firmware.elf',work/'src/sw/tests/squash_runtime.S'],'firmware')
        elf = (work/'firmware.elf').read_bytes()
        assert elf[:7] == b'\x7fELF\x01\x01\x01' and struct.unpack_from('<H',elf,18)[0] == 243
        assert struct.unpack_from('<I',elf,24)[0] == 0x80000000
        image = bytearray([0xa5]*131072)
        offset = struct.unpack_from('<I',elf,28)[0]
        size,count = struct.unpack_from('<HH',elf,42)
        for index in range(count):
            kind,start,va,pa,filesz,memsz = struct.unpack_from('<6I',elf,offset+index*size)
            if kind == 1:
                local = pa-0x80000000
                assert va == pa and filesz <= memsz and 0 <= local and local+memsz <= len(image)
                image[local:local+filesz] = elf[start:start+filesz]
        (work/'firmware.hex').write_text(''.join(f'{int.from_bytes(image[i:i+4],"little"):08x}\n' for i in range(0,len(image),4)),encoding='utf-8')
        symbol_text = native(gcc.parent/'riscv-none-elf-nm.exe',['-n',work/'firmware.elf'],'symbols')
        symbols = {name:int(address,16) for address,name in re.findall(r'(?m)^([0-9a-f]+)\s+\w\s+(\w+)\s*$',symbol_text)}
        required = [f'{prefix}_{i}' for i in range(1,4) for prefix in ('bad_b','resume_b')] + [f'{prefix}_{i}' for i in range(1,5) for prefix in ('fault','bad_f','resume_f','after_f')]
        assert all(name in symbols for name in required)
        header = work/'squash_symbols.vh'
        header.write_text(''.join(f'`define {name.upper()} 32\'h{symbols[name]:08x}\n' for name in required),encoding='utf-8')
        row['symbols'] = symbols
        row['generated_input_hashes'] = {header.name:sha(header)}
        native(SIM/'vsim.exe',['-version'],'modelsim-version')
        native(SIM/'vmap.exe',['-c'],'vmap')
        native(SIM/'vlib.exe',['work'],'vlib')
        native(SIM/'vlog.exe',['+incdir+'+(work/'src/rtl/cpu/vendor/src/core').as_posix(),
            '+incdir+'+work.as_posix(),*[work/'src'/name for name in sources],*primitives],'compile')
        names = ('clk rst_n i_pc i_req i_valid saved_i_pc d_addr d_wr d_rd d_accept d_pending '
                 'd_ack d_error d_data saved_addr delay_left squash redirect redirect_pc decode_pc decode_valid '
                 'mscratch mepc mcause mtval wrong_fetched wrong_decoded recovered wb_pc wb_rd wb_valid wb_data '
                 'traps returns fault_returns normal_stores mmio_writes csr_writes')
        signals = ['/tb_cpu_squash/'+name for name in names.split()]
        lines = ['onerror {quit -f -code 2}','onbreak {quit -f -code 3}','vcd file {squash.vcd}']
        for signal in signals:
            lines += ['log '+signal,'vcd add '+signal]
        lines += ['run -all','quit -f -code 0']
        (work/'capture.do').write_text('\n'.join(lines)+'\n',encoding='utf-8')
        output = native(SIM/'vsim.exe',['-c','-onfinish','exit','-voptargs=+acc','-wlf','squash.wlf',
            '-gRESPONSE_DELAY='+str(args.delay),'-gCORRUPT_FAULT='+str(int(args.negative=='load')),
            'work.tb_cpu_squash','-do',work/'capture.do'],'simulation')
        if args.negative != 'none':
            reason = dict(store='wrong-path SRAM store',mmio='wrong-path MMIO write',csr='wrong-path CSR write',
                          load='wrong-path SRAM store')[args.negative]
            assert 'CPU_SQUASH_FAIL '+reason in output and '** Fatal:' in output, 'negative did not reach intended check'
            row.update(status='FAIL',negative_rejected=True,negative_reason=reason,runner_return_code=1)
        else:
            assert 'CPU_SQUASH_PASS' in output and not re.search(r'CPU_SQUASH_FAIL|\*\* (Error|Fatal)',output)
            line = next(line for line in output.splitlines() if 'CPU_SQUASH_PASS' in line)
            row.update(status='PASS',runner_return_code=0,pass_line=line,
                       statistics={key:int(value) for key,value in re.findall(r'(\w+)=(\d+)(?:\s|$)',line)})
    except Exception as error:
        row.update(status='FAIL',error=f'{type(error).__name__}: {error}',runner_return_code=1)
    finally:
        row['source_unchanged'] = all(sha(ROOT/p)==h and sha(work/'src'/p)==h for p,h in row['input_hashes'].items())
        row['external_unchanged'] = all(sha(p)==h for p,h in row['external_hashes'].items())
        row['generated_unchanged'] = all(sha(work/p)==h for p,h in row.get('generated_input_hashes',{}).items())
        if not all(row[k] for k in ('source_unchanged','external_unchanged','generated_unchanged')):
            row.update(status='FAIL',error='frozen inputs changed',runner_return_code=1)
        row['output_hashes'] = {p.relative_to(work).as_posix():sha(p) for p in work.rglob('*') if p.is_file() and p.name != 'result.json'}
        save(work/'result.json',row)
    print(row['status'],row.get('negative_reason',row.get('error','')),work/'result.json',flush=True)
    return row['runner_return_code']


if __name__ == '__main__':
    sys.exit(main())

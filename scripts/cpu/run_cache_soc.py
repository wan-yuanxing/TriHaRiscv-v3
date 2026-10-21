"""Frozen-input native verification of local memory plus the paired-cache router."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import time

from check_cache import validate, ROOT
from gen_cache_soc import generate
from run_cache import sha, save, SIM


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--test', choices=['router', 'runtime'], default='router')
    parser.add_argument('--fault', choices=['none', 'data', 'watchdog'], default='none')
    parser.add_argument('--bypass-caches', action='store_true')
    args = parser.parse_args()
    work = ROOT/'build/cpu'/('cache-soc-'+args.test+'-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    print('CPU_CACHE_SOC_RUN', work, flush=True)
    result = dict(status='RUNNING', test=args.test, fault=args.fault, cache_enable=not args.bypass_caches,
                  input_hashes={}, external_hashes={}, commands=[], output_hashes={},
                  scope='Local ROM/SRAM/MMIO and modeled AXI DDR RTL simulation; no real DDR, CDC, board or timing acceptance')
    save(work/'result.json', result)
    started = time.monotonic()

    def native(exe, arguments, label, timeout=120):
        result['external_hashes'][str(exe)] = sha(exe)
        command = [str(exe), *[x.as_posix() if isinstance(x, Path) else str(x) for x in arguments]]
        record = dict(command=command, return_code=None, timed_out=False)
        result['commands'].append(record)
        process = subprocess.Popen(command, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            record['timed_out'] = True
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
            output, _ = process.communicate()
        record['return_code'] = process.returncode
        (work/(label+'.log')).write_bytes(output)
        if record['timed_out'] or process.returncode:
            raise RuntimeError(f'{label} returned {process.returncode}, timed_out={record["timed_out"]}')
        return output.decode('utf-8', errors='replace')

    try:
        checked = validate()
        generate(check=True)
        core = json.loads((ROOT/'fpga/pg2l100h/project/cpu_core.json').read_text(encoding='utf-8'))
        project = json.loads((ROOT/'fpga/pg2l100h/project/cpu_cached_soc.json').read_text(encoding='utf-8'))
        sources = project['sources']
        if project['top'] != 'triha_cached_soc' or project['device'] != 'PG2L100H' or len(set(sources)) != len(sources):
            raise ValueError('invalid explicit cached SoC source target')
        if args.test == 'router':
            sources = [s for s in sources if s not in core['sources'] and s != 'rtl/soc/triha_cached_soc.v']
        tb = 'tb/soc/tb_cpu_cache_'+('router' if args.test == 'router' else 'soc')+'.v'
        paths = sources+[tb, 'scripts/cpu/run_cache_soc.py', 'scripts/cpu/run_modelsim.do',
            'scripts/cpu/gen_cache_soc.py', 'scripts/cpu/run_cache.py', 'scripts/soc/gen_config.py',
            'sw/runtime/soc_map.h', 'sw/runtime/triha_sram.ld', 'config/cpu_cache_soc.json', 'config/soc_map.json',
            'rtl/soc/include/soc_map.vh', 'rtl/soc/include/cpu_cache_map.vh',
            'fpga/pg2l100h/project/cpu_cached_soc.json', *checked['validated_paths']]
        primitives = []
        if args.test == 'runtime':
            paths += core['headers']+['config/cpu_primitives.json', 'config/cpu_toolchain.json',
                'sw/tests/cache_soc_runtime.S', 'sw/runtime/triha_sram.ld', 'rtl/cpu/ADAPTATIONS.json',
                'fpga/pg2l100h/project/cpu_core.json']
            for entry in json.loads((ROOT/'rtl/cpu/ADAPTATIONS.json').read_text(encoding='utf-8'))['adaptations']:
                for key in ['base', 'derived']:
                    assert sha(ROOT/entry[key]) == entry[key+'_sha256'], entry[key]
                    paths.append(entry[key])
            for row in json.loads((ROOT/'config/cpu_primitives.json').read_text(encoding='utf-8'))['simulation_models']:
                assert sha(row['path']) == row['sha256']
                primitives.append(Path(row['path']))
                result['external_hashes'][row['path']] = row['sha256']
        # Missing production modules intentionally reach ModelSim in RED runs.
        for name in sorted(set(paths)):
            if not (ROOT/name).is_file():
                continue
            result['input_hashes'][name] = sha(ROOT/name)
            dest = work/'src'/name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/name, dest)
        native(Path(sys.executable), [work/'src/scripts/soc/gen_config.py', '--check'], 'local-config')
        rom = bytearray(b'\x73\x00\x10\x00'*2048)
        rom[:8] = struct.pack('<II', 0x000102b7, 0x00028067)
        sram = bytearray([0xa5]*32768)
        if args.test == 'runtime':
            gcc = Path(json.loads((work/'src/config/cpu_toolchain.json').read_text(encoding='utf-8'))['compiler'])
            native(gcc, ['--version'], 'gcc-version')
            native(gcc, ['-march=rv32im_zicsr_zifencei', '-mabi=ilp32', '-O2', '-mcmodel=medany',
                '-mno-relax', '-nostdlib', '-T', work/'src/sw/runtime/triha_sram.ld',
                '-Wl,--build-id=none', '-Wl,-Map='+str(work/'firmware.map'),
                '-o', work/'firmware.elf', work/'src/sw/tests/cache_soc_runtime.S'], 'firmware')
            elf = (work/'firmware.elf').read_bytes()
            assert elf[:7] == b'\x7fELF\x01\x01\x01' and struct.unpack_from('<H', elf, 18)[0] == 243
            assert struct.unpack_from('<I', elf, 24)[0] == 0x10000
            offset = struct.unpack_from('<I', elf, 28)[0]
            size, count = struct.unpack_from('<HH', elf, 42)
            for n in range(count):
                kind, start, va, pa, filesz, memsz = struct.unpack_from('<6I', elf, offset+n*size)
                if kind != 1:
                    continue
                local = pa-0x10000
                assert va == pa and 0 <= local and filesz <= memsz and local+memsz <= len(sram)
                assert start+filesz <= len(elf)
                sram[local:local+filesz] = elf[start:start+filesz]
        for name, image in [('rom', rom), ('sram', sram)]:
            (work/(name+'.hex')).write_text(''.join(f'{int.from_bytes(image[n:n+8],"little"):016x}\n'
                for n in range(0, len(image), 8)), encoding='utf-8', newline='\n')
        native(SIM/'vsim.exe', ['-version'], 'modelsim-version')
        native(SIM/'vmap.exe', ['-c'], 'vmap')
        native(SIM/'vlib.exe', ['work'], 'vlib')
        native(SIM/'vlog.exe', ['+incdir+'+(work/'src/rtl/soc/include').as_posix(),
            '+incdir+'+(work/'src/rtl/cpu/vendor/src/core').as_posix(),
            *[work/'src'/p for p in sources+[tb]], *primitives], 'compile')
        output = native(SIM/'vsim.exe', ['-c', '-onfinish', 'exit', '-voptargs=+acc',
            '-gCACHE_ENABLE='+str(int(not args.bypass_caches)), '-gCORRUPT_DATA='+str(int(args.fault == 'data')),
            '-gMAX_CYCLES='+str(8 if args.fault == 'watchdog' else 200000),
            'work.tb_cpu_cache_'+('router' if args.test == 'router' else 'soc'),
            '-do', work/'src/scripts/cpu/run_modelsim.do'], 'simulation', 180)
        marker = 'CPU_CACHE_'+('ROUTER' if args.test == 'router' else 'SOC')+'_PASS'
        if marker not in output or any(s in output for s in ['CPU_CACHE_FAIL', '** Error', '** Fatal']):
            raise RuntimeError('cached SoC self-check failed')
        result.update(status='PASS', runner_return_code=0)
    except Exception as error:
        result.update(status='FAIL', error=str(error), runner_return_code=1)
    finally:
        result['source_unchanged'] = all((ROOT/p).is_file() and sha(ROOT/p) == h for p,h in result['input_hashes'].items())
        result['external_unchanged'] = all(sha(p) == h for p,h in result['external_hashes'].items())
        if not result['source_unchanged'] or not result['external_unchanged']:
            result.update(status='FAIL', error='inputs changed during run', runner_return_code=1)
        result['output_hashes'] = {p.relative_to(work).as_posix():sha(p) for p in work.rglob('*') if p.is_file() and p.name != 'result.json'}
        result['elapsed_seconds'] = round(time.monotonic()-started, 3)
        save(work/'result.json', result)
    print(result['status'], result.get('error', ''), flush=True)
    return result['runner_return_code']


if __name__ == '__main__':
    raise SystemExit(main())

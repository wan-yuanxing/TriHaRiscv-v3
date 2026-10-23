"""Native, frozen-input ModelSim verification of the paired CPU caches."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import re
from pathlib import Path
import shutil
import struct
import subprocess
import time
from check_cache import validate

ROOT = Path(__file__).resolve().parents[2]
SIM = Path('D:/modeltech64_2020.4/win64')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n',
                    encoding='utf-8', newline='\n')


def parse_args(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--test', choices=['components', 'writeback', 'overlap', 'transport', 'joint', 'cpu', 'coremark'], default='components')
    parser.add_argument('--fault', choices=['none', 'data', 'crc'], default='none')
    parser.add_argument('--iterations', type=int, choices=[1, 5], default=5)
    parser.add_argument('--issue-mode', choices=['single', 'dual'], default='single')
    parser.add_argument('--bypass-caches', action='store_true')
    parser.add_argument('--fast-response-check', action='store_true', help='Require component resident-read lookup response latency')
    parser.add_argument('--store-response-check', action='store_true', help='Require direct store dispatch/completion and the original registered load response')
    args = parser.parse_args(argv)
    if (args.fast_response_check or args.store_response_check) and args.test != 'components':
        parser.error('fast response latency check is a cache component test')
    if args.fast_response_check and args.store_response_check:
        parser.error('select one read-response contract')
    cpu_test = args.test in ['cpu', 'coremark']
    if args.bypass_caches and not cpu_test:
        parser.error('--bypass-caches is a real CPU comparison mode')
    if args.fault == 'crc' and args.test != 'coremark':
        parser.error('CRC corruption requires the real CoreMark program')
    if args.issue_mode != 'single' and not cpu_test:
        parser.error('--issue-mode dual requires a real CPU or CoreMark test')
    return args


def main():
    args = parse_args()
    cpu_test = args.test in ['cpu', 'coremark']
    work = ROOT / 'build/cpu' / ('cache-' + args.test + '-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    row = dict(status='RUNNING', directory=str(work), test=args.test, fault=args.fault,
               input_hashes={}, external_hashes={}, output_hashes={}, commands=[],
               source_unchanged=False, external_unchanged=False, runner_return_code=None,
               scope='Paired-cache RTL components; no full CPU, DDR hardware or timing acceptance')
    row['cache_enable'] = not args.bypass_caches
    row['issue_mode'] = args.issue_mode
    if cpu_test:
        row['scope'] = f'Real six-stage {args.issue_mode}-issue CPU with paired-cache or uncached DDR model; no physical DDR, board or timing acceptance'
    if args.test == 'coremark':
        row['memory_model'] = dict(axi_bits=128, deterministic_ready=True,
            model_write_wait_cycles=30, refill_bytes=32, physical_ddr_latency_validated=False)
    save(work / 'result.json', row)
    print('CPU_CACHE_RUN', work, flush=True)
    started = time.monotonic()

    def native(exe, arguments, label, timeout=90):
        row['external_hashes'][str(exe)] = sha(exe)
        command = [str(exe), *map(str, arguments)]
        item = dict(command=command, return_code=None, timed_out=False)
        row['commands'].append(item)
        process = subprocess.Popen(command, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            item['timed_out'] = True
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
            output, _ = process.communicate()
        (work / (label + '.log')).write_bytes(output)
        item['return_code'] = process.returncode
        if item['timed_out'] or process.returncode:
            raise RuntimeError(f'{label} returned {process.returncode}; timed_out={item["timed_out"]}')
        return output.decode('utf-8', errors='replace')

    try:
        preflight = validate(ROOT)
        row['preflight'] = preflight
        cfg = json.loads((ROOT / 'config/cpu_cache.json').read_text(encoding='utf-8'))
        assert cfg['schema_version'] == 1 and cfg['clock_hz'] == 100000000
        assert all(cfg[k] == dict(bytes=16384, ways=2, line_bytes=32) for k in ['icache'])
        assert cfg['dcache'] == dict(bytes=16384, ways=2, line_bytes=32, write_policy='write_back', write_allocate=True, posted_writes=False)
        assert cfg['private_ddr_base'] == 0x80000000 and cfg['private_ddr_bytes'] == 0x2000000
        assert cfg['shared_ddr_base'] == 0x82000000 and cfg['shared_ddr_bytes'] == 0x6000000
        sources = [p.strip() for p in (ROOT / 'config/cpu_cache_sources.f').read_text(encoding='utf-8').splitlines() if p.strip() and not p.startswith('#')]
        tb = 'tb/cpu/tb_cpu_cache.v'
        if args.test == 'writeback':
            tb = 'tb/cpu/tb_cpu_dcache_writeback.v'
        elif args.test == 'overlap':
            tb = 'tb/cpu/tb_cpu_dcache_overlap.v'
        elif args.test == 'transport':
            sources = ['rtl/soc/triha_cpu_cache_axi.v']
            tb = 'tb/soc/tb_cpu_cache_axi.v'
        elif args.test in ['joint', 'cpu', 'coremark']:
            sources += ['rtl/soc/triha_cpu_cache_axi.v', 'rtl/cpu/triha_cache_subsystem.v']
            tb = 'tb/soc/tb_cpu_cache_joint.v'
        if cpu_test:
            core = json.loads((ROOT / 'fpga/pg2l100h/project/cpu_core.json').read_text(encoding='utf-8'))
            sources = core['sources'] + sources + ['rtl/cpu/triha_cached_core.v']
            tb = 'tb/soc/tb_cpu_cache_cpu.v'
        local = sources + [tb, 'config/cpu_cache.json', 'config/cpu_cache_sources.f',
                           'scripts/cpu/run_cache.py', 'scripts/cpu/run_modelsim.do']
        local += preflight['validated_paths']
        primitive_sources = []
        if cpu_test:
            local += ['fpga/pg2l100h/project/cpu_core.json', 'rtl/cpu/ADAPTATIONS.json',
                      'rtl/cpu/vendor/UPSTREAM.json', 'rtl/cpu/vendor/src/core/biriscv_defs.v',
                      'config/cpu_toolchain.json', 'config/cpu_primitives.json',
                      'sw/tests/cache_runtime.S', 'sw/runtime/triha_tcm.ld']
            primitive = json.loads((ROOT / 'config/cpu_primitives.json').read_text(encoding='utf-8'))
            for entry in primitive['simulation_models']:
                assert sha(entry['path']) == entry['sha256']
                primitive_sources.append(Path(entry['path']))
                row['external_hashes'][entry['path']] = entry['sha256']
        if args.test == 'coremark':
            local += ['scripts/cpu/cache_firmware.py', 'sw/runtime/crt0.S', 'sw/runtime/triha_runtime.c',
                      'sw/runtime/triha_runtime.h', 'sw/benchmarks/coremark/port/core_portme.c',
                      'sw/benchmarks/coremark/port/core_portme.h']
        for optional in ['rtl/cpu/CACHE_ADAPTATIONS.json', 'rtl/cpu/vendor/CACHE_UPSTREAM.json']:
            if (ROOT / optional).exists():
                local.append(optional)
        for name in local:
            path = ROOT / name
            if path.exists():
                row['input_hashes'][name] = sha(path)
                frozen = work / 'src' / name
                frozen.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, frozen)
        if cpu_test:
            toolchain = json.loads((work / 'src/config/cpu_toolchain.json').read_text(encoding='utf-8'))
            row['compiler_version'] = native(Path(toolchain['compiler']), ['--version'], 'gcc-version').strip()
            if args.test == 'coremark':
                from cache_firmware import prepare
                flags, program_sources = prepare(work, args.iterations, args.fault)
                row['compiler_flags'] = [str(flag) for flag in flags]
                row['iterations'] = args.iterations
                library = native(Path(toolchain['compiler']), ['-march=rv32im_zicsr','-mabi=ilp32','-print-libgcc-file-name'], 'libgcc').strip()
                row['external_hashes'][library] = sha(library)
                native(Path(toolchain['compiler']), flags + ['-nostdlib', '-T', work/'src/sw/runtime/triha_tcm.ld',
                    '-Wl,--gc-sections,--build-id=none', '-Wl,-Map='+str(work/'firmware.map'),
                    '-o', work/'firmware.elf', *program_sources, '-lgcc'], 'firmware')
            else:
                native(Path(toolchain['compiler']), ['-march=rv32im_zicsr_zifencei', '-mabi=ilp32', '-O2',
                    '-mcmodel=medany', '-mno-relax', '-nostdlib', '-T', work/'src/sw/runtime/triha_tcm.ld',
                    '-Wl,--build-id=none', '-o', work/'firmware.elf', work/'src/sw/tests/cache_runtime.S'], 'firmware')
            elf = (work/'firmware.elf').read_bytes()
            assert elf[:7] == b'\x7fELF\x01\x01\x01' and struct.unpack_from('<H',elf,18)[0] == 243
            assert struct.unpack_from('<I',elf,24)[0] == 0x80000000
            image = bytearray([0xa5] * 131072)
            offset = struct.unpack_from('<I',elf,28)[0]
            size,count = struct.unpack_from('<HH',elf,42)
            for index in range(count):
                kind,start,vaddr,paddr,filesz,memsz = struct.unpack_from('<6I',elf,offset+index*size)
                if kind != 1: continue
                relative = paddr - 0x80000000
                assert paddr == vaddr and 0 <= relative and filesz <= memsz and relative+memsz <= len(image)
                image[relative:relative+filesz] = elf[start:start+filesz]
            (work/'firmware.hex').write_text(''.join(f'{int.from_bytes(image[i:i+4],"little"):08x}\n' for i in range(0,len(image),4)),encoding='utf-8',newline='\n')
        native(SIM / 'vsim.exe', ['-version'], 'modelsim-version')
        native(SIM / 'vmap.exe', ['-c'], 'vmap')
        native(SIM / 'vlib.exe', ['work'], 'vlib')
        # Missing expected files deliberately reach the compiler in RED runs.
        includes = ['+incdir+' + (work/'src/rtl/cpu/vendor/src/core').as_posix()] if cpu_test else []
        native(SIM / 'vlog.exe', ['-work', 'work', *includes, *[work / 'src' / p for p in sources + [tb]], *primitive_sources], 'compile')
        dual = int(args.issue_mode == 'dual')
        generics = ['-gCACHE_ENABLE=' + str(int(not args.bypass_caches)), '-gDUAL_ISSUE=' + str(dual)] if cpu_test else []
        if args.fast_response_check: generics += ['-gFAST_RESPONSE_CHECK=1']
        if args.store_response_check: generics += ['-gSTORE_RESPONSE_CHECK=1']
        if args.test == 'coremark': generics += ['-gCOREMARK_MODE=1']
        output = native(SIM / 'vsim.exe', ['-c', '-onfinish', 'exit', '-voptargs=+acc', *generics,
                        '-gCORRUPT_DATA=' + str(int(args.fault == 'data')), 'work.' + Path(tb).stem,
                        '-do', work / 'src/scripts/cpu/run_modelsim.do'], 'simulation', timeout=600 if args.test == 'coremark' else 90)
        marker = {'components': 'CPU_CACHE_PASS', 'writeback': 'CPU_DCACHE_WB_PASS', 'overlap': 'CPU_DCACHE_OVERLAP_PASS', 'transport': 'CPU_CACHE_AXI_PASS', 'joint': 'CPU_CACHE_JOINT_PASS', 'cpu': 'CPU_CACHE_CPU_PASS', 'coremark': 'CPU_CACHE_COREMARK_PASS'}[args.test]
        if marker not in output or any(token in output for token in ['CPU_CACHE_FAIL', '** Error', '** Fatal']):
            raise RuntimeError('Paired-cache self-check failed')
        if cpu_test:
            configs = re.findall(r'CPU_CACHE_ISSUE_CONFIG requested=(\d+) actual=(\d+)', output)
            observations = re.findall(r'CPU_CACHE_ISSUE_OBSERVATION mode=(\d+) pairs_total=(\d+) lane1_wb_total=(\d+)', output)
            if configs != [(str(dual), str(dual))] or len(observations) != 1:
                raise RuntimeError('Missing, duplicate or wrong actual CPU issue configuration')
            actual_mode, pairs, lane1 = map(int, observations[0])
            if actual_mode != dual or (dual and (pairs <= 0 or lane1 <= 0)) or (not dual and (pairs != 0 or lane1 != 0)):
                raise RuntimeError('Actual paired issue/completion does not match selected CPU mode')
            row['issue_observation'] = dict(actual_mode=actual_mode, paired_cycles_total=pairs, lane1_wb_total=lane1)
            memory = re.findall(r'CPU_CACHE_MEMORY_OBSERVATION I_reads=(\d+) D_reads=(\d+) stores=(\d+) cached_store_updates=(\d+) lower_writes=(\d+) protocol_fault=(\d+)', output)
            if len(memory) != 1:
                raise RuntimeError('Missing or duplicate actual CPU memory coverage')
            row['memory_observation'] = dict(zip(['instruction_reads', 'data_reads', 'timed_stores',
                'cached_store_updates_total', 'lower_writes', 'protocol_fault'], map(int, memory[0])))
        if args.test == 'coremark':
            match = re.search(r'CPU_CACHE_COREMARK_PASS cycles=(\d+) wb=(\d+) stores=(\d+)', output)
            cycles, wb, stores = map(int, match.groups())
            ticks = re.findall(r'Total ticks\s*:\s*(\d+)', output)
            if ticks != [str(cycles)] or 'CPU_COREMARK_STATUS errors=0' not in output:
                raise RuntimeError('CoreMark CRC/time status mismatch')
            for value in ['e9f5','e714','1fd7','8e3a']:
                if '0x'+value not in output: raise RuntimeError('Missing standard CoreMark CRC')
            row['measurement'] = dict(cycles=cycles, wb_observations=wb, stores=stores,
                coremark_per_mhz=args.iterations*1000000/cycles,
                clock_hz_nominal=100000000, official_score=False, board_score=False)
        row['status'] = 'PASS'
        row['runner_return_code'] = 0
    except Exception as error:
        row.update(status='FAIL', error=str(error), runner_return_code=1)
    finally:
        row['source_unchanged'] = all((ROOT / p).is_file() and sha(ROOT / p) == h for p, h in row['input_hashes'].items())
        row['external_unchanged'] = all(sha(p) == h for p, h in row['external_hashes'].items())
        if not row['source_unchanged'] or not row['external_unchanged']:
            row.update(status='FAIL', runner_return_code=1, error='Input changed during run')
        row['output_hashes'] = {p.relative_to(work).as_posix(): sha(p) for p in work.rglob('*')
                                if p.is_file() and p.name != 'result.json'}
        row['elapsed_seconds'] = round(time.monotonic() - started, 3)
        save(work / 'result.json', row)
    print(row['status'], row.get('error', ''), flush=True)
    return row['runner_return_code']


if __name__ == '__main__':
    raise SystemExit(main())

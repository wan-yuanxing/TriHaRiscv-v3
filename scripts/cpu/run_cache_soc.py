"""Frozen-input native verification of local memory plus the paired-cache router."""
import argparse
from datetime import datetime, timezone
import json
import re
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import time

from admission_common import validate, ROOT, sha, save, SIM


def validate_irq_result(output, events):
    match = re.search(r'CPU_CACHE_IRQ_PASS (.+)', output)
    if not match:
        raise ValueError('missing cache IRQ completion')
    stats = {name: int(value) for name, value in re.findall(r'(\w+)=(\d+)', match[1])}
    for name in ('entries', 'returns', 'resumes'):
        if stats.get(name) != 3:
            raise ValueError('incomplete IRQ '+name)
    if stats.get('wait_irq_cycles', 0) < 40:
        raise ValueError('missing IRQ while refill outstanding')
    rows = re.findall(r'^(ASSERT|ENTRY|RETURN) phase=(\d+)', events, re.M)
    expected = [(event, str(phase)) for phase in range(1, 4) for event in ('ASSERT','ENTRY','RETURN')]
    if rows != expected:
        raise ValueError('missing, duplicate or reordered IRQ event')
    return stats


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--test', choices=['router', 'runtime', 'irq'], default='router')
    parser.add_argument('--fault', choices=['none', 'data', 'watchdog', 'irq-return'], default='none')
    parser.add_argument('--bypass-caches', action='store_true')
    args = parser.parse_args()
    if args.test == 'irq' and args.bypass_caches:
        parser.error('IRQ/cache interaction requires enabled I/D caches')
    if args.fault == 'irq-return' and args.test != 'irq':
        parser.error('IRQ return corruption requires --test irq')
    work = ROOT/'build/cpu'/('cache-soc-'+args.test+'-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    print('CPU_CACHE_SOC_RUN', work, flush=True)
    result = dict(status='RUNNING', test=args.test, fault=args.fault, cache_enable=not args.bypass_caches,
                  expected_negative=(args.fault == 'irq-return'),
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
        admission = validate()
        core = admission['core']
        sources = core['sources'] + admission['cache_sources'] + admission['local_primitives'] + admission['fixture_sources']
        if args.test == 'router':
            sources = [p for p in sources if p not in core['sources'] and not p.endswith('/triha_cached_soc.v')]
        tb = 'tb/soc/tb_cpu_cache_'+('router' if args.test == 'router' else ('soc' if args.test == 'runtime' else 'irq'))+'.v'
        paths = sources + [tb,'scripts/cpu/run_cache_soc.py','scripts/cpu/run_modelsim.do',
            'scripts/cpu/admission_common.py','config/cpu_admission.json','config/cpu_toolchain.json',
            admission['fixture_include']+'/soc_map.vh', admission['fixture_include']+'/cpu_cache_map.vh']
        primitives = [Path(p['path']) for p in admission['simulation_models']] if args.test != 'router' else []
        for p in primitives:
            result['external_hashes'][str(p)] = sha(p)
        if args.test != 'router':
            paths += core['headers'] + ['sw/tests/cache_soc_runtime.S','sw/runtime/triha_sram.ld',
                'rtl/cpu/ADAPTATIONS.json','sw/tests/cache_irq_runtime.S','sw/runtime/triha_cache_irq.ld']
        # Missing production modules intentionally reach ModelSim in RED runs.
        for name in sorted(set(paths)):
            if not (ROOT/name).is_file():
                continue
            result['input_hashes'][name] = sha(ROOT/name)
            dest = work/'src'/name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/name, dest)
        rom = bytearray(b'\x73\x00\x10\x00'*2048)
        rom[:8] = struct.pack('<II', 0x000102b7, 0x00028067)
        sram = bytearray([0xa5]*32768)
        if args.test in ('runtime', 'irq'):
            gcc = Path(json.loads((work/'src/config/cpu_toolchain.json').read_text(encoding='utf-8'))['compiler'])
            native(gcc, ['--version'], 'gcc-version')
            linker = work/'src/sw/runtime/triha_cache_irq.ld' if args.test == 'irq' else work/'src/sw/runtime/triha_sram.ld'
            firmware = work/'src/sw/tests/cache_irq_runtime.S' if args.test == 'irq' else work/'src/sw/tests/cache_soc_runtime.S'
            native(gcc, ['-march=rv32im_zicsr_zifencei', '-mabi=ilp32', '-O2', '-mcmodel=medany',
                '-mno-relax', '-nostdlib', '-T', linker,
                '-Wl,--build-id=none', '-Wl,-Map='+str(work/'firmware.map'),
                *(['-DBROKEN_IRQ_RETURN=1'] if args.fault == 'irq-return' else []),
                '-o', work/'firmware.elf', firmware], 'firmware')
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
                assert (va == pa or (args.test == 'irq' and 0x80004000 <= va < 0x80008000)), f'unsupported VMA {va:#x}'
                assert 0 <= local and filesz <= memsz and local+memsz <= len(sram), 'firmware load segment outside SRAM'
                assert start+filesz <= len(elf)
                sram[local:local+filesz] = elf[start:start+filesz]
        for name, image in [('rom', rom), ('sram', sram)]:
            (work/(name+'.hex')).write_text(''.join(f'{int.from_bytes(image[n:n+8],"little"):016x}\n'
                for n in range(0, len(image), 8)), encoding='utf-8', newline='\n')
        native(SIM/'vsim.exe', ['-version'], 'modelsim-version')
        native(SIM/'vmap.exe', ['-c'], 'vmap')
        native(SIM/'vlib.exe', ['work'], 'vlib')
        if args.test == 'irq':
            nm = gcc.parent/'riscv-none-elf-nm.exe'
            symbols = native(nm, ['-n', work/'firmware.elf'], 'symbols')
            names = {}
            for line in symbols.splitlines():
                fields = line.split()
                if len(fields) == 3 and fields[2] in {
                    'phase1_load','phase1_after','phase1_end',
                    'phase2_load','phase2_after','phase2_end',
                    'phase3_load','phase3_after','phase3_end'}:
                    names[fields[2]] = int(fields[0], 16)
            required = ['phase1_load','phase1_after','phase1_end',
                        'phase2_load','phase2_after','phase2_end',
                        'phase3_load','phase3_after','phase3_end']
            if any(name not in names for name in required):
                raise RuntimeError('missing IRQ phase symbols')
            header = work/'src/tb/soc/cache_irq_symbols.vh'
            header.write_text(''.join(f'`define {name.upper()} 32\'h{names[name]:08x}\n' for name in required), encoding='utf-8')
            result['generated_input_hashes'] = {'src/tb/soc/cache_irq_symbols.vh': sha(header)}
        native(SIM/'vlog.exe', ['+incdir+'+(work/'src'/admission['fixture_include']).as_posix(),
            '+incdir+'+(work/'src/tb/soc').as_posix(),
            '+incdir+'+(work/'src/rtl/cpu/vendor/src/core').as_posix(),
            *[work/'src'/p for p in sources+[tb]], *primitives], 'compile')
        top = 'work.tb_cpu_cache_'+('router' if args.test == 'router' else ('soc' if args.test == 'runtime' else 'irq'))
        do_file = work/'src/scripts/cpu/run_modelsim.do'
        wave_args = []
        if args.test == 'irq':
            names = 'clk rst_n phase irq fired entries returns resumes target_pending target_addr target_tag '
            names += 'ddr_ready fault protocol_fault done exit_code read_pending saved_araddr read_wait '
            names += 'arvalid arready araddr arid rvalid rready rlast rdata read_beat delayed_irq_cycles '
            names += 'mepc mcause mstatus mie exception wb_pc wb_valid saved_epc'
            scope = ['/tb_cpu_cache_irq/'+name for name in names.split()]
            scope += ['/tb_cpu_cache_irq/u_dut/'+name for name in
                      'inst_addr inst_req inst_valid inst_accept data_addr data_re data_accept data_ack data_rdata data_resp_tag'.split()]
            lines = ['onerror {quit -f -code 2}', 'onbreak {quit -f -code 3}', 'vcd file {cache-irq.vcd}']
            for signal in scope:
                lines += [f'log {signal}', f'vcd add {signal}']
            lines += ['run -all', 'quit -f -code 0']
            do_file = work/'capture.do'
            do_file.write_text('\n'.join(lines)+'\n', encoding='utf-8')
            wave_args = ['-wlf', 'cache-irq.wlf']
            result['waveform_scope'] = scope
        output = native(SIM/'vsim.exe', ['-c', '-onfinish', 'exit', '-voptargs=+acc',
            '-gCACHE_ENABLE='+str(int(not args.bypass_caches)), '-gCORRUPT_DATA='+str(int(args.fault == 'data')),
            '-gMAX_CYCLES='+str(8 if args.fault == 'watchdog' else 200000),
            *wave_args, top, '-do', do_file], 'simulation', 180)
        marker = 'CPU_CACHE_'+('ROUTER' if args.test == 'router' else ('SOC' if args.test == 'runtime' else 'IRQ'))+'_PASS'
        if args.fault == 'irq-return':
            if 'CPU_CACHE_FAIL MRET must not skip original interrupted PC' not in output or '** Fatal' not in output:
                raise RuntimeError('IRQ return negative was not rejected at the precise-PC check')
            result.update(status='FAIL', negative_reason='MRET returned with deliberately advanced mepc',
                          runner_return_code=1)
        elif marker not in output or any(s in output for s in ['CPU_CACHE_FAIL', '** Error', '** Fatal']):
            raise RuntimeError('cached SoC self-check failed')
        if args.fault != 'irq-return':
            result['pass_line'] = next(line for line in output.splitlines() if marker in line)
        if args.test == 'irq' and args.fault != 'irq-return':
            result['statistics'] = validate_irq_result(output, (work/'cache-irq.events.log').read_text())
        if args.fault != 'irq-return':
            result.update(status='PASS', runner_return_code=0)
    except Exception as error:
        result.update(status='FAIL', error=f'{type(error).__name__}: {error}', runner_return_code=1)
    finally:
        result['source_unchanged'] = all((ROOT/p).is_file() and sha(ROOT/p) == h for p,h in result['input_hashes'].items())
        result['external_unchanged'] = all(sha(p) == h for p,h in result['external_hashes'].items())
        result['source_unchanged'] &= all(sha(work/'src'/p) == h for p,h in result['input_hashes'].items())
        result['generated_unchanged'] = all(sha(work/p) == h for p,h in result.get('generated_input_hashes', {}).items())
        if not result['source_unchanged'] or not result['external_unchanged'] or not result['generated_unchanged']:
            result.update(status='FAIL', error='inputs changed during run', runner_return_code=1)
        result['output_hashes'] = {p.relative_to(work).as_posix():sha(p) for p in work.rglob('*') if p.is_file() and p.name != 'result.json'}
        result['elapsed_seconds'] = round(time.monotonic()-started, 3)
        save(work/'result.json', result)
    print(result['status'], result.get('error', ''), flush=True)
    return result['runner_return_code']


if __name__ == '__main__':
    raise SystemExit(main())

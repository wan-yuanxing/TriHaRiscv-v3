"""Freeze/build/verify private-DDR CoreMark with the actual CPU/CDC/native bridge.

Uses digital DDR/PLL substitutes only in ModelSim; never accesses the board.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

from check_cache import validate
from ddr_coremark_firmware import build
from prepare_ddr import materialize
from run_cache import ROOT, SIM, sha
from run_ddr_board_route import project, save


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache-enable', type=int, choices=[0, 1], default=1)
    parser.add_argument('--iterations', type=int, choices=[1, 5000], default=1)
    parser.add_argument('--fault', choices=['none', 'crc'], default='none')
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--cpu-core-luts', type=int, default=0)
    parser.add_argument('--uncached-shared', action='store_true', help='Keep Cache hardware; execute code/data in shared uncached DDR')
    args = parser.parse_args()
    if args.uncached_shared and args.cache_enable != 1:
        parser.error('shared-attribute comparison retains the successful Cache hardware')
    base_address = 0x82000000 if args.uncached_shared else 0x80000000
    if args.build_only and (args.iterations != 5000 or args.fault != 'none'):
        parser.error('build-only is the unchanged 5000-iteration board image')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    work = ROOT / 'build/cpu' / ('ddr-coremark-' + stamp)
    work.mkdir(parents=True)
    row = dict(status='RUNNING', test='coremark', fault=args.fault, cache_enable=args.cache_enable,
        iterations=args.iterations, build_only=args.build_only, directory=str(work),
        input_hashes={}, external_hashes={}, output_hashes={}, commands=[],
        source_unchanged=False, external_unchanged=False, runner_return_code=None,
        programmed=False, scope='O2 DDR CoreMark build/digital ModelSim; not a physical board score')
    save(work / 'result.json', row)
    print('CPU_DDR_COREMARK_RUN', work, flush=True)
    started = time.monotonic()

    def native(exe, arguments, label, timeout=180):
        exe = Path(exe)
        row['external_hashes'][str(exe)] = sha(exe)
        command = [str(exe), *[p.as_posix() if isinstance(p, Path) else str(p) for p in arguments]]
        record = dict(command=command, return_code=None, timed_out=False)
        row['commands'].append(record)
        with (work / (label + '.log')).open('wb') as output:
            process = subprocess.Popen(command, cwd=work, stdout=output, stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                record['timed_out'] = True
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True,
                    timeout=30, creationflags=subprocess.CREATE_NO_WINDOW)
                process.wait(timeout=30)
            record['return_code'] = process.returncode
        save(work / 'result.json', row)
        text = (work / (label + '.log')).read_text(encoding='utf-8', errors='replace')
        if record['timed_out'] or process.returncode:
            raise RuntimeError(f'{label} returned {process.returncode}; timed_out={record["timed_out"]}')
        return text

    try:
        validate(ROOT)
        row['binding'] = materialize(work)
        _, recipe, base, sources = project()
        names = sources + base['headers'] + recipe['headers'] + [
            'config/cpu_toolchain.json', 'config/soc_map.json', 'config/cpu_primitives.json',
            'config/cpu_ddr.json', 'config/cpu_ddr_board.json', 'fpga/pg2l100h/project/cpu_cached_soc.json',
            'sw/runtime/crt0.S', 'sw/runtime/triha_runtime.c', 'sw/runtime/triha_runtime.h',
            'sw/runtime/triha_sram.ld', 'sw/runtime/triha_coremark_loader.ld', 'sw/runtime/triha_tcm.ld', 'sw/runtime/soc_map.h', 'sw/runtime/cpu_cache_map.h',
            'sw/tests/cpu_ddr_coremark_boot.c', 'sw/benchmarks/coremark/UPSTREAM.json',
            'sw/benchmarks/coremark/port/core_portme.c', 'sw/benchmarks/coremark/port/core_portme.h',
            'scripts/cpu/ddr_coremark_firmware.py', 'scripts/cpu/cache_firmware.py',
            'scripts/cpu/run_ddr_coremark.py', 'scripts/cpu/run_modelsim.do',
            'scripts/cpu/prepare_ddr.py', 'scripts/cpu/check_cache.py', 'scripts/cpu/run_cache.py',
            'scripts/cpu/run_ddr_board_route.py', 'fpga/pg2l100h/project/cpu_ddr_board.json',
            'scripts/soc/run.py', 'scripts/soc/gen_config.py', 'scripts/soc/coremark_board.py',
            'tb/soc/tb_cpu_ddr_coremark.v', 'tb/soc/cpu_board_pll_model.v',
            'tb/video/models/ddr_board_ip_model.sv']
        upstream = json.loads((ROOT / 'sw/benchmarks/coremark/UPSTREAM.json').read_text(encoding='utf-8'))
        names += ['sw/benchmarks/coremark/src/' + name for name in upstream['files']]
        for name in sorted(set(names)):
            row['input_hashes'][name] = sha(ROOT / name)
            target = work / 'src' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        compiler = Path(json.loads((work / 'src/config/cpu_toolchain.json').read_text())['compiler'])
        row['compiler_version'] = native(compiler, ['--version'], 'gcc-version').strip()
        libgcc = native(compiler, ['-march=rv32im_zicsr', '-mabi=ilp32', '-print-libgcc-file-name'], 'libgcc').strip()
        row['external_hashes'][libgcc] = sha(libgcc)
        row.update(build(work, native, args.iterations, not args.build_only, args.fault, args.cpu_core_luts, base_address))
        if args.build_only:
            row.update(status='BUILT', runner_return_code=0)
        else:
            model = (work / 'src/tb/video/models/ddr_board_ip_model.sv').read_text(encoding='utf-8')
            if model.count('.MEMORY_SLOTS(128)') != 1:
                raise ValueError('digital DDR memory geometry changed')
            (work / 'ddr_board_model.sv').write_text(model.replace('.MEMORY_SLOTS(128)', '.MEMORY_SLOTS(4096)'),
                encoding='utf-8', newline='\n')
            primitives = []
            for entry in json.loads((ROOT / 'config/cpu_primitives.json').read_text())['simulation_models']:
                if sha(entry['path']) != entry['sha256']:
                    raise ValueError('primitive model changed')
                row['external_hashes'][entry['path']] = entry['sha256']
                primitives.append(Path(entry['path']))
            native(SIM / 'vsim.exe', ['-version'], 'modelsim-version')
            native(SIM / 'vmap.exe', ['-c'], 'vmap')
            native(SIM / 'vlib.exe', ['work'], 'vlib')
            native(SIM / 'vlog.exe', ['+incdir+' + (work / 'src/rtl/soc/include').as_posix(),
                '+incdir+' + (work / 'src/rtl/cpu/vendor/src/core').as_posix(),
                work / 'pinned/rtl/video/video_async_fifo.sv', work / 'pinned/rtl/video/axi128_hmic256.sv',
                work / 'pinned/tb/video/models/ddr_native_model.sv', work / 'ddr_board_model.sv',
                work / 'src/tb/soc/cpu_board_pll_model.v', *[work / 'src' / n for n in sources],
                work / 'src/tb/soc/tb_cpu_ddr_coremark.v', *primitives], 'compile')
            text = native(SIM / 'vsim.exe', ['-c', '-onfinish', 'exit', '-voptargs=+acc',
                '-gCACHE_ENABLE=' + str(args.cache_enable), "-gPAYLOAD_BASE=32'h"+f'{base_address:08x}', 'work.tb_cpu_ddr_coremark',
                '-do', work / 'src/scripts/cpu/run_modelsim.do'], 'simulation', 900)
            sys.path.insert(0, str(ROOT / 'scripts/soc'))
            from coremark_board import review_output
            row['measurement'] = review_output(text, allow_short=True)
            if ('CPU_DDR_COREMARK_PAYLOAD_PASS' not in text or 'CPU_DDR_COREMARK_SIM_PASS' not in text or
                    any(v in text for v in ['CPU_DDR_COREMARK_SIM_FAIL', 'CPU_DDR_COREMARK_FAIL', '** Error', '** Fatal'])):
                raise ValueError('missing complete DDR software execution')
            row.update(status='PASS', runner_return_code=0)
    except Exception as error:
        row.update(status='FAIL', runner_return_code=1, error=str(error))
    finally:
        row['source_unchanged'] = all(sha(ROOT / n) == h for n, h in row['input_hashes'].items())
        row['external_unchanged'] = all(sha(n) == h for n, h in row['external_hashes'].items())
        row['pinned_unchanged'] = all(sha(e['path']) == e['sha256'] for e in row.get('binding', {}).get('files', {}).values())
        if not all(row[k] for k in ['source_unchanged', 'external_unchanged', 'pinned_unchanged']):
            row.update(status='FAIL', runner_return_code=1, error='DDR benchmark inputs changed')
        row['output_hashes'] = {p.relative_to(work).as_posix(): sha(p) for p in work.rglob('*')
            if p.is_file() and p.name != 'result.json'}
        row['elapsed_seconds'] = round(time.monotonic() - started, 3)
        save(work / 'result.json', row)
    print('CPU_DDR_COREMARK', row['status'], row.get('error', ''), flush=True)
    return row['runner_return_code']


if __name__ == '__main__':
    raise SystemExit(main())

"""Windows-native, pinned-input CPU DDR/CDC verification."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import json
import shutil
import subprocess
import time

from run_cache import ROOT, SIM, save, sha
from prepare_ddr import materialize


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--test', choices=['cdc', 'system'], default='cdc')
    parser.add_argument('--firmware-dir', type=Path)
    parser.add_argument('--bypass-caches', action='store_true')
    parser.add_argument('--fault', choices=['none', 'data', 'watchdog'], default='none')
    parser.add_argument('--cpu-half', type=int, choices=[3, 5, 7], default=5)
    parser.add_argument('--ddr-half', type=int, choices=[4, 6], default=4)
    args = parser.parse_args()
    if args.test == 'system' and args.firmware_dir is None:
        parser.error('--test system requires a passing local-SoC firmware directory')
    if args.test == 'system' and (args.cpu_half != 5 or args.ddr_half != 4):
        parser.error('the real CPU system test uses fixed CPU100MHz/DDR125MHz clocks')
    if args.test == 'cdc' and args.bypass_caches:
        parser.error('Cache bypass applies only to the real CPU system')
    work = ROOT/'build/cpu'/('ddr-'+args.test+'-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    print('CPU_DDR_RUN', work, flush=True)
    row = dict(status='RUNNING', test=args.test, fault=args.fault, input_hashes={},
        external_hashes={}, output_hashes={}, commands=[], source_unchanged=False,
        external_unchanged=False, runner_return_code=None,
        scope='AXI asynchronous transport RTL verification; no physical CDC/timing/DDR/board acceptance')
    started = time.monotonic()
    save(work/'result.json', row)

    def native(exe, arguments, label, timeout=120):
        command = [str(exe), *[x.as_posix() if isinstance(x, Path) else str(x) for x in arguments]]
        row['external_hashes'][str(exe)] = sha(exe)
        record = dict(command=command, return_code=None, timed_out=False)
        row['commands'].append(record)
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
            raise RuntimeError(f'{label} returned {process.returncode}; timed_out={record["timed_out"]}')
        return output.decode('utf-8', errors='replace')

    try:
        row['binding'] = materialize(work)
        row['external_hashes'][row['binding']['git']] = row['binding']['git_sha256']
        sources = ['rtl/soc/triha_axi128_cdc.v']
        tb = 'tb/soc/tb_cpu_axi_cdc.v'
        pinned_sources = ['rtl/video/video_async_fifo.sv']
        primitive_sources = []
        extra = []
        if args.test == 'system':
            from review_cache_soc import verify_run
            from check_cache import validate
            validate()
            firmware = verify_run(args.firmware_dir)
            if firmware['test'] != 'runtime' or firmware['fault'] != 'none':
                raise ValueError('need positive real CPU firmware execution')
            row['firmware_result_sha256'] = sha(args.firmware_dir/'result.json')
            row['firmware_directory'] = str(args.firmware_dir.resolve())
            row['cache_enable'] = not args.bypass_caches
            row['scope'] = 'Real local cached CPU100MHz -> five-channel CDC -> pinned DDR bridge125MHz -> native digital memory; excludes physical DDR/CDC timing/shared fabric/board acceptance'
            row['firmware_hashes'] = {str((args.firmware_dir/name).resolve()):sha(args.firmware_dir/name)
                for name in ['rom.hex', 'sram.hex', 'firmware.elf', 'result.json']}
            shutil.copyfile(args.firmware_dir/'result.json', work/'firmware-result.json')
            for name in ['rom.hex', 'sram.hex', 'firmware.elf']:
                shutil.copyfile(args.firmware_dir/name, work/name)
            project = json.loads((ROOT/'fpga/pg2l100h/project/cpu_cached_soc.json').read_text(encoding='utf-8'))
            sources += project['sources']+['rtl/soc/triha_cpu_ddr.v']
            pinned_sources += ['rtl/video/axi128_hmic256.sv', 'tb/video/models/ddr_native_model.sv']
            tb = 'tb/soc/tb_cpu_ddr_system.v'
            extra = project['headers']+['fpga/pg2l100h/project/cpu_cached_soc.json',
                'scripts/cpu/review_cache_soc.py', 'scripts/cpu/compare_cache_runs.py',
                'config/cpu_primitives.json', 'rtl/cpu/ADAPTATIONS.json', 'rtl/cpu/CACHE_ADAPTATIONS.json']
            for item in json.loads((ROOT/'config/cpu_primitives.json').read_text(encoding='utf-8'))['simulation_models']:
                if sha(item['path']) != item['sha256']:
                    raise ValueError('primitive simulation model hash drift')
                primitive_sources.append(Path(item['path']))
                row['external_hashes'][item['path']] = item['sha256']
        names = sources+[tb, 'scripts/cpu/run_ddr.py', 'scripts/cpu/prepare_ddr.py',
            'scripts/cpu/run_cache.py', 'scripts/cpu/check_cache.py', 'scripts/cpu/run_modelsim.do', 'config/cpu_ddr.json']+extra
        for name in sorted(set(names)):
            if not (ROOT/name).exists():
                continue
            row['input_hashes'][name] = sha(ROOT/name)
            target = work/'src'/name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/name, target)
        native(SIM/'vsim.exe', ['-version'], 'modelsim-version')
        native(SIM/'vmap.exe', ['-c'], 'vmap')
        native(SIM/'vlib.exe', ['work'], 'vlib')
        native(SIM/'vlog.exe', ['+incdir+'+(work/'src/rtl/soc/include').as_posix(),
            '+incdir+'+(work/'src/rtl/cpu/vendor/src/core').as_posix(),
            *[work/'pinned'/n for n in pinned_sources],
            *[work/'src'/n for n in sources+[tb]], *primitive_sources], 'compile')
        generics = ['-gCPU_HALF_NS='+str(args.cpu_half), '-gDDR_HALF_NS='+str(args.ddr_half)] if args.test == 'cdc' else [
            '-gCACHE_ENABLE='+str(int(not args.bypass_caches))]
        output = native(SIM/'vsim.exe', ['-c', '-onfinish', 'exit', '-voptargs=+acc',
            *generics,
            '-gCORRUPT_DATA='+str(int(args.fault == 'data')),
            '-gMAX_CYCLES='+str(8 if args.fault == 'watchdog' else 50000),
            'work.'+('tb_cpu_axi_cdc' if args.test == 'cdc' else 'tb_cpu_ddr_system'), '-do', work/'src/scripts/cpu/run_modelsim.do'], 'simulation')
        marker = 'CPU_AXI_CDC_PASS' if args.test == 'cdc' else 'CPU_DDR_SYSTEM_PASS'
        if marker not in output or any(s in output for s in ['CPU_AXI_CDC_FAIL', 'CPU_CACHE_FAIL', '** Error', '** Fatal']):
            raise RuntimeError('CPU DDR self-check failed')
        row.update(status='PASS', runner_return_code=0)
    except Exception as error:
        row.update(status='FAIL', runner_return_code=1, error=str(error))
    finally:
        row['source_unchanged'] = all(sha(ROOT/p) == h for p,h in row['input_hashes'].items())
        row['external_unchanged'] = all(sha(p) == h for p,h in row['external_hashes'].items())
        row['pinned_unchanged'] = all(sha(e['path']) == e['sha256'] for e in row.get('binding', {}).get('files', {}).values())
        if any(sha(p) != h for p,h in row.get('firmware_hashes', {}).items()):
            row['source_unchanged'] = False
        if not all(row[k] for k in ['source_unchanged', 'external_unchanged', 'pinned_unchanged']):
            row.update(status='FAIL', runner_return_code=1, error='CPU DDR inputs changed')
        row['output_hashes'] = {p.relative_to(work).as_posix():sha(p) for p in work.rglob('*') if p.is_file() and p.name != 'result.json'}
        row['elapsed_seconds'] = round(time.monotonic()-started, 3)
        save(work/'result.json', row)
    print(row['status'], row.get('error', ''), flush=True)
    return row['runner_return_code']


if __name__ == '__main__':
    raise SystemExit(main())

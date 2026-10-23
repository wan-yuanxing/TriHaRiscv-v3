"""Frozen-input, passive dual-issue TCM profiling using an accepted -O2 image."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import time

from run_cache import ROOT, SIM, sha, save


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--firmware-run', type=Path, required=True)
    parser.add_argument('--issue-source', type=Path)
    args = parser.parse_args()
    work = ROOT / 'build/cpu' / ('tcm-profile-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    row = dict(status='RUNNING', directory=str(work), input_hashes={}, input_origins={}, external_hashes={},
        output_hashes={}, commands=[], source_unchanged=False, external_unchanged=False, runner_return_code=None,
        scope='Passive six-stage dual-issue TCM RTL profile; no board, area or timing admission')
    save(work / 'result.json', row)
    print('TCM_PROFILE_RUN', work, flush=True)
    started = time.monotonic()

    def native(name, arguments, label, timeout=60):
        exe = SIM / (name + '.exe')
        row['external_hashes'][str(exe)] = sha(exe)
        command = [str(exe), *map(str, arguments)]
        process = subprocess.Popen(command, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        item = dict(command=command, return_code=None, timed_out=False)
        row['commands'].append(item)
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            item['timed_out'] = True
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
            output, _ = process.communicate()
        item['return_code'] = process.returncode
        (work / (label + '.log')).write_bytes(output)
        if item['timed_out'] or process.returncode:
            raise ValueError(f'{label}: return={process.returncode} timeout={item["timed_out"]}')
        return output.decode('utf-8', errors='replace')

    try:
        fw = args.firmware_run.resolve()
        evidence = json.loads((fw / 'result.json').read_text(encoding='utf-8'))
        if evidence['status'] != 'PASS' or evidence['runner_return_code'] != 0 or not evidence['source_unchanged'] or evidence['program'] != 'coremark' or evidence['fault'] != 'none' or '-O2' not in evidence['compiler_flags'] or any('flto' in f or f == '-O3' for f in evidence['compiler_flags']):
            raise ValueError('Need an accepted uncorrupted -O2 TCM CoreMark program')
        row['iterations'] = evidence['iterations']
        row['firmware_run'] = str(fw)
        for name in ['result.json', 'firmware.elf', 'tcm.bin']:
            source = fw / name
            if name != 'result.json' and sha(source) != evidence['output_hashes'][name]:
                raise ValueError('Firmware output drift: ' + name)
            row['external_hashes'][str(source)] = sha(source)
            shutil.copyfile(source, work / name.replace('result.json', 'firmware-result.json'))
        sources = [s.strip() for s in (ROOT / 'config/cpu_sources.f').read_text(encoding='utf-8').splitlines() if s.strip() and not s.startswith('#')]
        sources += ['tb/cpu/tb_dual_profile.v']
        names = sources + ['config/cpu_sources.f', 'config/cpu_primitives.json',
            'rtl/cpu/vendor/src/core/biriscv_defs.v', 'scripts/cpu/run_modelsim.do', 'scripts/cpu/run_tcm_profile.py', 'scripts/cpu/run_cache.py']
        for name in names:
            source = args.issue_source.resolve() if args.issue_source and name == 'rtl/cpu/triha_issue.v' else ROOT / name
            row['input_origins'][name] = str(source)
            row['input_hashes'][name] = sha(source)
            target = work / 'src' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        primitives = []
        for item in json.loads((ROOT / 'config/cpu_primitives.json').read_text(encoding='utf-8'))['simulation_models']:
            if sha(item['path']) != item['sha256']:
                raise ValueError('Primitive drift')
            row['external_hashes'][item['path']] = item['sha256']
            primitives.append(item['path'])
        native('vsim', ['-version'], 'version')
        native('vmap', ['-c'], 'vmap')
        native('vlib', ['work'], 'vlib')
        native('vlog', ['-work', 'work', '+incdir+' + (work / 'src/rtl/cpu/vendor/src/core').as_posix(),
            *[work / 'src' / p for p in sources], *primitives], 'compile')
        output = native('vsim', ['-c', '-onfinish', 'exit', '-voptargs=+acc', 'work.tb_dual_profile',
            '+MEM_IMAGE=' + (work / 'tcm.bin').as_posix(), '-do', work / 'src/scripts/cpu/run_modelsim.do'], 'simulation', 600)
        if 'TCM_PROFILE_PASS ' not in output or 'CPU_FIRMWARE_PASS dual=1' not in output or 'CPU_COREMARK_STATUS errors=0' not in output or any(s in output for s in ['PROFILE_FAIL', 'SMOKE_FAIL', '** Error', '** Fatal']):
            raise ValueError('Profile/program check failed')
        import re
        lines = re.findall(r'TCM_PROFILE_PASS (.*)', output)
        if len(lines) != 1:
            raise ValueError('Missing or duplicate profile')
        row['profile'] = {k: int(v) for k, v in (s.split('=') for s in lines[0].strip().split())}
        if re.findall(r'Total ticks\s*:\s*(\d+)', output) != [str(row['profile']['cycles'])]:
            raise ValueError('Profile time differs from software')
        row['coremark_per_mhz_short_estimate'] = row['iterations'] * 1000000 / row['profile']['cycles']
        row['status'] = 'PASS'
        row['runner_return_code'] = 0
    except Exception as error:
        row.update(status='FAIL', runner_return_code=1, error=str(error))
    finally:
        row['source_unchanged'] = all(sha(row['input_origins'][p]) == h for p, h in row['input_hashes'].items())
        row['external_unchanged'] = all(sha(p) == h for p, h in row['external_hashes'].items())
        if not row['source_unchanged'] or not row['external_unchanged']:
            row.update(status='FAIL', runner_return_code=1, error='Inputs changed during profile')
        row['output_hashes'] = {p.relative_to(work).as_posix(): sha(p) for p in work.rglob('*') if p.is_file() and p.name != 'result.json'}
        row['elapsed_seconds'] = round(time.monotonic() - started, 3)
        save(work / 'result.json', row)
    print(row['status'], row.get('profile', row.get('error')), flush=True)
    return row['runner_return_code']


if __name__ == '__main__':
    raise SystemExit(main())

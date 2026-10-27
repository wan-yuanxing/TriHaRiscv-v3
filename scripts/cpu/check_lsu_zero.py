"""Replay LSU zero and E2 selection checks against an isolated CPU candidate."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SIM = Path('D:/modeltech64_2020.4/win64')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    candidate = args.candidate.resolve()
    source = ROOT
    out = args.output.resolve()
    if not out.is_relative_to(ROOT / 'build/cpu'):
        raise ValueError('Output must be under build/cpu')
    out.mkdir(parents=True, exist_ok=False)
    row = {'status': 'RUNNING', 'commands': [], 'input_hashes': {}}
    receipt = out / 'result.json'

    def save():
        receipt.write_text(json.dumps(row, indent=2) + '\n', encoding='utf-8')

    def run(name, tool, arguments, expected=None, rejected=None):
        command = [str(SIM / tool)] + arguments
        result = subprocess.run(command, cwd=out, capture_output=True, timeout=120)
        log = result.stdout + result.stderr
        (out / (name + '.log')).write_bytes(log)
        row['commands'].append({'command': command, 'return_code': result.returncode,
                                'log': name + '.log'})
        if result.returncode or (expected and expected.encode() not in log) or (rejected and rejected.encode() in log):
            raise RuntimeError(name + ' failed; inspect log')

    try:
        cfg = json.loads((source / 'fpga/pg2l100h/project/cpu_core.json').read_text())
        primitives = json.loads((source / 'config/cpu_primitives.json').read_text())
        files = [(candidate / Path(n).name) if n.startswith('rtl/cpu/') and (candidate / Path(n).name).is_file() else source / n for n in cfg['sources']]
        for item in primitives['simulation_models']:
            path = Path(item['path'])
            if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
                raise ValueError('Primitive drift')
            files.append(path)
        tests = [ROOT / ('tb/cpu/' + n + '.v') for n in
                 ['tb_lsu_zero_sideband', 'tb_load_bypass', 'tb_mul_zero_program', 'tb_lsu_zero_program']]
        for path in files + tests:
            row['input_hashes'][str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
        run('vlib', 'vlib.exe', ['work'])
        run('compile', 'vlog.exe', ['+define+HAS_LSU_ZERO',
            '+incdir+' + (source / 'rtl/cpu/vendor/src/core').as_posix()] +
            [str(p) for p in files + tests])
        for load in [0, 1]:
            for mul in [0, 1]:
                run(f'lsu-zero-{load}-{mul}', 'vsim.exe', ['-c', 'tb_lsu_zero_sideband',
                    f'-gLOAD_BYPASS={load}', f'-gMUL_BYPASS={mul}', '-do', 'run -all; quit -f'],
                    'LSU_ZERO_PASS', 'LSU_ZERO_FAIL')
        for name, marker in [('tb_load_bypass', 'LOAD_BYPASS'), ('tb_mul_zero_program', 'MUL_PROGRAM'),
                             ('tb_lsu_zero_program', 'LSU_PROGRAM')]:
            run(name, 'vsim.exe', ['-c', name, '-do', 'run -all; quit -f'], marker+'_PASS', marker+'_FAIL')
        for fault in ['FAULT_ZERO', 'FAULT_E2']:
            command = [str(SIM / 'vsim.exe'), '-c', 'tb_lsu_zero_sideband', '+'+fault,
                       '-do', 'run -all; quit -f']
            neg = subprocess.run(command, cwd=out, capture_output=True, timeout=120)
            log = neg.stdout + neg.stderr
            (out / ('negative-'+fault+'.log')).write_bytes(log)
            row['commands'].append({'command': command, 'return_code': neg.returncode})
            if b'LSU_ZERO_FAIL' not in log or b'LSU_ZERO_PASS' in log:
                raise RuntimeError('Real sideband negative not detected')
        for path, value in row['input_hashes'].items():
            if hashlib.sha256(Path(path).read_bytes()).hexdigest() != value:
                raise ValueError('Input changed during run')
        row['status'] = 'PASS'
    except Exception as exc:
        row.update(status='FAIL', error=str(exc))
        raise
    finally:
        row['output_hashes'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in out.glob('*.log')}
        save()
    print('LSU_ZERO_CHECK_PASS', receipt)


if __name__ == '__main__':
    main()

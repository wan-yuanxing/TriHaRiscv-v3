"""Replay multiplier sideband checks against a frozen full-CPU simulation source set."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SIM = Path('D:/modeltech64_2020.4/win64')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('simulation', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    source = args.simulation.resolve() / 'src'
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
        files = [source / n for n in cfg['sources']]
        for item in primitives['simulation_models']:
            path = Path(item['path'])
            if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
                raise ValueError('Primitive drift')
            files.append(path)
        tests = [ROOT / ('tb/cpu/' + n + '.v') for n in
                 ['tb_mul_zero_sideband', 'tb_issue_mul_zero', 'tb_mul_zero_program']]
        for path in files + tests:
            row['input_hashes'][str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
        run('vlib', 'vlib.exe', ['work'])
        run('compile', 'vlog.exe', ['+define+HAS_ZERO_SIDEBAND',
            '+incdir+' + (source / 'rtl/cpu/vendor/src/core').as_posix()] +
            [str(p) for p in files + tests])
        for name, marker in [('tb_mul_zero_sideband', 'MUL_ZERO'),
                             ('tb_issue_mul_zero', 'ISSUE_MUL_ZERO'),
                             ('tb_mul_zero_program', 'MUL_PROGRAM')]:
            run(name, 'vsim.exe', ['-c', name, '-do', 'run -all; quit -f'],
                marker + '_PASS', marker + '_FAIL')
        run('negative-real-sideband', 'vsim.exe', ['-c', 'tb_issue_mul_zero',
            '+FAULT_SIDEBAND', '-do', 'run -all; quit -f'],
            'ISSUE_MUL_ZERO_FAIL', 'ISSUE_MUL_ZERO_PASS')
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
    print('MUL_ZERO_CHECK_PASS', receipt)


if __name__ == '__main__':
    main()

"""Compare all branch/ALU outputs with a frozen parent, including fault controls."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SIM = Path('D:/modeltech64_2020.4/win64')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('parent', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    if not out.is_relative_to(ROOT / 'build/cpu'):
        raise ValueError('Output must be below build/cpu')
    out.mkdir(parents=True, exist_ok=False)
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    bench = ROOT / 'tb/cpu/tb_shift_data_compare.v'
    defs = ROOT / 'rtl/cpu/vendor/src/core/biriscv_defs.v'
    inputs = [args.parent.resolve(), args.candidate.resolve(), bench, defs, Path(__file__)]
    row = {'status': 'RUNNING', 'input_hashes': {str(p): sha(p) for p in inputs}, 'commands': []}

    def run(name, tool, argv, marker=None, negative=False):
        command = [str(SIM / tool)] + argv
        result = subprocess.run(command, cwd=out, capture_output=True, timeout=120)
        log = result.stdout + result.stderr
        (out / (name + '.log')).write_bytes(log)
        row['commands'].append({'command': command, 'return_code': result.returncode, 'log': name + '.log'})
        if marker and marker.encode() not in log:
            raise RuntimeError(name + ': missing expected marker')
        if negative:
            if b'SHIFT_DATA_PASS' in log:
                raise RuntimeError(name + ': fault escaped')
        elif result.returncode or b'SHIFT_DATA_FAIL' in log:
            raise RuntimeError(name + ': failed')

    try:
        for path, name in [(inputs[0], 'parent'), (inputs[1], 'candidate')]:
            text = path.read_text(encoding='utf-8')
            text = '`include "biriscv_defs.v"\n' + text[text.index('module triha_branch_exec'):]
            if name == 'parent':
                (out / 'old.v').write_text(text, encoding='utf-8')
                text = text.replace('triha_branch_exec', 'triha_branch_parent').replace('triha_immediate_shift_alu', 'triha_immediate_shift_parent')
            (out / (name + '.v')).write_text(text, encoding='utf-8')
        run('library', 'vlib.exe', ['work'])
        include = '+incdir+' + defs.parent.as_posix()
        run('old-compile', 'vlog.exe', [include, 'parent.v', 'old.v', str(bench)])
        run('old-poison', 'vsim.exe', ['-c', 'tb_shift_data_compare', '+POISON_INPUT', '-do', 'run -all; quit -f'], 'SHIFT_DATA_FAIL', True)
        run('candidate-compile', 'vlog.exe', [include, 'candidate.v'])
        for mode in [0, 1]:
            for extra in ['', '+POISON_INPUT', '+FAULT_RESULT']:
                negative = extra == '+FAULT_RESULT'
                argv = ['-c', 'tb_shift_data_compare', f'-gPREDECODE={mode}'] + ([extra] if extra else []) + ['-do', 'run -all; quit -f']
                run(f'candidate-{mode}-{extra or "normal"}', 'vsim.exe', argv, 'SHIFT_DATA_FAIL' if negative else 'SHIFT_DATA_PASS', negative)
        for path, value in row['input_hashes'].items():
            if sha(Path(path)) != value:
                raise ValueError('Input changed: ' + path)
        row['status'] = 'PASS'
    except Exception as exc:
        row.update(status='FAIL', error=str(exc))
        raise
    finally:
        row['output_hashes'] = {p.name: sha(p) for p in out.iterdir() if p.is_file()}
        (out / 'result.json').write_text(json.dumps(row, indent=2) + '\n', encoding='utf-8')
    print('SHIFT_DATA_CHECK_PASS', out / 'result.json')


if __name__ == '__main__':
    main()

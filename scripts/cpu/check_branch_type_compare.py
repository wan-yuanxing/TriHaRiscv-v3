"""Check isolated target comparison against a frozen parent branch module."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path('D:/modeltech64_2020.4/win64')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--old', action='store_true')
    parser.add_argument('parent', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    if not out.is_relative_to(ROOT / 'build/cpu'):
        raise ValueError('Use a fresh directory under build/cpu')
    out.mkdir(parents=True, exist_ok=False)
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    tb = ROOT / 'tb/cpu/tb_branch_type_compare.v'
    defs = ROOT / 'rtl/cpu/vendor/src/core/biriscv_defs.v'
    inputs = [args.parent.resolve(), args.candidate.resolve(), tb, defs, Path(__file__).resolve()]
    row = {'status': 'RUNNING', 'inputs': {str(p): sha(p) for p in inputs}, 'commands': []}
    try:
        for name, path in [('parent', args.parent), ('candidate', args.candidate)]:
            text = path.read_text(encoding='utf-8')
            marker = 'module triha_e1_branch'
            if text.count(marker) != 1:
                raise ValueError('Missing unique branch module')
            text = text[text.index(marker):]
            if name == 'parent':
                text = text.replace(marker, 'module triha_e1_branch_parent', 1)
            (out / (name + '.v')).write_text('`include "biriscv_defs.v"\n' + text, encoding='utf-8')
        commands = [('vlib', 'vlib.exe', ['work'], None, None),
                    ('compile', 'vlog.exe', ['+incdir+' + defs.parent.as_posix(),
                        'parent.v', 'candidate.v', str(tb)], None, None)]
        for name, extra, expected, rejected in [
            ('semantic', [], 'TARGET_COMPARE_PASS', 'TARGET_COMPARE_FAIL'),
            ('structural', ['+POISON_TARGET'], 'TARGET_COMPARE_FAIL' if args.old else 'TARGET_COMPARE_PASS', 'TARGET_COMPARE_PASS' if args.old else 'TARGET_COMPARE_FAIL'),
            ('negative', ['+FAULT_COMPARE'], 'TARGET_COMPARE_FAIL', 'TARGET_COMPARE_PASS')]:
            commands.append((name, 'vsim.exe', ['-c', 'tb_branch_type_compare'] + extra +
                             ['-do', 'run -all; quit -f'], expected, rejected))
        for name, tool, arguments, expected, rejected in commands:
            command = [str(TOOLS / tool)] + arguments
            result = subprocess.run(command, cwd=out, capture_output=True, timeout=120)
            log = result.stdout + result.stderr
            (out / (name + '.log')).write_bytes(log)
            row['commands'].append({'command': command, 'return_code': result.returncode})
            if expected and (expected.encode() not in log or rejected.encode() in log):
                raise RuntimeError(name + ' marker mismatch')
            if result.returncode and name != 'negative' and not (args.old and name=='structural'):
                raise RuntimeError(name + ' failed')
        if any(sha(Path(p)) != value for p, value in row['inputs'].items()):
            raise ValueError('Input changed')
        row['status'] = 'PASS'
    except Exception as exc:
        row.update(status='FAIL', error=str(exc))
        raise
    finally:
        row['outputs'] = {p.name: sha(p) for p in out.iterdir() if p.is_file()}
        (out / 'result.json').write_text(json.dumps(row, indent=2) + '\n', encoding='utf-8')
    print('TARGET_COMPARE_CHECK_PASS', out)


if __name__ == '__main__':
    main()

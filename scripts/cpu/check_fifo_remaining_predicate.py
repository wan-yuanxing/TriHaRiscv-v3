"""Check an isolated FIFO against its parent and independent sequence oracle."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SIM = Path('D:/modeltech64_2020.4/win64')


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
    tests = [ROOT / 'tb/cpu/tb_fifo_remaining_predicate.v', ROOT / 'tb/cpu/tb_fifo_head_ring.v']
    inputs = [args.parent.resolve(), args.candidate.resolve(), *tests, Path(__file__).resolve()]
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    row = dict(status='RUNNING', inputs={str(p): sha(p) for p in inputs}, commands=[])
    try:
        for label, path in [('parent', args.parent), ('candidate', args.candidate)]:
            text = path.read_text(encoding='utf-8')
            begin = text.index('module triha_fetch_fifo')
            end = text.index('\nendmodule', begin) + len('\nendmodule')
            text = text[begin:end]
            if label == 'parent':
                text = text.replace('module triha_fetch_fifo', 'module triha_fetch_fifo_parent', 1)
            (out / (label + '.v')).write_text(text + '\n', encoding='utf-8')
        commands = [('vlib', 'vlib.exe', ['work'], None, None),
                    ('compile', 'vlog.exe', ['parent.v', 'candidate.v', *map(str, tests)], None, None)]
        for addr in [1, 2]:
            for label, extra, fail in [('semantic', [], False),
                                      ('structural', ['+POISON_REMAINING'], args.old),
                                      ('negative', ['+FAULT_NEXT'], True)]:
                commands.append((f'{label}-{addr}', 'vsim.exe',
                    ['-c', 'tb_fifo_remaining_predicate', f'-gADDR_W={addr}', *extra,
                     '-do', 'run -all; quit -f'],
                    'FIFO_PREDICATE_FAIL' if fail else 'FIFO_PREDICATE_PASS',
                    'FIFO_PREDICATE_PASS' if fail else 'FIFO_PREDICATE_FAIL'))
        for broken in [0, 1]:
            commands.append((f'sequence-{broken}', 'vsim.exe',
                ['-c', 'tb_fifo_head_ring', f'-gBROKEN={broken}', '-do', 'run -all; quit -f'],
                'HEAD_RING_FAIL' if broken else 'HEAD_RING_PASS',
                'HEAD_RING_PASS' if broken else 'HEAD_RING_FAIL'))
        for name, tool, arguments, expected, rejected in commands:
            command = [str(SIM / tool), *arguments]
            result = subprocess.run(command, cwd=out, capture_output=True, timeout=120)
            log = result.stdout + result.stderr
            (out / (name + '.log')).write_bytes(log)
            row['commands'].append(dict(command=command, return_code=result.returncode))
            if expected and (expected.encode() not in log or rejected.encode() in log):
                raise ValueError(name + ' marker mismatch')
            if result.returncode:
                raise ValueError(name + ' tool failed')
        assert all(sha(Path(p)) == h for p, h in row['inputs'].items())
        row['status'] = 'PASS'
    except Exception as error:
        row.update(status='FAIL', error=str(error))
        raise
    finally:
        row['outputs'] = {p.name: sha(p) for p in out.iterdir() if p.is_file()}
        (out / 'result.json').write_text(json.dumps(row, indent=2) + '\n', encoding='utf-8')
    print('FIFO_PREDICATE_CHECK_PASS', out)


if __name__ == '__main__':
    main()

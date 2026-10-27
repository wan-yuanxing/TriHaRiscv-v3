"""Native ModelSim qualification of an isolated SRAM command candidate."""
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
        raise ValueError('Use a fresh build/cpu directory')
    out.mkdir(parents=True, exist_ok=False)
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    sources = [ROOT / 'rtl/soc' / name for name in
               ['triha_sram.v', 'triha_boot_rom.v', 'triha_uart_tx.v']]
    tb = ROOT / 'tb/cpu/tb_sram_local_command.v'
    inputs = sources + [tb, args.parent.resolve(), args.candidate.resolve(),
                        ROOT / 'rtl/soc/include/soc_map.vh', Path(__file__).resolve()]
    row = dict(status='RUNNING', inputs={str(p): sha(p) for p in inputs}, commands=[])
    try:
        text = args.parent.read_text(encoding='utf-8')
        assert text.count('module triha_soc_memory #(') == 1
        (out / 'parent.v').write_text(text.replace('module triha_soc_memory #(',
            'module triha_soc_memory_parent #(', 1), encoding='utf-8')
        (out / 'candidate.v').write_bytes(args.candidate.read_bytes())
        (out / 'rom.hex').write_text('0\n' * 1024, encoding='ascii')
        (out / 'sram.hex').write_text('0\n' * 4096, encoding='ascii')
        commands = [('vlib', 'vlib.exe', ['work'], None, None),
                    ('compile', 'vlog.exe', ['+incdir+' + (ROOT / 'rtl/soc/include').as_posix(),
                        *map(str, sources), 'parent.v', 'candidate.v', str(tb)], None, None)]
        for name, extra, fail in [('semantic', [], False),
                                  ('structural', ['+POISON_GENERIC'], args.old),
                                  ('negative', ['+FAULT_CE'], True)]:
            commands.append((name, 'vsim.exe', ['-c', 'tb_sram_local_command', *extra,
                '-do', 'run -all; quit -f'], 'SRAM_COMMAND_FAIL' if fail else 'SRAM_COMMAND_PASS',
                'SRAM_COMMAND_PASS' if fail else 'SRAM_COMMAND_FAIL'))
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
    print('SRAM_COMMAND_CHECK_PASS', out)


if __name__ == '__main__':
    main()

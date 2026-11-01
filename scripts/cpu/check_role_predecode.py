"""Compare actual extracted role expressions, including a late-opcode poison."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SIM = Path('D:/modeltech64_2020.4/win64')


def function(text, name):
    start = text.index('function [2:0] ' + name + ';')
    return text[start:text.index('endfunction', start) + len('endfunction')]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('parent', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--old', action='store_true')
    args = parser.parse_args()
    out = args.output.resolve()
    if not out.is_relative_to(ROOT / 'build/cpu'):
        raise ValueError('Use a new directory under build/cpu')
    out.mkdir(parents=True, exist_ok=False)
    parent = args.parent / 'triha_issue.v'
    candidate = args.candidate / 'triha_issue.v'
    decode = args.candidate / 'triha_decode.v'
    tb = ROOT / 'tb/cpu/tb_role_predecode.v'
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    inputs = [parent, candidate, decode, tb, Path(__file__).resolve()]
    row = dict(status='RUNNING', input_hashes={str(p.resolve()): sha(p) for p in inputs}, commands=[])
    ports = '(input [31:0] opcode_i,input invalid_i,input [1:0] fault_i,input [2:0] raw_i,output [2:0] roles_o);\n'
    try:
        old = function(parent.read_text(encoding='utf-8'), 'register_roles')
        source = 'module role_parent'+ports+old+'\nassign roles_o=register_roles(opcode_i,invalid_i,fault_i);\nendmodule\n'
        if args.old:
            source += 'module role_candidate'+ports+old+'\nassign roles_o=register_roles(opcode_i,invalid_i,fault_i);\nendmodule\n'
            source += 'module role_predecode(input [31:0] opcode_i,output [2:0] roles_o);\n'+old+'\nassign roles_o=register_roles(opcode_i,1\'b0,2\'b00);\nendmodule\n'
        else:
            new = function(candidate.read_text(encoding='utf-8'), 'qualify_register_roles')
            source += 'module role_candidate'+ports+new+'\nassign roles_o=qualify_register_roles(raw_i,invalid_i,fault_i);\nendmodule\n'
            text = decode.read_text(encoding='utf-8')
            start = text.index('module triha_register_roles_predecode')
            source += text[start:text.index('\nendmodule', start)+len('\nendmodule')].replace('module triha_register_roles_predecode', 'module role_predecode', 1)
        (out / 'roles.v').write_text(source, encoding='utf-8', newline='\n')
        calls = [('vlib', 'vlib.exe', ['work'], None),
                 ('compile', 'vlog.exe', ['roles.v', str(tb)], None),
                 ('semantic', 'vsim.exe', ['-c', 'tb_role_predecode', '-do', 'run -all; quit -f'], False),
                 ('poison', 'vsim.exe', ['-c', 'tb_role_predecode', '+POISON_OPCODE', '-do', 'run -all; quit -f'], args.old)]
        if not args.old:
            calls.append(('negative', 'vsim.exe', ['-c', 'tb_role_predecode', '+FAULT_ROLE', '-do', 'run -all; quit -f'], True))
        for label, tool, arguments, expected_fail in calls:
            command = [str(SIM/tool), *arguments]
            result = subprocess.run(command, cwd=out, capture_output=True, timeout=120)
            log = result.stdout + result.stderr
            (out/(label+'.log')).write_bytes(log)
            row['commands'].append(dict(command=command, return_code=result.returncode))
            if result.returncode:
                raise ValueError(label+' tool error')
            if expected_fail is not None:
                expected = b'ROLE_PREDECODE_FAIL' if expected_fail else b'ROLE_PREDECODE_PASS'
                rejected = b'ROLE_PREDECODE_PASS' if expected_fail else b'ROLE_PREDECODE_FAIL'
                assert expected in log and rejected not in log, label
        assert all(sha(Path(p)) == h for p, h in row['input_hashes'].items())
        row['status'] = 'PASS'
    except Exception as error:
        row.update(status='FAIL', error=str(error))
        raise
    finally:
        row['output_hashes'] = {p.name:sha(p) for p in out.iterdir() if p.is_file()}
        (out/'result.json').write_text(json.dumps(row, indent=2)+'\n', encoding='utf-8', newline='\n')
    print('ROLE_PREDECODE_CHECK_PASS', out)


if __name__ == '__main__':
    main()

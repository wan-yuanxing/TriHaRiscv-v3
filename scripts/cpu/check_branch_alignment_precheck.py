"""Exercise real E1 branch and extracted issue consumers against frozen v78."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path('D:/modeltech64_2020.4/win64')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract(path, parent=False):
    source = path.read_text(encoding='utf-8')
    marker = 'module triha_e1_branch'
    if source.count(marker) != 1:
        raise ValueError('Expected one real E1 branch module')
    branch = source[source.index(marker):]
    prefix = 'parent' if parent else 'candidate'
    branch = branch.replace(marker, 'module ' + prefix + '_branch', 1)
    # Test the exact expressions consumed by the real issue module.
    start = source.index('wire fault0_w=')
    end = source.index('wire train0_w=', start)
    consumer = source[start:end]
    consumer = consumer.replace('wire fault0_w=', 'assign fault0_w=').replace('wire fault1_w=', 'assign fault1_w=')
    function = ''
    if 'function branch_alignment_fault;' in source:
        start = source.index('function branch_alignment_fault;')
        function = source[start:source.index('endfunction', start) + len('endfunction')]
    ports = '''input resolve0_valid_w,resolve1_valid_w,resolved0_taken_w,resolved1_taken_w,
        input [31:0] resolved0_next_w,resolved1_next_w,
        input resolved0_target_misaligned_w,resolved1_target_misaligned_w,
        input resolved0_mismatch_w,resolved1_mismatch_w,
        input stall_w,squash_w,branch_csr_request_i,pipe0_branch_e1_w,
        output fault0_w,fault1_w,resolved_fault_w,recovery_w,cancel1_e1_w,
        output [31:0] recovery_pc_w'''
    consumer = 'module ' + prefix + '_consumer(' + ports + ');\n' + function + '\n' + consumer + '\nendmodule\n'
    return '`include "biriscv_defs.v"\n' + branch + '\n' + consumer


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
    tb = ROOT / 'tb/cpu/tb_branch_alignment_precheck.v'
    defs = ROOT / 'rtl/cpu/vendor/src/core/biriscv_defs.v'
    inputs = [args.parent.resolve(), args.candidate.resolve(), tb, defs, Path(__file__).resolve()]
    row = dict(status='RUNNING', inputs={str(p): sha(p) for p in inputs}, commands=[])
    try:
        (out / 'parent.v').write_text(extract(args.parent, True), encoding='utf-8')
        candidate = extract(args.candidate)
        if args.old:
            # Red test only: expose the old target alignment for the common TB API.
            candidate = candidate.replace('output reg mismatch_o,', 'output reg mismatch_o, output target_misaligned_o,', 1)
            candidate = candidate.replace('assign source_o=opcode_pc_i;', 'assign target_misaligned_o=branch_target_r[1:0]!=0;\nassign source_o=opcode_pc_i;', 1)
        (out / 'candidate.v').write_text(candidate, encoding='utf-8')
        commands = [('vlib', 'vlib.exe', ['work'], None),
                    ('compile', 'vlog.exe', ['+incdir+' + defs.parent.as_posix(), 'parent.v', 'candidate.v', str(tb)], None)]
        for label, extra, expected in [
            ('semantic', [], 'ALIGNMENT_PASS'),
            ('late_next_poison', ['+POISON_NEXT'], 'ALIGNMENT_FAIL' if args.old else 'ALIGNMENT_PASS'),
            ('negative', ['+FAULT_ALIGNMENT'], 'ALIGNMENT_FAIL')]:
            if args.old and label == 'negative':
                continue
            commands.append((label, 'vsim.exe', ['-c', '-voptargs=+acc', 'tb_branch_alignment_precheck'] + extra + ['-do', 'run -all; quit -f'], expected))
        for label, tool, arguments, expected in commands:
            command = [str(TOOLS / tool)] + arguments
            result = subprocess.run(command, cwd=out, capture_output=True, timeout=120)
            log = result.stdout + result.stderr
            (out / (label + '.log')).write_bytes(log)
            row['commands'].append(dict(command=command, return_code=result.returncode))
            failure_expected = expected == 'ALIGNMENT_FAIL'
            if expected and (expected.encode() not in log or (b'ALIGNMENT_FAIL' in log) != failure_expected):
                raise RuntimeError(label + ': unexpected test marker')
            if result.returncode and not failure_expected:
                raise RuntimeError(label + ': simulator failed')
        row['source_unchanged'] = all(sha(Path(p)) == digest for p, digest in row['inputs'].items())
        if not row['source_unchanged']:
            raise ValueError('Inputs changed')
        row['status'] = 'PASS'
    except Exception as exc:
        row.update(status='FAIL', error=str(exc))
        raise
    finally:
        row['outputs'] = {p.name: sha(p) for p in out.iterdir() if p.is_file()}
        (out / 'result.json').write_text(json.dumps(row, indent=2) + '\n', encoding='utf-8')
    print('ALIGNMENT_CHECK_PASS', out)


if __name__ == '__main__':
    main()

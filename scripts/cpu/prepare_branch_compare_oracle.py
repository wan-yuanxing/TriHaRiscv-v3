"""Freeze the parent's full branch module into a clocked comparison bench."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def prepare(parent_cpu, output):
    output = output.resolve()
    if output.exists() or not output.is_relative_to((ROOT / 'build/cpu').resolve()):
        raise ValueError('Use a new output file below build/cpu')
    source = parent_cpu.read_text(encoding='utf-8')
    marker = 'module triha_branch_exec'
    if source.count(marker) != 1:
        raise ValueError('Expected exactly one parent branch module')
    parent = source[source.index(marker):].replace(marker, 'module triha_branch_parent', 1)
    bench = (ROOT / 'tb/cpu/tb_exec_signed_ge.v').read_text(encoding='utf-8')
    replacements = [
        ('module tb_exec_signed_ge;', 'module tb_branch_sign_compare;'),
        ('parameter USE_DERIVATIVE=0', 'parameter USE_DERIVATIVE=1'),
        ('biriscv_exec u_reference', 'triha_branch_parent u_reference'),
        ('.opcode_rb_operand_i(b),', '.opcode_rb_operand_i(b),\n'
         '        .opcode_ra_zero_i(a == 0), .opcode_rb_zero_i(b == 0), .alu_decode_i(9\'b0),'),
    ]
    for before, after in replacements:
        if before not in bench:
            raise ValueError('Clocked comparison template changed: ' + before)
        bench = bench.replace(before, after)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(('`include "biriscv_defs.v"\n' + bench + '\n' + parent).encode('utf-8'))
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--parent-cpu', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(prepare(args.parent_cpu, args.output))

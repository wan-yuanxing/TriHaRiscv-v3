"""Conservative late-direction support check on native branch carry outputs.

Every connected cell input is treated as a dependency. This can overestimate
support; it is a local mapping diagnostic, never STA or functional proof.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re


def inspect(path, alu=False):
    raw = path.read_bytes()
    modules = []
    module_pattern = r'triha_immediate_shift_alu' if alu else r'triha_e1_branch\w*'
    for name, block in re.findall(r'\bmodule\s+(' + module_pattern + r')\b(.*?)\bendmodule\b', raw.decode('utf-8'), re.S):
        block = re.sub(r'/\*.*?\*/|//[^\n]*', '', block, flags=re.S)
        normalize = lambda x: re.sub(r'\s+', '', x).lstrip('\\')
        drivers, carries = {}, []
        for kind, instance, ports in re.findall(r'\b(GTP_\w+)\s*(?:#\s*\(.*?\)\s*)?(\\[^\s]+|[\w$]+)\s*\((.*?)\);', block, re.S):
            ports = {p: normalize(n) for p, n in re.findall(r'\.(\w+)\s*\(([^()]*)\)', ports)}
            if not kind.startswith(('GTP_LUT', 'GTP_MUX2LUT', 'GTP_INV', 'GTP_BUF')):
                continue
            inputs = [n for p, n in ports.items() if n and p not in ('Z', 'Z5', 'COUT', 'O')]
            for output in ('Z', 'Z5', 'COUT', 'O'):
                if ports.get(output):
                    drivers[ports[output]] = inputs
            if kind == 'GTP_LUT6CARRY' and ports.get('COUT'):
                carries.append((instance, ports['COUT']))
        for lhs, rhs in re.findall(r'\bassign\s+([^=;]+)=([^;]+);', block):
            lhs, rhs = normalize(lhs), normalize(rhs)
            if re.fullmatch(r'[\w$/\[\].]+', rhs):
                drivers[lhs] = [rhs]
        token = 'sub_res_w' if alu else 'branch_taken_r'
        if token not in block or not carries:
            raise ValueError('Missing expected branch direction/carry evidence: ' + name)
        late = ({'sub_res_w[' + str(i) + ']' for i in range(32)} if alu else
                {'branch_taken_r'} | {'opcode_i[' + str(i) + ']' for i in range(7)})
        violations = []
        for instance, root in carries:
            todo, seen = [root], set()
            while todo:
                net = todo.pop()
                if net in seen:
                    continue
                seen.add(net)
                if net not in late:
                    todo.extend(drivers.get(net, []))
            if seen & late:
                violations.append(dict(cell=instance, late_dependencies=sorted(seen & late)))
        modules.append(dict(module=name, carry_outputs_checked=len(carries), violations=violations))
    if len(modules) != (1 if alu else 2):
        raise ValueError('Missing expected native modules')
    return dict(status='FAIL' if any(m['violations'] for m in modules) else 'PASS',
                scope='Conservative local native carry support; hierarchy inputs outside inspected modules, CE/control, STA and equivalence are separate',
                netlist=str(path), netlist_sha256=hashlib.sha256(raw).hexdigest(), modules=modules)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('netlist', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--alu', action='store_true', help='Check secondary ALU subtraction-to-other-carry support instead')
    args = parser.parse_args()
    result = inspect(args.netlist, args.alu)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8', newline='\n')
    print('BRANCH_TARGET_CARRY_' + result['status'], [(m['module'], len(m['violations'])) for m in result['modules']])
    raise SystemExit(0 if result['status'] == 'PASS' else 1)

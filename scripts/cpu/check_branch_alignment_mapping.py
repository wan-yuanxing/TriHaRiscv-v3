"""Check real ADS alignment support and issue consumption; topology is not STA."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]


def inspect(netlist, fault_next=False, fault_disconnect=False):
    parser_path = ROOT / 'scripts/cpu/trace_head_ring_hierarchy.py'
    source = parser_path.read_text(encoding='utf-8').split('targetset=')[0]
    source = source.replace('graph={}', 'graph={};ambiguous=set()')
    before = "if o in graph:assert graph[o]==ins,('multiple drivers',o)\n graph[o]=ins"
    after = "if o in graph and graph[o]!=ins:ambiguous.add(o)\n graph[o]=list(set(graph.get(o,[])+ins))"
    if before not in source:
        raise ValueError('Hierarchy parser contract changed')
    source = source.replace(before, after)
    saved = sys.argv
    try:
        sys.argv = ['hierarchy', str(netlist)]
        state = {}
        exec(compile(source, str(parser_path), 'exec'), state)
    finally:
        sys.argv = saved
    find, graph, term = (state[k] for k in ('find', 'graph', 'term'))
    ambiguous = state['ambiguous']
    known = set(state['parent'])
    issue = 'top/u_core/u_cpu/u_issue/'
    # Recover the exact Boolean support of carry/LUT outputs, including tied
    # pins. A conservative all-pin graph can invent dependence on unused CIN.
    truth = {}
    def refine(module, path):
        decl, _, cells, _ = state['parse'](module)
        for kind, instance, pins in cells:
            if kind in state['mods']:
                refine(kind, path + '/' + instance)
        block = state['mods'][module]
        for kind, params, instance, body in re.findall(r'(?m)^\s*(\w+)\s*(?:#\s*\((.*?)\)\s*)?(\\[^\s]+|[\w$]+)\s*\((.*?)\);', block, re.S):
            if not re.fullmatch(r'GTP_LUT[1-6]D?|GTP_LUT6CARRY', kind):
                continue
            match = re.search(r"\.INIT\s*\(\s*(\d+)'([bh])([0-9a-f_]+)\s*\)", params, re.I)
            if not match:
                continue
            value = int(match[3].replace('_', ''), 2 if match[2].lower() == 'b' else 16)
            pins = {state['norm'](key): expression for key, expression in re.findall(r'\.(\\[^\s]+|\w+)\s*\(([^()]*)\)', body)}
            for pin in (['Z', 'COUT'] if kind == 'GTP_LUT6CARRY' else ['Z', 'Z5']):
                if not pins.get(pin, '').strip():
                    continue
                width = 7 if kind == 'GTP_LUT6CARRY' else 5 if pin == 'Z5' else int(kind[7])
                inputs = []
                for bit in range(width):
                    expression = pins.get('CIN' if bit == 6 else 'I' + str(bit), '')
                    inputs.append(find(state['expand'](expression, decl, path)[0]) if expression.strip() else None)
                table = value
                if kind == 'GTP_LUT6CARRY':
                    carry_i5 = 'I5_TO_CARRY("FALSE")' not in params.replace(' ', '')
                    lut_i5 = 'I5_TO_LUT("TRUE")' in params.replace(' ', '')
                    table = 0
                    for address in range(128):
                        low, high = (value >> (address & 31)) & 1, (value >> (32 + (address & 31))) & 1
                        i5, cin = (address >> 5) & 1, (address >> 6) & 1
                        output = (high if (i5 if lut_i5 else cin) else low) if pin == 'Z' else (cin if low else (i5 if carry_i5 else high))
                        table |= output << address
                node = find(state['expand'](pins[pin], decl, path)[0])
                fixed = {bit: int(child[-1]) for bit, child in enumerate(inputs) if child in ('CONST:0', 'CONST:1')}
                reachable = [address for address in range(1 << width) if all((address >> bit) & 1 == value for bit, value in fixed.items())]
                support = [bit for bit in range(width) if bit not in fixed and any(((table >> address) ^ (table >> (address ^ (1 << bit)))) & 1 for address in reachable)]
                if any(inputs[bit] is None for bit in support):
                    raise ValueError('Unconnected active LUT input: ' + node)
                graph[node] = [inputs[bit] for bit in support]
                truth[node] = (table, width, inputs, fixed, support)
    refine('triha_minimal_soc', 'top')

    def evaluate(node, values, active=frozenset()):
        node = find(node)
        if node in values:
            return values[node]
        if node in ('CONST:0', 'CONST:1'):
            return int(node[-1])
        if node in active or node not in truth or node in ambiguous:
            raise ValueError('Unsupported or cyclic truth cone: ' + node)
        table, width, inputs, fixed, support = truth[node]
        address = sum(value << bit for bit, value in fixed.items())
        for bit in support:
            address |= evaluate(inputs[bit], values, active | {node}) << bit
        return (table >> address) & 1

    def bounded(name, cuts):
        seen, active, bad = set(), set(), []

        def visit(node):
            node = find(node)
            if node in ambiguous:
                bad.append('ambiguous:' + node)
            if node in active:
                bad.append('cycle:' + node)
                return
            if node in seen:
                return
            seen.add(node)
            if node in cuts or node in term:
                return
            if node not in graph:
                bad.append('unknown:' + node)
                return
            active.add(node)
            for child in graph[node]:
                visit(child)
            active.remove(node)

        visit(name)
        return seen, sorted(set(bad))

    rows = []
    for lane in range(2):
        base = issue + 'u_branch' + str(lane) + '/'
        taken = base + 'branch_taken_r'
        next_bits = [base + 'next_pc_o[' + str(bit) + ']' for bit in range(2)]
        comparators = []
        for signal, target in [
            ('conditional_misaligned_w', ['conditional_pc_w[0]', 'conditional_pc_w[1]']),
            ('jump_misaligned_w', ['jump_pc_w[1]', 'pc_i[0]']),
            ('register_misaligned_w', ['operand_ra_i[0]', 'operand_ra_i[1]', 'opcode_i[20]', 'opcode_i[21]'])]:
            name = base + signal
            bounds = [base + value for value in target]
            if name not in known or any(value not in known for value in bounds):
                comparators.append(dict(signal=signal, status='HOLD', reason='Missing actual mapped boundary'))
                continue
            cuts = {find(value) for value in bounds}
            nodes, bad = bounded(name, cuts)
            foreign = sorted(node for node in nodes if node in term and node not in cuts and not node.startswith('CONST:'))
            truth_ok = True
            if signal == 'register_misaligned_w' and not bad and not foreign:
                for assignment in range(16):
                    values = {find(value): (assignment >> bit) & 1 for bit, value in enumerate(bounds)}
                    expected = (((assignment & 3) + ((assignment >> 2) & 3)) >> 1) & 1
                    truth_ok &= evaluate(name, values) == expected
            comparators.append(dict(signal=signal, status='PASS' if not bad and not foreign and truth_ok else 'HOLD',
                                    nodes=len(nodes), unknown=bad, foreign=foreign, sum_bit1_truth_checked=truth_ok if signal == 'register_misaligned_w' else None))
        flags = [base + row['signal'] for row in comparators]
        fault = issue + 'fault' + str(lane) + '_w'
        target_bad = base + 'target_misaligned_o'
        valid = issue + 'resolve' + str(lane) + '_valid_w'
        # ADS keeps lane A's target-select output but merges lane B's select,
        # resolve-valid and direction into the actual misprediction suppressor.
        # Inspect that consumer instead of requiring vanished RTL signal names.
        required = [taken, valid, issue + 'mispredicted_r', *flags, *next_bits]
        if any(name not in known for name in required):
            rows.append(dict(lane=lane, status='HOLD', comparators=comparators,
                             missing=[name for name in required if name not in known]))
            continue
        if fault_next and lane == 0:
            graph[find(issue + 'mispredicted_r')] = graph.get(find(issue + 'mispredicted_r'), []) + [find(next_bits[1])]
        if fault_disconnect:
            # Remove the entire new target-alignment boundary from consumers.
            node = find(flags[0])
            for key in graph:
                if key != node:
                    graph[key] = [child for child in graph[key] if child != node]
        flag_set = {find(name) for name in flags if name in known}
        cuts = set()
        for other_lane in range(2):
            other = issue + 'u_branch' + str(other_lane) + '/'
            cuts |= {find(other + signal) for signal in ('branch_taken_r', 'branch_r')}
            cuts |= {find(other + signal) for signal in ('conditional_misaligned_w', 'jump_misaligned_w', 'register_misaligned_w')}
            for signal in ('opcode_i', 'pc_i', 'operand_ra_i', 'operand_rb_i', 'predicted_pc_i', 'conditional_pc_i'):
                cuts |= {find(other + signal + '[' + str(bit) + ']') for bit in range(32)}
        cuts |= {find(issue + signal) for signal in ('resolve0_valid_w', 'resolve1_valid_w', 'stall_w', 'squash_w', 'branch_csr_request_i', 'opcode_a_valid_r')}
        module = next(kind for kind, instance, pins in state['parse']('triha_cpu')[2] if instance == 'u_issue')
        decl, ports, _, _ = state['parse'](module)
        cuts |= {find(node) for signal, direction in ports.items() if direction == 'input' for node in state['expand'](signal, decl, issue.rstrip('/'))}
        nodes, bad = bounded(issue + 'mispredicted_r', cuts)
        foreign = []
        late = sorted(nodes & {find(name) for name in next_bits})
        # All three flags must be consumed by the real misprediction logic.
        target_used = flag_set <= nodes
        okay = (all(row['status'] == 'PASS' for row in comparators) and
                not (bad or foreign or late) and target_used)
        rows.append(dict(lane=lane, status='PASS' if okay else 'HOLD', comparators=comparators,
                         fault_unknown=bad, fault_foreign=foreign, fault_late_next_hits=late,
                         new_targets_consumed_by_actual_misprediction_control=target_used,
                         actual_consumer=issue + 'mispredicted_r', consumed_flags=sorted(flag_set & nodes)))
    return dict(status='PASS' if all(row['status'] == 'PASS' for row in rows) else 'HOLD',
                scope='Actual bit support only; unchanged pipe_ctrl alignment remains a separate consumer; not delay/STA acceptance',
                netlist=str(netlist), netlist_sha256=hashlib.sha256(netlist.read_bytes()).hexdigest(),
                hierarchy_parser_sha256=hashlib.sha256(parser_path.read_bytes()).hexdigest(), rows=rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('netlist', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--fault-next', action='store_true')
    parser.add_argument('--fault-disconnect', action='store_true')
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Preserve prior mapping receipt')
    row = inspect(args.netlist.resolve(), args.fault_next, args.fault_disconnect)
    args.output.write_text(json.dumps(row, indent=2) + '\n', encoding='utf-8')
    print('ALIGNMENT_MAPPING', row['status'], args.output)
    return 0 if row['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())

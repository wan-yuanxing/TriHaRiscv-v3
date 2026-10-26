"""Conservative ADS FIFO connectivity gate; never a substitute for STA."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re


def analyze(text):
    modules = re.findall(r'(?ms)^module triha_fetch_fifo\b.*?^\s*endmodule', text)
    if len(modules) != 1:
        raise ValueError('Need exactly one actual FIFO module')
    body = re.sub(r'/\*.*?\*/|//[^\n]*|\(\*.*?\*\)', '', modules[0], flags=re.S)
    norm = lambda value: re.sub(r'\s+', '', value).lstrip('\\')
    inputs = set()
    for declaration in re.findall(r'\binput\s+(.+?)(?=,\s*(?:input|output|inout)\b|[;)])', body, re.S):
        # Support ADS non-ANSI declarations and small ANSI test fixtures.
        declaration = re.split(r',\s*(?:input|output|inout)\b', declaration)[0]
        declaration = re.sub(r'\[[^\]]+\]|\b(?:wire|reg|signed)\b', '', declaration)
        inputs.update(norm(name) for name in declaration.split(',') if name.strip())
    drivers, flops = {}, []
    primitive_counts = Counter()
    pattern = r'\b(GTP_\w+)\s*(?:#\s*\(.*?\)\s*)?(\\[^\s]+|[\w$]+)\s*\((.*?)\);'
    for kind, name, connections in re.findall(pattern, body, re.S):
        ports = {pin: norm(net) for pin, net in re.findall(r'\.(\w+)\s*\(([^()]*)\)', connections)}
        primitive_counts[kind] += 1
        if kind.startswith('GTP_DFF'):
            if not ports.get('Q') or not ports.get('D'):
                raise ValueError('Incomplete FF primitive')
            if kind.endswith('E') and not ports.get('CE'):
                raise ValueError('Enable FF missing CE connection')
            flops.append((norm(name), ports))
        elif kind.startswith(('GTP_LUT', 'GTP_MUX2LUT')):
            outputs = {'Z', 'Z5', 'COUT'}
            incoming = [net for pin, net in ports.items() if pin not in outputs and net]
            found = False
            for pin in outputs:
                if ports.get(pin):
                    found = True
                    if ports[pin] in drivers:
                        raise ValueError('Multiple net drivers')
                    drivers[ports[pin]] = incoming
            if not found:
                raise ValueError('Unknown primitive output port')
        else:
            raise ValueError('Unsupported primitive: ' + kind)
    for target, source in re.findall(r'\bassign\s+([^=;]+)=([^;]+);', body):
        target = norm(target)
        if target in drivers or any(c in target for c in '{} ,'):
            raise ValueError('Unsupported assignment target: ' + target)
        drivers[target] = [norm(v) for v in re.findall(r'\\[^\s,{}]+|[^\s,{}]+', source)]
    terminals = {ports['Q'] for _, ports in flops}
    memo = {}

    def cone(net, stack=frozenset()):
        if net in memo:
            return memo[net]
        if net in stack:
            raise ValueError('Combinational loop: ' + net)
        if net in drivers:
            children = [cone(source, stack | {net}) for source in drivers[net]]
            support = set().union(*(row[0] for row in children))
            result = support, 1 + max((row[1] for row in children), default=0)
        elif net in terminals or net.split('[')[0] in inputs:
            result = {net}, 0
        elif re.fullmatch(r"\d+'[bhd][0-9a-fxz]+", net, re.I):
            result = set(), 0
        else:
            raise ValueError('Unknown cone terminal: ' + net)
        memo[net] = result
        return result

    backend = [(name, ports) for name, ports in flops if 'ring_q[' in name]
    if not backend:
        raise ValueError('No actual backend registers')
    violations, pins, head_depths = [], 0, []
    head_late_pins = Counter()
    late_depths = {'pop0_i': [], 'pop1_i': []}
    late_memo = {}

    def late_depth(net, target):
        key = (net, target)
        if key not in late_memo:
            if net == target:
                late_memo[key] = 0
            else:
                values = [late_depth(source, target) for source in drivers.get(net, [])]
                values = [value for value in values if value is not None]
                late_memo[key] = 1 + max(values) if values else None
        return late_memo[key]
    backend_depths = []
    for name, ports in flops:
        is_backend = 'ring_q[' in name
        is_head = 'head0_q' in name or 'head1_q' in name
        if not (is_backend or is_head):
            continue
        for pin in ('D', 'CE'):
            if not ports.get(pin):
                continue
            support, depth = cone(ports[pin])
            if is_head:
                head_depths.append(depth)
                head_late_pins.update(support & {'pop0_i', 'pop1_i'})
                for target in support & {'pop0_i', 'pop1_i'}:
                    late_depths[target].append(late_depth(ports[pin], target))
            if is_backend:
                pins += 1
                backend_depths.append(depth)
                late = support & {'pop0_i', 'pop1_i'}
                if late:
                    violations.append(dict(cell=name, pin=pin, late=sorted(late)))
    return dict(status='FAIL' if violations else 'PASS', backend_ff_count=len(backend),
                backend_checked_pins=pins, backend_max_local_depth=max(backend_depths),
                head_max_local_depth=max(head_depths, default=None), violations=violations,
                head_late_pins=dict(head_late_pins),
                head_late_max_depth={key:max(values, default=None) for key,values in late_depths.items()},
                primitives=dict(primitive_counts), unknown_terminals=[],
                scope='Conservative local FIFO support at FF boundaries, including all LUT inputs; no STA/area/ISA acceptance')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('netlist', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        result = analyze(args.netlist.read_text(encoding='utf-8'))
    except ValueError as error:
        result = dict(status='UNKNOWN', error=str(error))
    result.update(netlist=str(args.netlist), netlist_sha256=hashlib.sha256(args.netlist.read_bytes()).hexdigest())
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['status'] == 'PASS' else 1)

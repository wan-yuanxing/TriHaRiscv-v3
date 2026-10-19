"""Check the issue-module PC cone in a native ADS synthesized Verilog netlist.

This is a structural diagnostic, not STA or functional equivalence. A LUT input
is conservatively considered to affect each of that cell's connected outputs.
Registers terminate the combinational search.
"""
import argparse
import hashlib
import json
import re
from collections import deque
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('netlist', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raw = args.netlist.read_bytes()
    text = raw.decode('utf-8-sig')
    module = re.search(r'\bmodule\s+triha_issue\b(.*?)\bendmodule\b', text, re.S)
    if not module:
        raise ValueError('Missing preserved triha_issue module')
    body = re.sub(r'/\*.*?\*/|//[^\n]*', '', module[1], flags=re.S)
    cell_re = re.compile(r'\b(GTP_\w+)\s*(?:#\s*\(.*?\)\s*)?(\\[^\s]+|[\w$]+)\s*\((.*?)\);', re.S)
    port_re = re.compile(r'\.(\w+)\s*\(([^()]*)\)')
    def net(value):
        return re.sub(r'\s+', '', value).lstrip('\\')
    drivers, cells, roots, terminals = {}, [], [], set()
    for high,low,name in re.findall(r'^\s*input\s+(?:\[(\d+):(\d+)\]\s+)?(\\[^\s,]+|[\w$]+)',body,re.M):
        name = net(name)
        terminals.add(name)
        if high:
            terminals.update(name+'['+str(i)+']' for i in range(int(low),int(high)+1))
    for match in cell_re.finditer(body):
        kind, name, ports = match.groups()
        name = name.lstrip('\\')
        ports = {k:net(v) for k,v in port_re.findall(ports)}
        cell = {'type':kind, 'name':name, 'ports':ports}
        cells.append(cell)
        if kind.startswith('GTP_DFF'):
            terminals.add(ports['Q'])
            if re.fullmatch(r'pc_x_q\[\d+\]', name):
                roots += [ports['D']] if ports.get('D') else []
            continue
        if kind.startswith(('GTP_LUT','GTP_MUX2LUT')):
            outputs = ('Z','Z5','COUT')
            inputs = [v for k,v in ports.items() if k not in outputs and v]
        elif kind in ('GTP_INV', 'GTP_BUF'):
            outputs = ('Z','O')
            inputs = [v for k,v in ports.items() if k not in outputs and v]
        else:
            continue
        for output in outputs:
            if ports.get(output):
                if ports[output] in drivers:
                    raise ValueError('Multiple recognized drivers: '+ports[output])
                drivers[ports[output]] = (cell, inputs)
    # Preserve hierarchy boundaries explicitly. These are not unrecognized
    # primitives and this local check makes no claim about paths inside them.
    child_terminals = set()
    for kind,name,connections in re.findall(r'\b(triha_\w+)\s+(\\[^\s]+|[\w$]+)\s*\((.*?)\);',body,re.S):
        child = re.search(r'\bmodule\s+'+re.escape(kind)+r'\b(.*?)\bendmodule\b',text,re.S)
        if not child:
            raise ValueError('Missing child module '+kind)
        output_ports = {}
        for high,low,port in re.findall(r'^\s*output\s+(?:\[(\d+):(\d+)\]\s+)?(\\[^\s,]+|[\w$]+)',child[1],re.M):
            output_ports[net(port)] = (high,low)
        for port,value in re.findall(r'\.(\\[^\s]+|[\w$]+)\s*\(([^()]*)\)',connections):
            if net(port) not in output_ports:
                continue
            high,low = output_ports[net(port)]
            value = net(value)
            if value.startswith('{'):
                child_terminals.update(n.lstrip('\\') for n in value.strip('{}').split(','))
            else:
                child_terminals.add(value)
                if high and '[' not in value:
                    child_terminals.update(value+'['+str(i)+']' for i in range(int(low),int(high)+1))
    terminals.update(child_terminals)
    for lhs,rhs in re.findall(r'\bassign\s+([^=;]+)=([^;]+);',body):
        lhs,rhs = net(lhs),net(rhs)
        if re.fullmatch(r'[\w$/\[\].]+',rhs):
            drivers[lhs] = ({'type':'assign','name':lhs},[rhs])
    if len(roots) < 30:
        raise ValueError('Incomplete PC register roots')
    cone, todo = set(),list(roots)
    while todo:
        current = todo.pop()
        if current in cone:
            continue
        cone.add(current)
        if current in drivers:
            todo.extend(drivers[current][1])
    unknown = sorted(n for n in cone if n not in drivers and n not in terminals
                     and not re.fullmatch(r"\d+'[bhd][0-9a-fxz]+",n,re.I))
    if unknown:
        raise ValueError('Unrecognized PC cone terminals: '+repr(unknown))
    requests = {'branch_csr_request_i','branch_d_exec0_request_i','branch_d_exec1_request_i'}
    def path_to_request(start):
        queue = deque([(start,[])])
        seen = set()
        while queue:
            current,path = queue.popleft()
            if current in seen:
                continue
            seen.add(current)
            if current in requests:
                return path+[current]
            if current in drivers:
                cell,inputs = drivers[current]
                queue.extend((n,path+[current]) for n in inputs)
        return None
    violations, checked = [],0
    for cell in cells:
        if cell['type'] != 'GTP_LUT6CARRY':
            continue
        cout = cell['ports'].get('COUT')
        if not cout or cout not in cone:
            continue
        checked += 1
        path = path_to_request(cout)
        if path:
            violations.append({'cell':cell['name'],'path':path})
    result = {'status':'FAIL' if violations else 'PASS',
              'scope':'Conservative structural check of issue-module PC D-input cone; CE/control cone, STA and equivalence are separate',
              'netlist':str(args.netlist.resolve()),
              'netlist_sha256':hashlib.sha256(raw).hexdigest(),
              'checker_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'pc_roots':len(roots),'pc_cone_nets':len(cone),
              'unknown_pc_cone_terminals':unknown,
              'unexpanded_child_outputs_in_pc_cone':sorted(child_terminals & cone),
              'pc_carry_outputs_checked':checked,'violations':violations}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('w',encoding='utf-8',newline='\n') as stream:
        json.dump(result,stream,indent=2)
        stream.write('\n')
    print('PC_CARRY_'+result['status'], 'carry outputs',checked,'violations',len(violations))
    return 1 if violations else 0


if __name__ == '__main__':
    raise SystemExit(main())

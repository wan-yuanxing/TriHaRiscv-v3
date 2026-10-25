"""Count actual native BTB query RAM read-address input-pin loads.

Training tag-read ports are separate. These local pin counts do not measure
global net capacitance, placement, propagation delay or timing acceptance.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re


def inspect(path, maximum=32):
    raw = path.read_bytes()
    rows = []
    for name, body in re.findall(r'\bmodule\s+(triha_btb_bank\w*)\b(.*?)\bendmodule\b', raw.decode('utf-8'), re.S):
        body = re.sub(r'/\*.*?\*/|//[^\n]*', '', body, flags=re.S)
        loads = Counter()
        cells = 0
        for instance, ports in re.findall(r'\bGTP_RAM32X2DP\s*(?:#\s*\(.*?\)\s*)?(\\[^\s]+|[\w$]+)\s*\((.*?)\);', body, re.S):
            if not ('.g_metadata[' in instance or '.g_target[' in instance):
                continue
            cells += 1
            match = re.search(r'\.RADDR\s*\(([^()]*)\)', ports)
            if not match:
                raise ValueError('Missing RAM RADDR')
            address = re.sub(r'\s+', '', match[1]).replace('\\', '').strip('{}').split(',')
            if len(address) != 5:
                raise ValueError('Expected five separate mapped address pins')
            loads.update(address)
        if cells != 224 or sum(loads.values()) != 1120:
            raise ValueError('Incomplete native query RAM evidence: ' + name)
        rows.append(dict(module=name, query_ram_cells=cells, address_pin_loads=sum(loads.values()),
                         distinct_nets=len(loads), maximum_loads=max(loads.values()), loads=dict(sorted(loads.items()))))
    if len(rows) != 2:
        raise ValueError('Expected both BTB banks')
    return dict(status='PASS' if all(r['maximum_loads'] <= maximum for r in rows) else 'FAIL',
                maximum_allowed=maximum, scope='Actual query RAM input pins only; not global fanout or STA',
                netlist=str(path), netlist_sha256=hashlib.sha256(raw).hexdigest(), modules=rows)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('netlist', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--maximum', type=int, default=32)
    args = parser.parse_args()
    if args.maximum <= 0:
        parser.error('maximum must be positive')
    result = inspect(args.netlist, args.maximum)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8', newline='\n')
    print('BTB_READ_FANOUT_' + result['status'], [(r['module'], r['maximum_loads']) for r in result['modules']])
    raise SystemExit(0 if result['status'] == 'PASS' else 1)

"""Conservative native primitive-input loads for retained ALU B nets/copies.

Only reads ADS's emitted hierarchical VM. Counts every connected primitive
input pin, including LUT inputs that might be Boolean-independent. This is a
mapping diagnostic, not a placement or timing acceptance test.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re


def inspect(path,maximum=16):
    data=path.read_bytes()
    rows=[]
    for block in re.findall(r'(?ms)^module\s+\S+.*?^endmodule',data.decode('utf-8')):
        module=block.splitlines()[0].split()[1]
        if not module.startswith('biriscv_alu'):
            continue
        loads=Counter()
        cells=re.findall(r'(?ms)^    (GTP_\w+)\s+/\*.*?\*/\s*(?:#\((.*?)\)\s*)?(\S+)\s*\((.*?)\);',block)
        for kind,parameters,name,body in cells:
            for port,net in re.findall(r'\.(\w+)\s*\(([^()]*)\)',body):
                net=re.sub(r'\s+','',net).replace('\\','')
                if port not in ['Z','Z5','Q','QN','O','CO'] and (net.startswith('alu_b_i[') or 'alu_input_b_r_' in net):
                    loads[net]+=1
        if len(loads)<32:
            raise ValueError('Incomplete native ALU B bus: '+module)
        rows.append(dict(module=module,net_count=len(loads),maximum_loads=max(loads.values()),
                         loads=dict(sorted(loads.items()))))
    if not rows:
        raise ValueError('No expected native ALU modules')
    return dict(status='PASS' if all(r['maximum_loads']<=maximum for r in rows) else 'FAIL',
                synthesis_vm=str(path),sha256=hashlib.sha256(data).hexdigest(),
                maximum_allowed=maximum,modules=rows,timing_admission=False)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('synthesis_vm',type=Path)
    parser.add_argument('--maximum',type=int,default=16)
    args=parser.parse_args()
    if args.maximum<1:
        parser.error('maximum must be positive')
    result=inspect(args.synthesis_vm,args.maximum)
    print(json.dumps(result,indent=2))
    raise SystemExit(0 if result['status']=='PASS' else 1)

"""Require each synthesized request-queue output bit to come directly from a FF.

This checks a local synthesis boundary, not functional equivalence or STA.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('netlist',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    raw=args.netlist.read_bytes()
    text=raw.decode('utf-8-sig')
    m=re.search(r'\bmodule\s+triha_lsu_fifo\b(.*?)\bendmodule\b',text,re.S)
    if not m:raise ValueError('Missing request queue module')
    body=re.sub(r'/\*.*?\*/|//[^\n]*','',m[1],flags=re.S)
    outputs=re.search(r'output\s+\[(\d+):0\]\s+data_out_o\b',body)
    if not outputs or int(outputs[1])!=35:raise ValueError('Expected complete 36-bit request tuple')
    def net(s):return re.sub(r'\s+','',s).lstrip('\\')
    aliases={net(a):net(b) for a,b in re.findall(r'assign\s+([^;=]+)=([^;]+);',body)}
    registered=set()
    for kind,name,pins in re.findall(r'\b(GTP_DFF\w*)\s*(?:#\s*\(.*?\)\s*)?(\\[^\s]+|[\w$]+)\s*\((.*?)\);',body,re.S):
        ports={k:net(v) for k,v in re.findall(r'\.(\w+)\s*\(([^()]*)\)',pins)}
        registered.add(ports['Q'])
    def resolve(n):
        seen=set()
        while n in aliases:
            if n in seen:raise ValueError('Alias cycle')
            seen.add(n);n=aliases[n]
        return n
    # ADS sometimes emits a whole-bus alias instead of individual assignments.
    def source(bit):
        n='data_out_o['+str(bit)+']'
        if 'data_out_o' in aliases and n not in aliases:
            n=aliases['data_out_o']+'['+str(bit)+']'
        return resolve(n)
    rejected=[i for i in range(36) if source(i) not in registered]
    result={'status':'FAIL' if rejected else 'PASS','scope':__doc__.strip(),
            'netlist':str(args.netlist.resolve()),'netlist_sha256':hashlib.sha256(raw).hexdigest(),
            'checker_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'output_bits_checked':36,'combinational_output_bits':rejected}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_bytes((json.dumps(result,indent=2)+'\n').encode('utf-8'))
    print('LSU_HEAD_'+result['status'],'combinational output bits',len(rejected))
    return 1 if rejected else 0


if __name__=='__main__':raise SystemExit(main())

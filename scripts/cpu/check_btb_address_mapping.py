"""Actual BTB RAM write-address control isolation and kept-delay boundaries."""
import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]


def main():
    p=argparse.ArgumentParser();p.add_argument('netlist',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--inject-control',action='store_true');p.add_argument('--collapse-delay',action='store_true');a=p.parse_args()
    assert not a.output.exists(), 'Preserve receipts'
    helper=ROOT/'scripts/cpu/trace_head_ring_hierarchy.py';code=helper.read_text().split('targetset=')[0]
    code=code.replace('graph={}','graph={};ambiguous=set()').replace("if o in graph:assert graph[o]==ins,('multiple drivers',o)\n graph[o]=ins", "if o in graph and graph[o]!=ins:ambiguous.add(o)\n graph[o]=list(set(graph.get(o,[])+ins))")
    original=sys.argv
    try:sys.argv=['hierarchy',str(a.netlist.resolve())];s={};exec(compile(code,str(helper),'exec'),s)
    finally:sys.argv=original
    find,graph,term,ambiguous=[s[n] for n in ['find','graph','term','ambiguous']]
    known=set(s['parent']);btb='top/u_core/u_cpu/u_frontend/u_npc/BRANCH_PREDICTION.g_indexed.u_btb'
    reset_names=[btb+'/'+n for n in ['rst_i','nt_rst_ni'] if btb+'/'+n in known]
    assert reset_names, 'Missing actual BTB reset boundary'
    names=reset_names+[btb+'/train_i','top/rst_ni']
    frontend=a.netlist.parent.parent/'src/rtl/cpu/triha_frontend.v'
    # The accepted physical configuration ties predictor invalidation low;
    # ADS removes that constant port. Do not treat a missing variable as safe.
    assert frontend.read_text(encoding='utf-8').count('.invalidate_i(1\'b0)')==1, 'Need frozen predictor-invalidate0 binding'
    if btb+'/invalidate_i' in known:names.append(btb+'/invalidate_i')
    missing=[n for n in names if n not in known];forbidden={find(n) for n in names}
    btb_source=a.netlist.parent.parent/'src/rtl/cpu/triha_btb.v'
    frozen=btb_source.read_text(encoding='utf-8')
    shared_half=('wire address_half_match = write_row_i[7:6] == (block_index >> 1);' in frozen and '.I1(address_half_match)' in frozen)
    def first_boundary(bank,block,bit):
        prefix=btb+f'/g_bank[{bank}].u_bank'
        names=[prefix+f'/g_block[{block}].write_address_delay_w[{bit}]']
        if shared_half:names.append(prefix+f'/g_block[{block^1}].write_address_delay_w[{bit}]')
        return next((n for n in names if n in known),None)
    first=first_boundary(0,0,0)
    last=btb+'/g_bank[0].u_bank/g_block[0].write_address_w[0]'
    if a.inject_control:graph.setdefault(find(last),[]).append(find(reset_names[0]))
    if a.collapse_delay:
        assert first is not None
        graph[find(last)]=list(graph.get(find(first),[]))
    def cone(root):
        seen=set();active=set();bad=[]
        def visit(n):
            n=find(n)
            if n in ambiguous:bad.append('ambiguous:'+n)
            if n in active:bad.append('cycle:'+n);return
            if n in seen:return
            seen.add(n)
            if n in term:return
            if n not in graph:bad.append('unknown:'+n);return
            active.add(n)
            for child in graph[n]:visit(child)
            active.remove(n)
        visit(root);return seen,sorted(set(bad))
    def distance(start,end):
        queue=deque([(find(start),0)]);end=find(end);seen=set()
        while queue:
            n,d=queue.popleft()
            if n==end:return d
            if n in seen or n in term:continue
            seen.add(n)
            queue.extend((c,d+1) for c in graph.get(n,[]))
        return None
    addresses=[];delays=[]
    for bank in range(2):
        path=btb+f'/g_bank[{bank}].u_bank'
        decl,ports,cells,_=s['parse']('triha_btb_bank')
        for kind,inst,pins in cells:
            if kind!='GTP_RAM32X2DP':continue
            roots=s['expand'](pins['WADDR'],decl,path)
            assert len(roots)==5
            bad=[];hits=set()
            for root in roots:
                nodes,errors=cone(root);bad+=errors;hits|=nodes&forbidden
            addresses.append(dict(bank=bank,cell=inst,status='PASS' if not bad and not hits else 'HOLD',
                                  forbidden_hits=sorted(hits),unknown=sorted(set(bad))))
        for block in range(8):
            for bit in range(5):
                prefix=path+f'/g_block[{block}]'
                f=first_boundary(bank,block,bit);last=prefix+f'.write_address_w[{bit}]'
                available=f is not None and last in known
                d=distance(last,f) if available else None
                delays.append(dict(bank=bank,block=block,bit=bit,status='PASS' if available and find(f) in graph and d is not None and d>0 else 'HOLD',actual_first_boundary=f,second_to_first_edges=d))
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    row=dict(status='PASS' if not missing and len(addresses)==624 and len(delays)==80 and all(r['status']=='PASS' for r in addresses+delays) else 'HOLD',
             scope='Actual624 RAM WADDR pins, full cones to FF/top inputs, reset/train/invalidate excluded;80 retained first/second LUT boundaries. Not STA.',
             netlist_sha256=sha(a.netlist),checker_sha256=sha(Path(__file__)),hierarchy_parser_sha256=sha(helper),
             frozen_frontend_sha256=sha(frontend),predictor_invalidate_constant_zero=True,
             frozen_btb_sha256=sha(btb_source),adjacent_first_stage_sharing_allowed=shared_half,actual_reset_boundaries=reset_names,
             missing=missing,addresses=addresses,delays=delays)
    a.output.write_text(json.dumps(row,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('BTB_ADDRESS_MAPPING',row['status'],'RAMs',len(addresses),'delay boundaries',sum(r['status']=='PASS' for r in delays))
    return 0 if row['status']=='PASS' else 1


if __name__=='__main__':raise SystemExit(main())

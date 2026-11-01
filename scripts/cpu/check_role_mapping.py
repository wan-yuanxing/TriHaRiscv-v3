"""Fail-closed ADS check: role qualification cannot depend on raw opcode."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    p=argparse.ArgumentParser();p.add_argument('netlist',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--inject-opcode',action='store_true');p.add_argument('--disconnect-role',action='store_true')
    args=p.parse_args();assert not args.output.exists(), 'Preserve mapping receipts'
    issue_source=args.netlist.parent.parent/'src/rtl/cpu/triha_issue.v'
    assert 'assign payload0_selected_w = 1\'b1;' in issue_source.read_text(encoding='utf-8'), 'This checker requires the frozen aligned-head configuration'
    helper=ROOT/'scripts/cpu/trace_head_ring_hierarchy.py'
    source=helper.read_text().split('targetset=')[0]
    source=source.replace('graph={}','graph={};ambiguous=set()').replace("if o in graph:assert graph[o]==ins,('multiple drivers',o)\n graph[o]=ins", "if o in graph and graph[o]!=ins:ambiguous.add(o)\n graph[o]=list(set(graph.get(o,[])+ins))")
    old=sys.argv
    try:
        sys.argv=['hierarchy',str(args.netlist.resolve())];s={};exec(compile(source,str(helper),'exec'),s)
    finally:sys.argv=old
    find,graph,term,ambiguous=[s[n] for n in ['find','graph','term','ambiguous']]
    known=set(s['parent']);base='top/u_core/u_cpu/u_issue'
    module=next(k for k,i,c in s['parse']('triha_cpu')[2] if i=='u_issue')
    decl,ports,_,_=s['parse'](module)
    opcode_formal=[n for name,d in ports.items() if name in ['fetch0_instr_i','fetch1_instr_i'] for n in s['expand'](name,decl,base)]
    assert len(opcode_formal)==64, 'Missing complete raw-opcode formal boundary'
    opcode={find(n) for n in opcode_formal}-{find('CONST:'+v) for v in '01xz'}
    cuts={find(n) for name,d in ports.items() if d=='input' and name not in ['fetch0_instr_i','fetch1_instr_i'] for n in s['expand'](name,decl,base)}
    # ADS exposes the inverted head register bundle instead of the original
    # positive-role ports. Bind those actual ports, and prove their FF sources.
    role_ports=[]
    for lane in range(2):
        choices=[name for name,d in ports.items() if d=='input' and name.endswith(f'.roles{lane}_encoded_w')]
        assert len(choices)==1, (lane,choices)
        role_ports.append(choices[0])
    roles=[base+'/'+role_ports[lane]+f'[{bit}]' for lane in range(2) for bit in range(3)]
    roots=[base+f'/{lane}_roles_w[{bit}]' for lane in ['a','b'] for bit in range(3)]
    missing=[n for n in roles+roots if n not in known]
    ff_outputs={}
    def collect_ff(module,path):
        dd,pp,cc,aa=s['parse'](module)
        for kind,inst,pins in cc:
            if kind in s['mods']:collect_ff(kind,path+'/'+inst)
            elif kind.startswith('GTP_DFF'):
                q=s['expand'](pins['Q'],dd,path)
                assert len(q)==1
                ff_outputs.setdefault(find(q[0]),[]).append(path+'/'+inst)
    collect_ff('triha_minimal_soc','top')
    if args.inject_opcode and roots[0] in known:
        n=find(roots[0]);graph[n]=graph.get(n,[])+[find(base+'/fetch0_instr_i[3]')]
    if args.disconnect_role:
        selected={find(n) for n in roles}
        for n in graph:graph[n]=[v for v in graph[n] if v not in selected]
    def cone(start,boundaries):
        seen=set();active=set();bad=[]
        def visit(n):
            n=find(n)
            if n in ambiguous:bad.append('ambiguous:'+n)
            if n in active:bad.append('cycle:'+n);return
            if n in seen:return
            seen.add(n)
            if n in boundaries or n in term:return
            if n not in graph:bad.append('unknown:'+n);return
            active.add(n)
            for child in graph[n]:visit(child)
            active.remove(n)
        visit(start);return seen,sorted(set(bad))
    rows=[]
    for i,name in enumerate(roots):
        if name not in known:continue
        # Selection may be hoisted across the issue boundary by ADS. Walk the
        # complete cone to real FF/top-input boundaries rather than accepting
        # an optimizer-created input port as a role source.
        nodes,bad=cone(name,set())
        expected={find(roles[(i%3)+(0 if i<3 else 3)])}
        hits=nodes&opcode;consumed=expected<=nodes
        rows.append(dict(root=name,status='PASS' if not bad and not hits and consumed else 'HOLD',
                         raw_opcode_hits=sorted(hits),queued_role_bits_consumed=consumed,unknown=bad,
                         observed_role_inputs=[r for r in roles if find(r) in nodes],
                         actual_ff_sources=[cell for n in nodes&term for cell in ff_outputs.get(n,[])]))
    capture=[]
    for i,name in enumerate(roles):
        if name not in known:continue
        nodes,bad=cone(name,set())
        leaves=nodes&term
        flops=[cell for n in leaves for cell in ff_outputs.get(n,[])]
        capture.append(dict(role=name,status='PASS' if not bad and len(flops)==1 and not (nodes&opcode) else 'HOLD',
                            unknown=bad,actual_ff_sources=flops))
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    result=dict(status='PASS' if not missing and len(rows)==6 and len(capture)==6 and all(r['status']=='PASS' for r in rows+capture) else 'HOLD',
                scope='Full actual role cones to FF/top inputs, no raw opcode support, plus role-to-queued-head FF connectivity. Not STA or complete FIFO semantics.',
                netlist_sha256=sha(args.netlist),checker_sha256=sha(Path(__file__)),hierarchy_parser_sha256=sha(helper),
                frozen_issue_sha256=sha(issue_source),aligned_head_a_constant=True,
                missing=missing,rows=rows,capture=capture)
    args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('ROLE_MAPPING',result['status'],'role roots',len(rows),'capture roots',len(capture),'missing',len(missing))
    return 0 if result['status']=='PASS' else 1


if __name__=='__main__':raise SystemExit(main())

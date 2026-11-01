"""Check actual flat B operand support against shared E2 result boundaries."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]


def main():
    parser=argparse.ArgumentParser();parser.add_argument('netlist',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('--inject-shared',action='store_true');parser.add_argument('--disconnect-memory',action='store_true');args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Preserve mapping receipts')
    helper=ROOT/'scripts/cpu/trace_head_ring_hierarchy.py';source=helper.read_text().split('targetset=')[0]
    source=source.replace('graph={}','graph={};ambiguous=set()').replace("if o in graph:assert graph[o]==ins,('multiple drivers',o)\n graph[o]=ins", "if o in graph and graph[o]!=ins:ambiguous.add(o)\n graph[o]=list(set(graph.get(o,[])+ins))")
    original=sys.argv
    try:
        sys.argv=['hierarchy',str(args.netlist.resolve())];state={};exec(compile(source,str(helper),'exec'),state)
    finally:sys.argv=original
    find,graph,term,ambiguous=[state[k] for k in ['find','graph','term','ambiguous']]
    known=set(state['parent']);base='top/u_core/u_cpu/u_issue/'
    shared={find(base+f'pipe{lane}_result_e2_w[{bit}]') for lane in range(2) for bit in range(32) if base+f'pipe{lane}_result_e2_w[{bit}]' in known}
    memory=[base+f'writeback_mem_bypass_i[{bit}]' for bit in range(32)]
    roots=[base+f'opcode1_{operand}_operand_o[{bit}]' for operand in ['ra','rb'] for bit in range(32)]
    missing=[n for n in memory+roots if n not in known]
    cuts=set()
    for signal,width in [('writeback_mem_bypass_i',32),('writeback_mul_early_i',32),('pipe0_nonmem_e2_w',32),('pipe1_nonmem_e2_w',32),
                         ('pipe0_result_wb_w',32),('pipe1_result_wb_w',32),('pipe0_forward_e1_w',32),('pipe1_forward_e1_w',32),
                         ('issue_b_ra_value_w',32),('issue_b_rb_value_w',32),('raw_bypass_tags_w',30),
                         ('issue_b_ra_idx_w',5),('issue_b_rb_idx_w',5)]:
        cuts|={find(base+f'{signal}[{bit}]') for bit in range(width) if base+f'{signal}[{bit}]' in known}
    for signal in ['pipe0_mem_bypass_e2_w','pipe1_mem_bypass_e2_w']:
        if base+signal in known:cuts.add(find(base+signal))
    # ADS exports RF bank words and live-writer selectors rather than the
    # original read-value ports. Treat the unchanged RF's actual outputs as
    # component boundaries; do not pretend its async RAM is a parsed FF.
    issue_module=next(kind for kind,inst,pins in state['parse']('triha_cpu')[2] if inst=='u_issue')
    rf_module=next(kind for kind,inst,pins in state['parse'](issue_module)[2] if inst=='u_regfile')
    rf_base=base+'u_regfile'
    decl,ports,_,_=state['parse'](rf_module)
    rf_outputs={find(n) for name,direction in ports.items() if direction=='output' for n in state['expand'](name,decl,rf_base)}
    rf_inputs={find(n) for name,direction in ports.items() if direction=='input' for n in state['expand'](name,decl,rf_base)}
    rf_shared_inputs=sorted(rf_inputs&shared)
    cuts|=rf_outputs
    if args.inject_shared and shared:
        n=find(roots[0]);graph[n]=graph.get(n,[])+[sorted(shared)[0]]
    if args.disconnect_memory:
        mem={find(n) for n in memory}
        for n in graph:graph[n]=[child for child in graph[n] if child not in mem]
    def cone(start):
        seen=set();active=set();bad=[]
        def visit(n):
            n=find(n)
            if n in ambiguous:bad.append('ambiguous:'+n)
            if n in active:bad.append('cycle:'+n);return
            if n in seen:return
            seen.add(n)
            if n in cuts or n in term:return
            if n not in graph:bad.append('unknown:'+n);return
            active.add(n)
            for child in graph[n]:visit(child)
            active.remove(n)
        visit(start);return seen,sorted(set(bad))
    rows=[]
    for i,name in enumerate(roots):
        if name not in known:continue
        nodes,bad=cone(name);hits=sorted(nodes&shared);used=find(memory[i%32]) in nodes
        rows.append(dict(root=name,status='PASS' if not bad and not hits and used else 'HOLD',nodes=len(nodes),shared_e2_hits=hits,unknown=bad,memory_bit_consumed=used))
    result=dict(status='PASS' if not missing and not rf_shared_inputs and len(rows)==64 and shared and all(r['status']=='PASS' for r in rows) else 'HOLD',
        scope='Actual B operand cones with data/tag/RF-output cuts; direct memory consumption without the shared E2 result bus. RF semantics are not proven by this graph. Connectivity only, not STA.',
        netlist_sha256=hashlib.sha256(args.netlist.read_bytes()).hexdigest(),checker_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        hierarchy_parser_sha256=hashlib.sha256(helper.read_bytes()).hexdigest(),missing=missing,shared_e2_boundaries=len(shared),rf_output_boundaries=len(rf_outputs),rf_shared_inputs=rf_shared_inputs,rows=rows)
    args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('DIRECT_LOAD_MAPPING',result['status'],'rows',len(rows),'shared hits',sum(bool(r['shared_e2_hits']) for r in rows),'unknown',sum(bool(r['unknown']) for r in rows))
    return 0 if result['status']=='PASS' else 1


if __name__=='__main__':raise SystemExit(main())

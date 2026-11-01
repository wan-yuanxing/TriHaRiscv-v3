"""Generate the production frame ABI and DDR layout from shared JSON sources."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def need(condition, message):
    if not condition:
        raise ValueError(message)


def uint(value):
    return type(value) is int and 0 <= value <= 0xffffffff


def disjoint(regions):
    for i, (a,n) in enumerate(regions):
        need(uint(a) and type(n) is int and n > 0 and a+n <= 0x100000000, 'address overflow/empty region')
        need(a % 32 == 0 and n % 32 == 0, '32-byte alignment')
        for b,m in regions[i+1:]:
            need(a+n <= b or b+m <= a, 'memory regions overlap')


def validate_memory(m):
    need(m['schema_version']==1 and m['ddr_base']==0x80000000 and m['ddr_bytes']==0x08000000,
         'main DDR map changed')
    need(m['window_base']==0x02000000 and m['window_bytes']==0x06000000, 'shared uncached window changed')
    regions=m['regions']; disjoint([(r['base'],r['bytes']) for r in regions])
    need(len({r['name'] for r in regions})==len(regions), 'duplicate region')
    by_name={r['name']:r for r in regions}
    need(set(by_name)==set('CPU_PRIVATE FRAMES AVATAR INPUT OUTPUT MODEL WORKSPACE RESERVED'.split()), 'region inventory')
    ordered=sorted(regions,key=lambda r:r['base'])
    need(ordered[0]['base']==m['ddr_base'] and ordered[-1]['base']+ordered[-1]['bytes']==0x88000000,
         'DDR coverage')
    for i,r in enumerate(ordered):
        need(type(r['cpu_cached']) is bool and r['cpu_cached']==(r['name']=='CPU_PRIVATE'), 'cache attribute')
        if i: need(ordered[i-1]['base']+ordered[i-1]['bytes']==r['base'], 'DDR gap')
    b=m['b03']
    for key,v in b.items():
        need(all(uint(x) for x in v) if isinstance(v,list) else uint(v), 'invalid b03 field '+key)
    need(len(b['input_bases'])==len(b['output_bases'])==3, 'three frame slots required')
    need(b['input_bases']==[0x82800000,0x82850000,0x828a0000], 'Video input slots changed')
    need(b['input_bytes']==307200 and b['input_slot_bytes']==327680, 'input geometry')
    need([b[k] for k in ('source_width','source_height','resized_width','resized_height','pad_left','pad_top')]
         ==[800,600,320,240,0,40], 'Video transform changed')
    need(b['capacity']==2100 and b['heads_bytes']==26368 and b['result_bytes']==128+32*2100, 'B03 output layout')
    need(b['parameter_origin']+b['parameter_bytes']==b['workspace_bytes'], 'parameter workspace placement')
    def inside(name,spans):
        r=by_name[name]
        for a,n in spans:
            need(r['base']<=a and a+n<=r['base']+r['bytes'], 'outside '+name)
        disjoint(spans)
    inside('INPUT',[(a,b['input_slot_bytes']) for a in b['input_bases']])
    inside('OUTPUT',[(a,b['output_slot_bytes']) for a in b['output_bases']])
    inside('MODEL',[(b['program_base'],b['program_bytes']),(b['post_table_base'],b['post_table_bytes'])])
    inside('WORKSPACE',[(b['workspace_base'],b['workspace_bytes'])])
    spans=[(b[k+'_offset'],b[k+'_bytes']) for k in ('heads','result','publish')]
    disjoint(spans)
    need(all(a+n<=b['output_slot_bytes'] for a,n in spans), 'output subregion outside slot')


def validate_regs(r):
    need(r['schema_version']==1 and r['base']==0x20000000 and r['region_bytes']==4096 and
         r['id_version']==0x4e460001, 'frame ABI identity')
    need(r['task_words']==32 and r['completion_words']==20 and len(r['completion_fields'])==20, 'descriptor size')
    offsets=[]; names=[]
    for row in r['registers']:
        need(re.fullmatch('[A-Z][A-Z0-9_]*',row['name']) and row['access'] in ('RO','WO','RW','W1C'), 'register')
        need(uint(row['offset']) and row['offset']%4==0, 'register alignment')
        offsets.append(row['offset']); names.append(row['name'])
    offsets += list(range(r['task_base'],r['task_base']+4*r['task_words'],4))
    offsets += list(range(r['completion_base'],r['completion_base']+4*r['completion_words'],4))
    need(len(set(offsets))==len(offsets) and max(offsets)<4096 and len(set(names))==len(names), 'register overlap')


def generate(root):
    root=Path(root)
    raw=[(root/'config'/name).read_bytes() for name in ('soc_memory.json','npu_frame_regs.json')]
    m,r=map(json.loads,raw); validate_memory(m); validate_regs(r)
    video=json.loads((root/'config/video_cfg.json').read_bytes())
    need(m['b03']['input_bases']==video['input_slots']['bases'], 'Video input authority mismatch')
    values={'NF_BASE':r['base'],'NF_BYTES':r['region_bytes'],'NF_ID_VERSION':r['id_version'],'NF_CAPS':r['caps'],
            'NF_TASK_BASE':r['task_base'],'NF_TASK_WORDS':r['task_words'],'NF_COMPLETION_BASE':r['completion_base'],
            'NF_COMPLETION_WORDS':r['completion_words'],'NF_START':r['control_start']}
    values.update({'NF_REG_'+x['name']:x['offset'] for x in r['registers']})
    values.update({'NF_STATUS_'+k:v for k,v in r['status'].items()})
    values.update({'NF_IRQ_'+k:v for k,v in r['interrupts'].items()})
    values.update({'NF_DONE_'+k:i for i,k in enumerate(r['completion_fields'])})
    values.update({'SOC_'+k.upper():m[k] for k in ('ddr_base','ddr_bytes','window_base','window_bytes')})
    for reg in m['regions']:
        values['SOC_'+reg['name']+'_BASE']=reg['base']; values['SOC_'+reg['name']+'_BYTES']=reg['bytes']
    for k,v in m['b03'].items():
        if isinstance(v,list): values.update({'B03_'+k.upper()+'_'+str(i):x for i,x in enumerate(v)})
        else: values['B03_'+k.upper()]=v
    digest=hashlib.sha256(b''.join(raw)).hexdigest()
    note='Generated by scripts/soc/gen_config.py; configuration SHA256 '+digest
    vh='// '+note+'\n`ifndef TRIHA_FRAME_CONFIG_VH\n`define TRIHA_FRAME_CONFIG_VH\n'
    ch='// '+note+'\n#ifndef TRIHA_FRAME_CONFIG_H\n#define TRIHA_FRAME_CONFIG_H\n'
    py='# '+note+'\n'
    for k,v in values.items():
        vh+=f"`define {k} 32'h{v:08x}\n"; ch+=f'#define {k} 0x{v:08x}u\n'; py+=f'{k} = 0x{v:08x}\n'
    return {'rtl/soc/include/frame_config.vh':(vh+'`endif\n').encode(),
            'sw/include/frame_config.h':(ch+'#endif\n').encode(),
            'scripts/soc/frame_config.py':py.encode()}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');a=p.parse_args()
    for name,data in generate(ROOT).items():
        target=ROOT/name
        if a.check: need(target.is_file() and target.read_bytes()==data,'stale generated '+name)
        else: target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    print('SOC_FRAME_CONFIG_PASS'+(' check' if a.check else ' generate'))


if __name__=='__main__': main()

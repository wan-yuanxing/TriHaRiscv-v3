"""Prepare a CPU per-operator host table; does not implement MMIO, DMA or NPU RTL."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
NONE = 0xFFFFFFFF
HF = ('magic format_id header_bytes logical_bytes allocated_bytes tensor_count param_count '
      'op_count tensor_offset tensor_stride param_offset param_stride op_offset op_stride '
      'workspace_bytes model_package_version numerics_id required_ops required_numeric_caps '
      'input_count output_count flags max_rank weight_block').split()
TF = ('id dtype rank role model_offset logical_bytes allocated_bytes element_count '
      'dim0 dim1 dim2 dim3 qmin qmax producer flags').split()
PF = 'id kind model_offset logical_bytes allocated_bytes count owner flags'.split()
OF = ('id opcode flags input_count input0 input1 output param0 param1 param2 param3').split()+['arg'+str(i) for i in range(16)]
REGIONS = list(zip(('frame_a','frame_b','frame_c','avatars','inputs','outputs','model','workspace','reserve'),
                  (0x82000000,0x82200000,0x82400000,0x82600000,0x82800000,0x82900000,0x82B00000,0x83300000,0x87300000),
                  (0x200000,0x200000,0x200000,0x200000,0x100000,0x200000,0x800000,0x4000000,0xD00000)))


def require(ok, message):
    if not ok:
        raise ValueError(message)


def integer(value):
    require(not isinstance(value, bool), 'integer required')
    if isinstance(value, str):
        value = int(value, 0)
    require(isinstance(value, int) and 0 <= value <= NONE, 'bounded unsigned integer required')
    return value


def align(value, unit=32):
    return (value+unit-1)//unit*unit


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    def unique(pairs):
        result = {}
        for k,v in pairs:
            require(k not in result, 'duplicate JSON key: '+k)
            result[k] = v
        return result
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=unique)


def write(path, value):
    Path(path).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def decode_program(blob, manifest):
    """Independently decode the identity-checked, previously numerically verified package."""
    require(digest(blob) == manifest['program_sha256'], 'program SHA256 mismatch')
    require(len(blob) >= 128, 'program length')
    words = struct.unpack_from('<32I',blob)
    h = dict(zip(HF,words))
    require(not any(words[len(HF):]), 'header reserved words')
    require(h == manifest['header'], 'header differs from manifest')
    require(h['magic']==0x5055504E and h['format_id']==1 and h['header_bytes']==128, 'program format')
    require(h['logical_bytes']==h['allocated_bytes']==len(blob), 'program length')
    require(1<=h['tensor_count']<=128 and 0<=h['param_count']<=256 and 1<=h['op_count']<=128, 'record counts')
    require(h['flags']==0 and h['max_rank']==4 and h['weight_block']==16, 'package flags/profile')
    result = {'header':h}
    cursor = 128
    for plural,prefix,stride,fields in (('tensors','tensor',64,TF),('params','param',32,PF),('ops','op',128,OF)):
        require(h[prefix+'_offset']==cursor and h[prefix+'_stride']==stride, 'record layout')
        rows=[]
        for i in range(h[prefix+'_count']):
            require(cursor+stride<=len(blob), 'record length')
            w=struct.unpack_from('<'+str(stride//4)+'I',blob,cursor)
            require(not any(w[len(fields):]), 'record reserved words')
            rows.append(dict(zip(fields,w)))
            cursor+=stride
        result[plural]=rows
    require(cursor==len(blob), 'trailing program length')
    ts,ps,ops=(result[k] for k in ('tensors','params','ops'))
    require(len(manifest['tensor_names'])==len(ts) and len(manifest['parameter_names'])==len(ps)
            and len(manifest['operator_names'])==len(ops), 'manifest names/counts')
    allocations=[]
    for i,t in enumerate(ts):
        require(t['id']==i and t['dtype'] in (1,2,3,4) and t['role'] in (0,1,2) and not t['flags'], 'tensor id/type/role')
        require(1<=t['rank']<=4 and all(t['dim'+str(j)]>0 for j in range(4)), 'tensor shape')
        require(all(t['dim'+str(j)]==1 for j in range(t['rank'],4)), 'tensor unused dimensions')
        count=math.prod(t['dim'+str(j)] for j in range(t['rank']))
        require(t['element_count']==count and t['logical_bytes']==count*(1 if t['dtype']<=2 else 2), 'tensor byte count')
        require(t['model_offset']%256==0 and t['allocated_bytes']==align(t['logical_bytes'],256), 'tensor allocation')
        allocations.append((t['model_offset'],t['model_offset']+t['allocated_bytes']))
    require(sum(t['role']==1 for t in ts)==h['input_count']==1 and sum(t['role']==2 for t in ts)==h['output_count'], 'input/output counts')
    image_start=integer(manifest['parameter_image_model_offset'])
    image_end=image_start+integer(manifest['parameter_image_bytes'])
    for i,p in enumerate(ps):
        require(p['id']==i and p['kind'] in range(1,7) and p['count']>0 and not p['flags'], 'parameter id/kind/count')
        require(p['allocated_bytes']>=p['logical_bytes']>0, 'parameter allocation')
        require(image_start<=p['model_offset']<p['model_offset']+p['allocated_bytes']<=image_end, 'parameter image range')
        allocations.append((p['model_offset'],p['model_offset']+p['allocated_bytes']))
    end=0
    for a,b in sorted(allocations):
        require(end<=a<b<=h['workspace_bytes'], 'model allocations overlap/range')
        end=b
    available={t['id'] for t in ts if t['role']==1}
    require(all(ts[i]['producer']==NONE for i in available), 'input producer')
    used=set(); mask=0
    for i,o in enumerate(ops):
        code=o['opcode']
        require(o['id']==i and code in range(1,9), 'operator id/opcode')
        require(o['flags'] in ((0,1) if code in (1,2) else (0,)), 'operator flags')
        mask|=(1<<(code-1)) | (256 if o['flags'] else 0)
        count=2 if code==3 else 1
        require(o['input_count']==count and (count==2 or o['input1']==NONE), 'operator inputs')
        inputs=[o['input0']]+([o['input1']] if count==2 else [])
        require(all(t in available and ts[t]['role']!=2 for t in inputs), 'read before producer or output read')
        output=o['output']
        require(output<len(ts) and output not in available and ts[output]['producer']==i, 'operator output')
        kinds={1:(1,2,3),2:(1,2,3),3:(4,),8:(5,6)}.get(code,())
        for j in range(4):
            pid=o['param'+str(j)]
            if j>=len(kinds):
                require(pid==NONE, 'unused parameter')
            else:
                require(pid<len(ps) and ps[pid]['kind']==kinds[j], 'parameter reference/kind')
                require(ps[pid]['owner']==(NONE if kinds[j]==6 else i), 'parameter owner')
                used.add(pid)
        available.add(output)
    require(len(available)==len(ts) and used==set(range(len(ps))), 'unproduced tensor or unused parameter')
    require(mask==h['required_ops'] and h['required_numeric_caps']==127, 'capabilities')
    return result


def range_in(base, length, outer, label, alignment=32):
    base,length=integer(base),integer(length)
    require(length>0 and base%alignment==0 and base+length<=2**32, label+' alignment/overflow')
    require(outer[0]<=base<base+length<=outer[1], label+' outside reserved region')
    return base,base+length,label


def disjoint(rows, label):
    rows=sorted(rows)
    for prev,now in zip(rows,rows[1:]):
        require(prev[1]<=now[0], label+' overlap: '+prev[2]+'/'+now[2])


def bind_program(program, manifest, video, fixture):
    require(fixture['schema_version']==1 and fixture['control']=='cpu_per_operator', 'control/schema')
    require(fixture['final_landmarks_required'] is True, 'final landmark requirement must be preserved')
    require(integer(fixture['ddr_base'])==0x80000000 and integer(fixture['ddr_bytes'])==0x8000000, 'DDR128MiB contract')
    require(integer(fixture['npu_mmio_base'])==0x20000000, 'NPU MMIO contract')
    require(len(fixture['shared_regions'])==len(REGIONS), 'shared region count')
    regions={}
    for got,(name,base,length) in zip(fixture['shared_regions'],REGIONS):
        require((got['name'],integer(got['base']),integer(got['bytes']))==(name,base,length), 'shared region differs from main specification: '+name)
        regions[name]=(base,base+length)
    det=video['detector']
    fmt={'active_width':320,'active_height':240,'storage_height':320,'pad_top':40,'pad_bottom':40,
         'valid_channels':3,'storage_channels':3,'channel_order':'BGR','layout':'NCHW','dtype':'UINT8',
         'scale':1,'zero_point':0,'preprocess_version':1}
    require(all(type(det[k]) is type(v) and det[k]==v for k,v in fmt.items()), 'Video input format mismatch')
    frames=video['frame_slots']
    require(frames['bases']==[0x82000000,0x82200000,0x82400000] and frames['slot_bytes']==0x200000
            and frames['preview_offset']==0x160000, 'Video frame region mismatch')
    inp=video['input_slots']
    require(inp['region_base']==regions['inputs'][0] and inp['region_bytes']==0x100000
            and inp['slot_bytes']==0x50000 and inp['bases']==[0x82800000,0x82850000,0x828A0000], 'Video input slots mismatch')
    input_rows=[range_in(b,inp['slot_bytes'],regions['inputs'],'input'+str(i)) for i,b in enumerate(inp['bases'])]
    disjoint(input_rows,'input')
    tensors=program['tensors']; names=manifest['tensor_names']
    require(names[0]=='input' and tensors[0]['role']==1 and tensors[0]['logical_bytes']==307200, 'model input mismatch')
    heads=[{**t,'name':names[t['id']]} for t in tensors if t['role']==2]
    head_size=sum(t['allocated_bytes'] for t in heads)
    out_size=integer(fixture['output_slot_bytes'])
    require(out_size>=head_size and out_size%256==0, 'output slot capacity/alignment')
    require(len(fixture['output_bases'])==3, 'three output slots required')
    output_rows=[range_in(b,out_size,regions['outputs'],'output'+str(i),256) for i,b in enumerate(fixture['output_bases'])]
    disjoint(output_rows,'output')
    workspace=range_in(fixture['workspace_base'],program['header']['workspace_bytes'],regions['workspace'],'workspace')[0]
    weights=range_in(fixture['weights_base'],manifest['parameter_image_bytes'],regions['model'],'weights')[0]
    table_row=range_in(fixture['table_base'],fixture['table_reserved_bytes'],regions['model'],'CPU table')
    disjoint([(weights,weights+manifest['parameter_image_bytes'],'weights'),table_row],'weights/table')
    slots=[]
    for i,out in enumerate(output_rows):
        addresses=[workspace+t['model_offset'] for t in tensors]
        addresses[0]=input_rows[i][0]
        cursor=out[0]; bound_heads=[]
        for t in heads:
            addresses[t['id']]=cursor
            bound_heads.append({k:t[k] for k in ('id','name','dtype','logical_bytes','allocated_bytes')})
            bound_heads[-1]['address']=cursor
            cursor+=t['allocated_bytes']
        slots.append({'slot':i,'input_base':input_rows[i][0],'output_base':out[0],
                      'tensor_addresses':addresses,'heads':bound_heads})
    parameters=[{**p,'name':manifest['parameter_names'][p['id']],
                 'address':weights+p['model_offset']-manifest['parameter_image_model_offset']} for p in program['params']]
    return {'schema_version':1,'scope':'CPU offline table; MMIO encoding and hardware execution unimplemented',
            'control':'cpu_per_operator','hardware_ready':False,'final_landmarks_required':True,
            'final_model_compatible':all('kps_'+str(s) in [t['name'] for t in heads] for s in (8,16,32)),
            'input_copy_bytes':0,'head_logical_bytes':sum(t['logical_bytes'] for t in heads),
            'head_allocated_bytes':head_size,'workspace_base':workspace,'weights_base':weights,
            'table_base':table_row[0],'table_reserved_bytes':table_row[1]-table_row[0],
            'slots':slots,'parameters':parameters,'operator_names':manifest['operator_names'],
            'operator_ticket_policy':'software ordered tickets, not upstream CMD_ID; register adapter pending'}


def resource_scenarios(video, avatar, npu, cfg):
    require(all(isinstance(x,(int,float)) and not isinstance(x,bool) and math.isfinite(x) and x>=0 for x in (video,avatar,npu)), 'resource values')
    require(video>=avatar, 'avatar cache exceeds Video resources')
    cpu=(align(integer(cfg['cpu_rom_bytes']),integer(cfg['payload_bytes_per_drm']))+
         align(integer(cfg['cpu_sram_bytes']),integer(cfg['payload_bytes_per_drm'])))/integer(cfg['payload_bytes_per_drm'])
    extra=integer(cfg['fabric_extra_drm'])
    raw=video-avatar+npu+cpu+extra
    result=[]
    for name,total in (('unchanged_video_plus_npu_only',video+npu),
                       ('raw_without_full_avatar_cache_candidate',raw),
                       ('ddr_avatar_cache_candidate',raw+integer(cfg['replacement_avatar_cache_drm']))):
        margin=integer(cfg['device_drm'])-total
        result.append({'name':name,'drm':total,'margin_drm':margin,'arithmetic_fits':margin>=0,
                       'hardware_ready':False,'scope':'planning sum, not a combined implementation measurement'})
    return result


def table_binary(program, bound):
    sections=[]
    def add(name,words):
        sections.append((name,struct.pack('<'+str(len(words))+'I',*words)))
    add('tensors',[t[k] for t in program['tensors'] for k in TF])
    add('tensor_addresses',[a for s in bound['slots'] for a in s['tensor_addresses']])
    add('parameters',[p[k] for p in program['params'] for k in PF])
    add('parameter_addresses',[p['address'] for p in bound['parameters']])
    sections.append(('operators',b''.join(struct.pack('<32I',*[o[k] for k in OF],*([0]*5)) for o in program['ops'])))
    data=bytearray(128); layout={}
    for name,content in sections:
        data.extend(bytes(align(len(data))-len(data)))
        layout[name]={'offset':len(data),'bytes':len(content)}
        data.extend(content)
    data.extend(bytes(align(len(data))-len(data)))
    require(len(data)<=bound['table_reserved_bytes'], 'CPU table capacity')
    header=[0x54434E54,1,len(data),3,len(program['tensors']),len(program['params']),len(program['ops']),
            *[v['offset'] for v in layout.values()],bound['weights_base'],bound['workspace_base'],0,0]
    struct.pack_into('<32I',data,0,*header,*([0]*(32-len(header))))
    return bytes(data),layout


def render_c(blob, bound, layout):
    words=struct.unpack('<'+str(len(blob)//4)+'I',blob)
    lines=['/* Generated HOST preparation table; not a released MMIO or firmware ABI. */',
           '#ifndef TRIHA_NPU_CPU_TABLE_H','#define TRIHA_NPU_CPU_TABLE_H','#include <stdint.h>',
           '#define TRIHA_NPU_HARDWARE_READY 0u',
           '#define TRIHA_NPU_FINAL_MODEL_COMPATIBLE '+str(int(bound['final_model_compatible']))+'u',
           '#define TRIHA_NPU_TABLE_BYTES '+str(len(blob))+'u',
           '#define TRIHA_NPU_TABLE_BASE UINT32_C(0x%08X)'%bound['table_base']]
    for name,part in layout.items():
        lines.append('#define TRIHA_NPU_'+name.upper()+'_OFFSET '+str(part['offset'])+'u')
    lines+=['/* Default: loader installs npu_cpu_table.bin in DDR; do not fill 8KiB Boot ROM. */',
            '#ifdef TRIHA_NPU_EMBED_HOST_TABLE',
            'static const uint32_t triha_npu_cpu_table[%d] = {'%len(words)]
    for i in range(0,len(words),8):
        lines.append('    '+', '.join('UINT32_C(0x%08X)'%w for w in words[i:i+8])+',')
    lines+=['};','#else',
            '#define triha_npu_cpu_table ((const uint32_t *)(uintptr_t)TRIHA_NPU_TABLE_BASE)',
            '#endif','#endif','']
    return '\n'.join(lines)


def run(args, output):
    npu=args.npu_root.resolve()
    mpath=npu/'yunet/baseline/program_package_manifest_v0_1.json'
    manifest=read(mpath)
    files={Path(__file__).resolve(),ROOT/'scripts/npu/test_prepare_integration.py',args.fixture.resolve(),
           ROOT/'config/video_cfg.json',ROOT/'docs/TriHaRiscv_SoC_Design_Spec_v0.6.md',
           ROOT/'docs/superpowers/specs/2026-10-21-npu-integration-preparation-design.md',
           mpath,args.program.resolve(),args.parameters.resolve(),
           ROOT/'docs/verification/video/evidence/mode_board.json',ROOT/'docs/verification/video/evidence/mode_resources.json',
           npu/'yunet/baseline/control_plane_summary_v1.json',npu/'yunet/models/model_manifest.json'}
    for rel in manifest['source_sha256']:
        p=(npu/rel).resolve()
        require(p.is_relative_to(npu), 'manifest path outside NPU root')
        files.add(p)
    cpu_ref=ROOT.parent/'TriHaRiscv-cpu-windows/docs/verification/cpu/operand_hazard.json'
    if cpu_ref.is_file(): files.add(cpu_ref)
    before={str(p):digest(p.read_bytes()) for p in sorted(files)}
    for rel,expected in manifest['source_sha256'].items():
        require(before[str((npu/rel).resolve())]==expected, 'source SHA256 mismatch: '+rel)
    parameters=args.parameters.read_bytes()
    require(digest(parameters)==manifest['parameter_image_sha256'] and len(parameters)==manifest['parameter_image_bytes'], 'parameter image SHA256/length mismatch')
    program=decode_program(args.program.read_bytes(),manifest)
    fixture=read(args.fixture)
    bound=bind_program(program,manifest,read(ROOT/'config/video_cfg.json'),fixture)
    numeric=read(npu/'yunet/models/integer_numerics_v1.json')
    processing=read(npu/'yunet/models/processing_contract_v1.json')
    require([t['name'] for t in bound['slots'][0]['heads']]==list(numeric['heads'])==[r['name'] for r in processing['outputs']], 'numeric/processing head order mismatch')
    model=read(npu/'yunet/models/model_manifest.json')
    require(digest((npu/numeric['source_model']['path']).read_bytes())==numeric['source_model']['sha256']==model['derived_sha256'], 'model SHA256 mismatch')
    table,layout=table_binary(program,bound)
    bound.update(cpu_table_bytes=len(table),cpu_table_sections=layout)
    video=read(ROOT/'docs/verification/video/evidence/mode_board.json')['resources']['drm']
    avatar=read(ROOT/'docs/verification/video/evidence/mode_resources.json')['resources']['video_avatar_cache']['drm']
    control=read(npu/'yunet/baseline/control_plane_summary_v1.json')
    npu_drm=max(p['NPU_total_DRM36eq_reserve_preserved'] for p in control['resource_profiles'].values())
    bound['resource_scenarios']=resource_scenarios(video,avatar,npu_drm,fixture['resource_budget'])
    write(output/'bindings.json',bound)
    (output/'npu_cpu_table.bin').write_bytes(table)
    (output/'npu_cpu_table.h').write_text(render_c(table,bound,layout),encoding='utf-8')
    (output/'npu_parameters.bin').write_bytes(parameters)
    after={str(p):digest(p.read_bytes()) for p in sorted(files)}
    require(after==before, 'source changed during preparation')
    cpu=None
    if cpu_ref in files:
        report=read(cpu_ref)
        cpu={'evidence_path':str(cpu_ref),'timing_reported_closed':report['timing']['closed'],
             'reported_worst_setup_ns':report['timing']['worst_setup_ns'],'reported_cpu_only_resources':report['cpu_only_resources'],
             'scope':'read historical evidence only; current dirty CPU sources, timing and board image not verified by this preparation'}
    result={'schema_version':1,'preparation_status':'PASS','hardware_ready':False,
            'generated_utc':datetime.now(timezone.utc).isoformat(),'python':sys.version,
            'scope':bound['scope'],'input_sha256':before,'output_sha256':{p.name:digest(p.read_bytes()) for p in sorted(output.iterdir()) if p.is_file()},
            'counts':{k:len(program[k]) for k in ('tensors','params','ops')},'slots':3,
            'head_logical_bytes':bound['head_logical_bytes'],'head_allocated_bytes':bound['head_allocated_bytes'],
            'cpu_table_bytes':len(table),'resource_scenarios':bound['resource_scenarios'],'cpu_reference':cpu,
            'open_gates':['MMIO operator encoding and driver','real NPU operator/controller/DMA',
                          'CPU stable import into main','125/100MHz fabric CDC and width conversion',
                          'cross-master visibility, drain and coordinated reset','combined resource and timing implementation',
                          'final five-landmark model and quantization','board inference and continuous stability acceptance'],
            'board_programmed':False,'rtl_simulation_run':False,'pds_run':False}
    write(output/'result.json',result)
    print('HOST_PREPARATION_PASS: 3 slots, %d tensors, %d parameters, %d operators; HARDWARE_READY=false'%
          (len(program['tensors']),len(program['params']),len(program['ops'])))
    print(output/'result.json')
    return 2 if args.require_hardware_ready else 0


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--npu-root',type=Path,required=True)
    parser.add_argument('--program',type=Path,required=True)
    parser.add_argument('--parameters',type=Path,required=True)
    parser.add_argument('--fixture',type=Path,default=ROOT/'config/npu_integration_fixture.json')
    parser.add_argument('--output-dir',type=Path)
    parser.add_argument('--require-hardware-ready',action='store_true')
    args=parser.parse_args()
    output=(args.output_dir or ROOT/'build/npu'/datetime.now(timezone.utc).strftime('prepare-%Y%m%dT%H%M%S_%fZ')).resolve()
    try:
        output.mkdir(parents=True,exist_ok=False)
    except OSError as exc:
        print('FAIL: output must be a new directory: '+str(exc),file=sys.stderr)
        return 1
    try:
        return run(args,output)
    except (OSError,ValueError,KeyError,TypeError,struct.error,ZeroDivisionError) as exc:
        write(output/'result.json',{'preparation_status':'FAIL','hardware_ready':False,'error':str(exc)})
        print('FAIL: '+str(exc),file=sys.stderr)
        return 1


if __name__=='__main__':
    raise SystemExit(main())

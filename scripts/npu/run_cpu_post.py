"""CPU-post ABI regression with frozen B03 bytes and independently located boxes."""
import argparse
import hashlib
import json
import math
from fractions import Fraction
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
from frozen_inputs import FrozenInputs
from run_b03_frame import ROOT, DEFAULT_ASSETS, DEFAULT_MANIFEST, common, checked_asset, load_manifest, need


def run(out,only_case=None):
    out=out.resolve();out.mkdir(parents=True,exist_ok=False)
    row={'status':'RUNNING','board_verified':False,'tests':[]}
    common.write_json(out/'result.json',row)
    try:
        names=['sw/drivers/npu_frame.c','sw/include/npu_frame.h','sw/include/frame_config.h',
               'tb/soc/test_npu_cpu_post.c','scripts/npu/run_cpu_post.py']
        frozen=FrozenInputs(ROOT,out/'inputs',names)
        manifest=load_manifest(DEFAULT_MANIFEST);frozen.track(DEFAULT_MANIFEST)
        table=checked_asset(DEFAULT_ASSETS,'post_table.bin',manifest['files_sha256'])
        frozen.external(DEFAULT_ASSETS/'post_table.bin',out/'table.bin')
        cc=Path(os.environ.get('TRIHA_HOST_CC','D:/Xilinx/Vivado/2018.3/msys64/mingw64/bin/gcc.exe'))
        frozen.track(cc);env=dict(os.environ)
        env['PATH']=str(cc.parent)+os.pathsep+str(cc.parents[2]/'usr/bin')+os.pathsep+env['PATH']
        def execute(args,label):
            p=subprocess.run(list(map(str,args)),capture_output=True,env=env,timeout=60)
            (out/(label+'.log')).write_bytes(p.stdout+p.stderr)
            need(p.returncode==0,label+' failed: '+(p.stdout+p.stderr).decode(errors='replace'))
            return p.stdout.decode().replace('\r\n','\n')
        execute([cc,'-static','-std=c99','-O2','-Wall','-Wextra','-Werror','-I'+str(out/'inputs/sw/include'),
                 out/'inputs/tb/soc/test_npu_cpu_post.c',out/'inputs/sw/drivers/npu_frame.c','-o',out/'test.exe'],'compile')
        frozen.track(out/'test.exe')
        tests=[]
        for case in ('zero','pattern','full255'):
            raw=checked_asset(DEFAULT_ASSETS,f'cases/{case}/heads_golden.bin',manifest['files_sha256'])
            expected=checked_asset(DEFAULT_ASSETS,f'cases/{case}/records_golden.bin',manifest['files_sha256'])
            need(not expected,'empty reference fixture expected')
            tests.append((case,raw,[]))
        # Use the manifest BYTE offsets, distinct from the C implementation.
        slots={x['name']:x['slot_offset'] for x in manifest['head_slot_map']}
        def box(scale,index,codes):
            stride=(8,16,32)[scale];grid=320//stride
            values=[Fraction(struct.unpack_from('<f',table,scale*524288+(code&65535)*8+(4 if axis>=2 else 0))[0]) for axis,code in enumerate(codes)]
            cx=(index%grid+values[0])*stride;cy=(index//grid+values[1])*stride
            x1=math.floor(max(0,min(320,cx-values[2]/2))*Fraction(5,2))
            x2=math.ceil(max(0,min(320,cx+values[2]/2))*Fraction(5,2))
            y1=math.floor(max(0,min(240,cy-values[3]/2-40))*Fraction(5,2))
            y2=math.ceil(max(0,min(240,cy+values[3]/2-40))*Fraction(5,2))
            return [(0,1600,2000)[scale]+index,x1,y1,x2-x1,y2-y1] if x2>x1 and y2>y1 else None
        for scale,stride in enumerate((8,16,32)):
            grid=320//stride
            for index in (grid*5+5,grid*5+6,grid*grid-1):
                raw=bytearray(26368)
                for leaf in ('cls','obj'):struct.pack_into('<H',raw,slots[f'{leaf}_{stride}']+index*2,65535)
                # bbox raw zero means dx=dy=0 and exp(0)*stride extent.
                column,yrow=index%grid,index//grid
                x1=max(Fraction(0),Fraction(column*stride)-Fraction(stride,2))*Fraction(5,2)
                y1=max(Fraction(0),Fraction(yrow*stride)-Fraction(stride,2)-40)*Fraction(5,2)
                x2=min(Fraction(320),Fraction(column*stride)+Fraction(stride,2))*Fraction(5,2)
                y2=min(Fraction(240),max(Fraction(0),Fraction(yrow*stride)+Fraction(stride,2)-40))*Fraction(5,2)
                x1,y1,x2,y2=math.floor(x1),math.floor(y1),math.ceil(x2),math.ceil(y2)
                want=[] if y2<=y1 else [[(0,1600,2000)[scale]+index,x1,y1,x2-x1,y2-y1]]
                tests.append((f'face_s{stride}_i{index}',raw,want))
            for codes in ((1024,-512,2000,-1000),(-2048,1024,-2000,1000)):
                index=grid*6+5;raw=bytearray(26368)
                for leaf in ('cls','obj'):struct.pack_into('<H',raw,slots[f'{leaf}_{stride}']+index*2,65535)
                struct.pack_into('<4h',raw,slots[f'bbox_{stride}']+index*8,*codes)
                expected=box(scale,index,codes)
                tests.append((f'fraction_s{stride}_{codes[0]}',raw,[expected] if expected else []))
        # Full-head oracle: no pre-NMS top-k truncation.
        raw=bytearray(26368);ranked=[]
        for index in [*range(400,464),1200]:
            prob=65535 if index==1200 else 40000
            for leaf in ('cls','obj'):struct.pack_into('<H',raw,slots[f'{leaf}_8']+index*2,prob)
            ranked.append((prob*prob,box(0,index,(0,0,0,0))))
        ranked.sort(key=lambda v:(-v[0],v[1][0]));kept=[]
        for _,candidate in ranked:
            _,x,y,w,h=candidate
            def overlap(other):
                _,ox,oy,ow,oh=other
                inter=max(0,min(x+w,ox+ow)-max(x,ox))*max(0,min(y+h,oy+oh)-max(y,oy))
                return inter*10>(w*h+ow*oh-inter)*3
            if not any(overlap(k) for k in kept):kept.append(candidate)
            if len(kept)==16:break
        tests.append(('late_strong_candidate',raw,kept))
        # Dense large boxes suppress to fewer than 16 survivors; the lower-score
        # small box must still be considered after the entire high-score prefix.
        def full_nms(ranked_boxes):
            kept=[]
            for candidate in ranked_boxes:
                if candidate is None:continue
                _,x,y,w,h=candidate
                def suppressed(other):
                    _,ox,oy,ow,oh=other
                    inter=max(0,min(x+w,ox+ow)-max(x,ox))*max(0,min(y+h,oy+oh)-max(y,oy))
                    return Fraction(inter,w*h+ow*oh-inter)>Fraction(3,10)
                if not any(suppressed(other) for other in kept):kept.append(candidate)
                if len(kept)==16:break
            return kept
        for count in (64,65,128,129,2099):
            raw=bytearray(26368)
            ranked=[]
            for candidate in range(count):
                scale=0 if candidate<1600 else 1 if candidate<2000 else 2
                index=candidate-(0,1600,2000)[scale];stride=(8,16,32)[scale]
                for leaf in ('cls','obj'):
                    struct.pack_into('<H',raw,slots[f'{leaf}_{stride}']+index*2,65535)
                struct.pack_into('<4h',raw,slots[f'bbox_{stride}']+index*8,0,0,32767,32767)
                ranked.append(box(scale,index,(0,0,32767,32767)))
            # Last head is a visible small box in stride 32, outside top 64.
            for leaf in ('cls','obj'):struct.pack_into('<H',raw,slots[f'{leaf}_32']+99*2,50000)
            want=full_nms(ranked+[box(2,99,(0,0,0,0))])
            if count<2099:
                need(any(b[0]==2099 for b in want),'adversarial late box must survive oracle')
            tests.append((f'suppressed_prefix_{count}',raw,want))
        # 49999*50001 < 50000**2, but both round to the same FP32 score.
        # Candidate id, not the raw product, breaks the tie, including NMS.
        for overlap_tie in (False,True):
            raw=bytearray(26368);codes=(0,0,12000,12000) if overlap_tie else (0,0,0,0)
            ids=(410,411) if overlap_tie else (410,414)
            for index,cls,obj in ((ids[0],49999,50001),(ids[1],50000,50000)):
                struct.pack_into('<H',raw,slots['cls_8']+index*2,cls)
                struct.pack_into('<H',raw,slots['obj_8']+index*2,obj)
                struct.pack_into('<4h',raw,slots['bbox_8']+index*8,*codes)
            tests.append(('rounded_tie_nms' if overlap_tie else 'rounded_tie_order',raw,
                          [box(0,index,codes) for index in (ids[:1] if overlap_tie else ids)]))
        raw=bytearray(26368)
        for index,prob in ((410,55000),(411,65535),(414,60000)):
            for leaf in ('cls','obj'):struct.pack_into('<H',raw,slots[f'{leaf}_8']+index*2,prob)
            struct.pack_into('<4h',raw,slots['bbox_8']+index*8,0,0,12000,12000)
        tests.append(('overlap_nms',raw,[box(0,index,(0,0,12000,12000)) for index in (411,414)]))
        for cls,obj in [(39321,39321),(39322,39322),(65535,23593),(65535,23594),
                        *[(40000+i*997,65535-i*509) for i in range(25)]]:
            raw=bytearray(26368);index=410
            struct.pack_into('<H',raw,slots['cls_8']+index*2,cls)
            struct.pack_into('<H',raw,slots['obj_8']+index*2,obj)
            want=[box(0,index,(0,0,0,0))] if cls*obj>=1546188224 else []
            tests.append((f'score_{cls}_{obj}',raw,want))
        if only_case:
            tests=[case for case in tests if case[0]==only_case]
            need(tests,'unknown case '+only_case)
        for name,raw,want in tests:
            path=out/(name+'.bin');path.write_bytes(raw);frozen.track(path)
            text=execute([out/'test.exe',out/'table.bin',path],name)
            actual=[list(map(int,m)) for m in re.findall(r'^BOX (\d+) (\d+) (\d+) (\d+) (\d+)$',text,re.M)]
            need(actual==want,name+f' boxes {actual} != {want}')
            scores=dict((int(a),int(b)) for a,b in re.findall(r'^SCORE (\d+) (\d+)$',text,re.M))
            for candidate,*_ in actual:
                scale=0 if candidate<1600 else 1 if candidate<2000 else 2
                stride=(8,16,32)[scale];index=candidate-(0,1600,2000)[scale]
                cls=struct.unpack_from('<H',raw,slots[f'cls_{stride}']+index*2)[0]
                obj=struct.unpack_from('<H',raw,slots[f'obj_{stride}']+index*2)[0]
                product_f32=struct.unpack('<f',struct.pack('<f',cls*obj/2**32))[0]
                expected_score=struct.unpack('<I',struct.pack('<f',math.sqrt(product_f32)))[0]
                need(scores.get(candidate)==expected_score,name+' FP32 score ABI mismatch')
            row['tests'].append({'name':name,'boxes':actual,'head_sha256':hashlib.sha256(raw).hexdigest()})
        frozen.verify();row.update(status='PASS',source_sha256=frozen.inputs,tracked_sha256=frozen.tracked,external_sha256=frozen.external_inputs)
    except Exception as exc:row.update(status='FAIL',error=str(exc))
    common.write_json(out/'result.json',row);print(row['status'],row.get('error',''))
    return int(row['status']!='PASS')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',required=True,type=Path)
    p.add_argument('--case',help='Run one named regression (also useful for negative controls)')
    args=p.parse_args();sys.exit(run(args.output,args.case))

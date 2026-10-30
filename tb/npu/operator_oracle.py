"""Independent scalar convolution oracle: exact Python integers and Fraction RNE."""
from fractions import Fraction
from pathlib import Path
import json
import hashlib
import random
import struct

INPUT,WEIGHT,BIAS,REQUANT,OUTPUT=0x82800000,0x82B00000,0x82B01000,0x82B02000,0x83300000


def rounded(value, shift):
    if not 0<=shift<=63: raise ValueError('shift')
    return round(Fraction(value,1<<shift))


def make_case(seed, **overrides):
    c=dict(iw=5,ih=4,ci=3,co=5,kernel=3,stride=1,pad=1,dw=0,signed=0,fmt=1,
           bias=None,mult=3,shift=4,expected_error=0,inject_error=0,alias=0)
    c.update(overrides); r=random.Random(seed)
    k,s,p=c['kernel'],c['stride'],c['pad']; ow=(c['iw']+2*p-k)//s+1; oh=(c['ih']+2*p-k)//s+1
    cfg=[INPUT,WEIGHT,BIAS,REQUANT,INPUT if c['alias'] else OUTPUT,c['iw'],c['ih'],c['ci'],c['co'],
         ow,oh,k,s,p,c['dw'],c['signed'],c['fmt'],c['expected_error'],c['inject_error']]
    if 'ow' in c: cfg[9]=c['ow']
    mem=bytearray([0xA5]*32768)
    xs=[r.randint(-127,127) if c['signed'] else r.randint(0,255) for _ in range(c['iw']*c['ih']*c['ci'])]
    if c.get('input_one'): xs=[1]*len(xs)
    mem[:len(xs)]=bytes(x&255 for x in xs)
    kvals=k*k*(1 if c['dw'] else c['ci'])
    ws=c.get('weights') or [r.randint(-127,127) for _ in range(((c['co']+15)//16)*kvals*16)]
    if c.get('weight_one'): ws=[1]*len(ws)
    mem[0x2000:0x2000+len(ws)]=bytes(w&255 for w in ws)
    biases=c['bias'] if c['bias'] is not None else [r.randint(-700,700) for _ in range(c['co'])]
    for co in range(c['co']):
        struct.pack_into('<i',mem,0x3000+4*co,biases[co])
        mult=c['mult'][co] if isinstance(c['mult'],list) else c['mult']
        shift=c['shift'][co] if isinstance(c['shift'],list) else c['shift']
        struct.pack_into('<ii',mem,0x4000+8*co,mult,shift)
    expected=bytearray(mem); result=[]
    if not c['expected_error']:
        for co in range(c['co']):
            for oy in range(oh):
                for ox in range(ow):
                    acc=biases[co]
                    for ci in range(1 if c['dw'] else c['ci']):
                        for ky in range(k):
                            for kx in range(k):
                                ix=ox*s+kx-p; iy=oy*s+ky-p
                                if 0<=ix<c['iw'] and 0<=iy<c['ih']:
                                    channel=co if c['dw'] else ci
                                    x=xs[(channel*c['ih']+iy)*c['iw']+ix]
                                    w=ws[((co//16)*kvals+(ci*k+ky)*k+kx)*16+co%16]
                                    acc+=x*w
                                    assert -(1<<31)<=acc<(1<<31)
                    mult=c['mult'][co] if isinstance(c['mult'],list) else c['mult']
                    shift=c['shift'][co] if isinstance(c['shift'],list) else c['shift']
                    y=rounded(acc*mult,shift)
                    lo,hi=(0,255) if c['fmt']==1 else (-127,127) if c['fmt']==2 else (-32767,32767)
                    result.append(max(lo,min(hi,y)))
        for i,y in enumerate(result):
            if c['fmt']==3: struct.pack_into('<h',expected,0x6000+2*i,y)
            else: expected[0x6000+i]=y&255
    cfg+=[len(result),int(c['expected_error']==1)]+[0]*11
    assert len(cfg)==32
    return cfg,mem,expected,result


def frozen_conv0(npu):
    manifest=json.loads((npu/'yunet/baseline/program_package_manifest_v0_1.json').read_text(encoding='utf-8'))
    raw=(npu/'build/integration_audit/20261020/program.bin').read_bytes()
    image=(npu/'build/integration_audit/20261020/parameter_image.bin').read_bytes()
    assert hashlib.sha256(raw).hexdigest()==manifest['program_sha256']
    assert hashlib.sha256(image).hexdigest()==manifest['parameter_image_sha256']
    h=struct.unpack_from('<32I',raw);op=struct.unpack_from('<32I',raw,h[12])
    assert op[:4]==(0,1,1,1) and op[11:19]==(3,3,2,2,1,1,1,1)
    params=[struct.unpack_from('<8I',raw,h[10]+pid*32) for pid in op[7:10]]
    def content(p):
        start=p[2]-manifest['parameter_image_model_offset'];return image[start:start+p[3]]
    weights=list(struct.unpack('<'+str(params[0][3])+'b',content(params[0])))
    biases=list(struct.unpack('<16i',content(params[1])))
    pairs=struct.unpack('<32i',content(params[2]));assert all(0<=v<=63 for v in pairs[1::2])
    return dict(iw=7,ih=5,ci=3,co=16,kernel=3,stride=2,pad=1,weights=weights,bias=biases,
                mult=list(pairs[::2]),shift=list(pairs[1::2]))


def emit(folder):
    assert [rounded(x,1) for x in (1,3,5,-1,-3,-5)]==[0,2,2,0,-2,-2]
    cases=[('dense_u8',{}),('dense_s8',dict(signed=1,fmt=2)),
           ('dense_i16',dict(signed=1,fmt=3,mult=7,shift=1)),
           ('dw_u8',dict(ci=5,co=5,dw=1)),('dw_s8',dict(ci=5,co=5,dw=1,signed=1,fmt=2)),
           ('tail17',dict(kernel=1,pad=0,co=17)),('stride2',dict(iw=7,ih=5,stride=2)),
           ('no_pad',dict(iw=7,ih=5,pad=0)),
           ('positive_tie',dict(iw=1,ih=1,ci=1,co=5,kernel=1,pad=0,bias=[0,2,4,6,8],mult=1,shift=1,input_one=1,weight_one=1)),
           ('negative_tie',dict(iw=1,ih=1,ci=1,co=5,kernel=1,pad=0,bias=[-2,-4,-6,-8,-10],mult=1,shift=1,input_one=1,weight_one=1,fmt=2)),
           ('shift0',dict(kernel=1,pad=0,mult=-13,shift=0,fmt=3)),
           ('shift63',dict(kernel=1,pad=0,mult=-2147483648,shift=63,fmt=2)),
           ('bad_shift',dict(shift=64,expected_error=3)),
           ('overflow',dict(iw=1,ih=1,ci=1,co=1,kernel=1,pad=0,bias=[2147483647],input_one=1,weight_one=1,expected_error=2)),
           ('bad_shape',dict(ow=1,expected_error=1)),('alias',dict(alias=1,expected_error=1)),
           ('dma_error',dict(inject_error=2,expected_error=4))]
    npu=Path(__file__).resolve().parents[2].parent/'npu_zgtc'
    if (npu/'build/integration_audit/20261020/program.bin').is_file():
        cases.append(('frozen_conv0',frozen_conv0(npu)))
    manifest=[]
    for i,(name,kw) in enumerate(cases):
        target=folder/name; target.mkdir(parents=True)
        for version in range(2):
            cfg,mem,expected,ys=make_case(901+i+version*100,**kw)
            suffix='' if version==0 else '_next'
            for label,data in (('memory',mem),('expected',expected)):
                (target/(label+suffix+'.hex')).write_text(''.join('%02x\n'%x for x in data),encoding='ascii')
            (target/('config'+suffix+'.hex')).write_text(''.join('%08x\n'%x for x in cfg),encoding='ascii')
        item={'name':name,'config':cfg,'output_values':len(ys),'expected_error':kw.get('expected_error',0)}
        if name=='frozen_conv0':
            item['frozen_source_sha256']={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in
                (npu/'yunet/baseline/program_package_manifest_v0_1.json',npu/'build/integration_audit/20261020/program.bin',npu/'build/integration_audit/20261020/parameter_image.bin')}
            item['scope']='real Conv_0 parameters, cropped 7x5 input; not complete 320x320 layer'
        manifest.append(item)
    (folder/'cases.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    return manifest

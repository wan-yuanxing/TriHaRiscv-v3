"""Generate the versioned capture-endpoint RTL/C ABI from one JSON definition."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[2]
IDENTIFIER=re.compile(r'[A-Z][A-Z0-9_]*\Z')
RW_NAMES={'CONTROL','IRQ_MASK','REQUEST_SLOT','REQUEST_FRAME_ID','REQUEST_VERSION'}
REQUIRED_NAMES=set('''VERSION CAPABILITIES CONTROL STATUS IRQ_MASK IRQ_PENDING ERROR_CODE
CAPTURE_REQUEST CAPTURE_STATUS ACCEPTED_FRAME_ID COMPLETED_FRAME_ID REQUEST_SLOT
REQUEST_FRAME_ID REQUEST_VERSION REQUEST_RAW_BASE REQUEST_PREVIEW_BASE REQUEST_INPUT_BASE
RAW_STRIDE PREVIEW_STRIDE INPUT_STRIDE FRAME_WIDTH FRAME_HEIGHT INPUT_WIDTH INPUT_HEIGHT
ACCEPTED_SLOT ACCEPTED_FRAME_ID_RECORD ACCEPTED_VERSION ACCEPTED_RAW_BASE
ACCEPTED_PREVIEW_BASE ACCEPTED_INPUT_BASE COMPLETED_SLOT COMPLETED_FRAME_ID_RECORD
COMPLETED_VERSION COMPLETED_RESULT COMPLETED_RAW_BASE COMPLETED_PREVIEW_BASE
COMPLETED_INPUT_BASE COMPLETED_RAW_PIXELS COMPLETED_PREVIEW_PIXELS COMPLETED_INPUT_PIXELS
COMPLETED_RAW_BYTES COMPLETED_PREVIEW_BYTES COMPLETED_INPUT_BYTES COMPLETED_RAW_CRC
COMPLETED_PREVIEW_CRC COMPLETED_FIFO_PEAK'''.split())
SUPPORTED_OFFSETS=set(range(0,0x1c,4))|{0x20,0x24,0x28,0x2c}|set(range(0x100,0x134,4))|set(range(0x140,0x158,4))|set(range(0x180,0x1c0,4))
# Compatibility lock for the published v1 ABI; values still come only from JSON.
# An intentional ABI change requires a new version and a reviewed new lock.
ABI_FINGERPRINT='391435f7b632e9907aebb59b98d6210be2157c948643cb560c8f7906265ed88c'


def require(condition,message):
    if not condition:raise ValueError(message)


def integer(value,low,high):
    return type(value) is int and low<=value<=high


def unique_object(pairs):
    value={}
    for key,item in pairs:
        require(key not in value,'duplicate JSON key: '+key)
        value[key]=item
    return value


def validate(config):
    require(type(config) is dict,'register profile must be an object')
    require(set(config)=={'schema_version','abi_version','base','region_bytes','capabilities','registers'},'unexpected profile keys')
    for key,expected in {'schema_version':1,'abi_version':0x10000,'base':0x20010000,'region_bytes':65536}.items():
        require(type(config[key]) is int and config[key]==expected,'invalid fixed '+key)
    caps=config['capabilities']
    require(type(caps) is dict and set(caps)=={'CAPTURE','HELD_EVENTS','IRQ'},'invalid capability names')
    require(all(type(v) is int for v in caps.values()) and caps=={'CAPTURE':0,'HELD_EVENTS':1,'IRQ':2},'invalid capability bits')
    registers=config['registers']
    require(type(registers) is list and len(registers)==46,'invalid register table')
    names=set();offsets=set()
    for reg in registers:
        require(type(reg) is dict,'register must be an object')
        require({'name','offset','access','fields'}<=set(reg)<= {'name','offset','access','fields','reset'},'invalid register keys')
        name=reg['name'];offset=reg['offset'];access=reg['access']
        require(type(name) is str and bool(IDENTIFIER.fullmatch(name)) and name not in names,'invalid/duplicate register name')
        require(integer(offset,0,65535) and offset%4==0 and offset in SUPPORTED_OFFSETS and offset not in offsets,'invalid/duplicate/reserved register offset')
        expected_access='RW' if name in RW_NAMES else 'RW1C' if name=='IRQ_PENDING' else 'WO' if name=='CAPTURE_REQUEST' else 'RO'
        require(type(access) is str and access==expected_access,'invalid register access')
        fields=reg['fields'];require(type(fields) is list,'fields must be an array')
        used=0;field_names=set()
        for field in fields:
            require(type(field) is dict and set(field)=={'name','lsb','width'},'invalid field keys')
            n=field['name'];lsb=field['lsb'];width=field['width']
            require(type(n) is str and bool(IDENTIFIER.fullmatch(n)) and n not in field_names,'invalid/duplicate field name')
            require(integer(lsb,0,31) and integer(width,1,32) and lsb+width<=32,'invalid field range')
            mask=((1<<width)-1)<<lsb
            require(not used&mask,'overlapping register fields')
            used|=mask;field_names.add(n)
        if access=='RO':require('reset' not in reg,'RO reset comes from live/held hardware state')
        else:
            reset=reg.get('reset')
            require(integer(reset,0,0xffffffff) and (not fields or reset&~used==0),'invalid writable reset')
        names.add(name);offsets.add(offset)
    require(names==REQUIRED_NAMES and offsets==SUPPORTED_OFFSETS,'incomplete capture ABI')
    canonical={**config,'registers':[{**reg,'fields':sorted(reg['fields'],key=lambda f:f['lsb'])}
                                     for reg in sorted(registers,key=lambda r:r['offset'])]}
    fingerprint=hashlib.sha256(json.dumps(canonical,sort_keys=True,separators=(',',':')).encode('utf-8')).hexdigest()
    require(fingerprint==ABI_FINGERPRINT,'register semantics changed without a new reviewed ABI version')


def generated_files(config,digest):
    validate(config)
    require(type(digest) is str and bool(re.fullmatch(r'[0-9a-f]{64}',digest)),'invalid source digest')
    values={'VIDEO_MMIO_BASE':config['base'],'VIDEO_MMIO_BYTES':config['region_bytes'],
            'VIDEO_ABI_VERSION':config['abi_version'],
            'VIDEO_CAPABILITIES':sum(1<<v for v in config['capabilities'].values())}
    for name,bit in sorted(config['capabilities'].items()):values['VIDEO_CAP_'+name]=1<<bit
    for reg in sorted(config['registers'],key=lambda r:r['offset']):
        name=reg['name'];values['VIDEO_REG_'+name]=reg['offset']
        if 'reset' in reg:values['VIDEO_REG_'+name+'_RESET']=reg['reset']
        for field in sorted(reg['fields'],key=lambda f:f['lsb']):
            prefix='VIDEO_'+name+'_'+field['name']
            values[prefix+'_MASK']=((1<<field['width'])-1)<<field['lsb']
            values[prefix+'_SHIFT']=field['lsb']
    note='// Generated by scripts/video/gen_regs.py; config SHA256 '+digest+'\n'
    rtl=note+'`ifndef TRIHA_VIDEO_REGS_VH\n`define TRIHA_VIDEO_REGS_VH\n'
    c=note+'#ifndef TRIHA_VIDEO_REGS_H\n#define TRIHA_VIDEO_REGS_H\n'
    for name,value in values.items():
        rtl+=f"`define {name} 32'h{value:08x}\n"
        c+=f'#define {name} 0x{value:08x}u\n'
    return {'rtl/video/include/video_regs.vh':rtl+'`endif\n',
            'sw/include/video_regs.h':c+'#endif\n'}


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=ROOT)
    parser.add_argument('--config',type=Path,default=ROOT/'config/video_regs.json')
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args(argv)
    try:
        raw=args.config.read_bytes();config=json.loads(raw,object_pairs_hook=unique_object);validate(config)
        files=generated_files(config,hashlib.sha256(raw).hexdigest());stale=[]
        for name,content in files.items():
            target=args.root/name;data=content.encode('utf-8')
            if args.check:
                if not target.is_file() or target.read_bytes()!=data:stale.append(name)
            else:
                target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
        require(not stale,'missing/stale generated register files: '+', '.join(stale))
    except (OSError,ValueError,TypeError,KeyError) as error:
        print('VIDEO_REGS_FAIL:',error,file=sys.stderr);return 1
    print('VIDEO_REGS_PASS'+(' check' if args.check else ' generate'));return 0


if __name__=='__main__':raise SystemExit(main())

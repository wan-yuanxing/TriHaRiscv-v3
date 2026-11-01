"""Audit B03 assets; optionally upload through the board THB1 UART boot port."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import struct
import sys
import time
import zlib

ROOT=Path(__file__).resolve().parents[2]


def make_packet(segment,offset,payload):
    if not 0<=segment<6 or not 0<=offset<2**32 or offset%256 or len(payload)!=256:
        raise ValueError('THB1 requires segment 0..5, aligned offset and 256 payload bytes')
    return b'THB1'+struct.pack('<III',segment,offset,zlib.crc32(payload))+payload


def parse_ack(data):
    if len(data)!=12 or data[:4]!=b'THA1' or data[6:8]!=b'\0\0' or data[5]>6:
        raise ValueError('malformed THA1 reply')
    return data[4],data[5],struct.unpack_from('<I',data,8)[0]


def read_ack(port,deadline):
    buffer=bytearray()
    while time.monotonic()<deadline:
        buffer.extend(port.read(1))
        if len(buffer)>=4 and buffer[:4]!=b'THA1':del buffer[0]
        if len(buffer)==12:return parse_ack(buffer)
    raise TimeoutError('THA1 reply timeout')


def upload_segments(port,segments,timeout=2,retries=2,progress=None):
    if len(segments)!=6 or any(not data or len(data)%256 for data in segments):
        raise ValueError('six complete 256-byte-aligned segments required')
    result=dict(bytes=0,packets=0,retries=0,ack_segment=0,ack_offset=0)
    previous=(0,0)
    for segment,data in enumerate(segments):
        for offset in range(0,len(data),256):
            packet=make_packet(segment,offset,data[offset:offset+256])
            expected=(segment+1,0) if offset+256==len(data) else (segment,offset+256)
            for attempt in range(retries+1):
                if port.write(packet)!=len(packet):raise RuntimeError('partial UART write')
                port.flush();deadline=time.monotonic()+timeout
                try:
                    while True:
                        status,next_segment,next_offset=read_ack(port,deadline)
                        cursor=(next_segment,next_offset)
                        if status==0 and cursor==previous:continue
                        if status in (1,6):raise TimeoutError('retryable packet CRC/framing rejection')
                        if status!=0:raise RuntimeError(f'loader rejected packet: status={status}, cursor={cursor}')
                        if cursor!=expected:raise RuntimeError(f'loader cursor {cursor}, expected {expected}')
                        break
                    break
                except TimeoutError:
                    if attempt==retries:raise
                    result['retries']+=1
            previous=expected
            result.update(bytes=result['bytes']+256,packets=result['packets']+1,
                          ack_segment=expected[0],ack_offset=expected[1])
        if progress:progress(segment+1,result['bytes'])
    return result


def audit_assets(asset_root):
    sys.path.insert(0,str(ROOT/'scripts/npu'))
    from run_b03_frame import DEFAULT_MANIFEST,checked_asset
    from audit_b03_assets import load_manifest
    manifest=load_manifest(DEFAULT_MANIFEST)
    cfg=json.loads((ROOT/'config/soc_memory.json').read_text(encoding='utf-8'))['b03']
    names=['program.bin','parameter_image.bin','post_table.bin']+['heads_init.bin']*3
    sizes=[cfg['program_bytes'],cfg['parameter_bytes'],cfg['post_table_bytes']]+[cfg['heads_bytes']]*3
    crcs=[cfg['program_crc32'],cfg['parameter_crc32'],cfg['post_table_crc32']]+[0xed5ca9c5]*3
    segments=[];evidence=[]
    for name,size,crc in zip(names,sizes,crcs):
        data=checked_asset(asset_root,name,manifest['files_sha256'])
        if len(data)!=size or len(data)%256 or zlib.crc32(data)!=crc:
            raise ValueError('asset differs from admitted loader layout: '+name)
        segments.append(data)
        evidence.append(dict(name=name,bytes=size,sha256=hashlib.sha256(data).hexdigest(),crc32=f'{crc:08x}'))
    return segments,evidence


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets',type=Path,default=ROOT/'build/npu/b03_assets_20261030/assets')
    parser.add_argument('--port',help='Explicit Windows COM port; omission audits assets without device access')
    parser.add_argument('--baud',type=int,default=115200)
    parser.add_argument('--timeout',type=float,default=2)
    parser.add_argument('--retries',type=int,default=2)
    args=parser.parse_args()
    if args.baud<=0 or args.timeout<=0 or args.retries<0:parser.error('invalid serial settings')
    out=ROOT/'build/soc'/('model_upload-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    out.mkdir(parents=True);result=dict(status='RUNNING',port=args.port,baud=args.baud,board_verified=False)
    try:
        segments,evidence=audit_assets(args.assets);result['segments']=evidence
        result['serial_lower_bound_seconds']=sum(len(x)//256*284*10 for x in segments)/args.baud
        if args.port:
            import serial
            # Hardware should be reset and DDR calibrated before opening. No
            # reset/DTR toggle, JTAG action or flash programming is performed.
            with serial.Serial(args.port,args.baud,timeout=.05,write_timeout=5) as port:
                result['transfer']=upload_segments(port,segments,args.timeout,args.retries,
                    lambda count,size:print(f'MODEL_UPLOAD segments={count}/6 bytes={size}',flush=True))
            result.update(status='PASS_UART_LOADER_ACK',model_seal_acknowledged=True)
        else:result.update(status='PASS_ASSET_AUDIT')
    except Exception as exc:result.update(status='FAIL',error=str(exc))
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(result['status'],out,result.get('error',''),flush=True)
    return int(result['status']=='FAIL')


if __name__=='__main__':sys.exit(main())

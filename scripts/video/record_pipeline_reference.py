"""Independent captured RGB and frozen result/material fixtures, not DUT state."""
import json,sys,zlib
from common import ROOT,write_json,sha256
sys.path.insert(0,str(ROOT/'tb/video'))
import check_record_pixels as records

def channel(x,y,c,tag):
    return (37*x+19*y+83*c+(x*y>>3)+tag*43+tag*x)&255

def fixtures(directory,height):
    records.generate(800,height,directory)
    rows=json.loads((directory/'reference.json').read_text())['records']
    row=rows[1];row[16]=0x82600ff0
    (directory/'record.bin').write_bytes(b''.join(v.to_bytes(4,'little') for v in row))
    asset=bytes(v for y in range(256) for x in range(256) for v in records.rgba(x,y,7))
    (directory/'asset.rgba').write_bytes(asset)
    (directory/'asset_bytes.hex').write_text(''.join(f'{v:02x}\n' for v in asset),encoding='ascii')
    (directory/'crc.hex').write_text(f'{zlib.crc32(asset):08x}\n',encoding='ascii')
    original=records.math.texture;records.math.texture=lambda x,y:records.rgba(x,y,7)
    counts=dict(box=0,point=0,avatar=0)
    try:
        with (directory/'expected.hex').open('w',encoding='ascii') as out:
            for mode in range(4):
                cfg=records.decode_record(row,min(mode,2));tag=2 if mode==3 else 1
                for y in range(height):
                    for x in range(800):
                        rgb=(channel(x,y,0,tag)<<16)|(channel(x,y,1,tag)<<8)|channel(x,y,2,tag)
                        if mode in (0,3):value,flags=rgb,(0,0,0)
                        else:value,flags,_=records.math.reference(cfg,(0,0,1,x,y,rgb,1,0,0,0,0))
                        out.write(f'{value|(sum(v<<i for i,v in enumerate(flags))<<24):07x}\n')
                        for k,hit in zip(('box','point','avatar'),flags):counts[k]+=hit
    finally:records.math.texture=original
    write_json(directory/'fixture.json',dict(width=800,height=height,reference_counts=counts,record_sha256=sha256(directory/'record.bin'),asset_sha256=sha256(directory/'asset.rgba'),asset_crc=zlib.crc32(asset)))

"""Shared-read renderer regression with independent record and byte fixtures."""
import json,re,sys,zlib
from common import ROOT,fresh_run,input_hashes,run_logged,tool,sha256,write_json
sys.path.insert(0,str(ROOT/'tb/video'))
import check_record_pixels as records

def fixtures(directory,w,h):
    records.generate(w,h,directory)
    info=json.loads((directory/'reference.json').read_text());rows=info['records']
    for row in rows:row[16]=0x82600ff0
    (directory/'records.hex').write_text(''.join(f'{sum(v<<(32*i) for i,v in enumerate(row)):01280x}\n' for row in rows),encoding='ascii')
    data=bytes(v for y in range(256) for x in range(256) for v in records.rgba(x,y,7))
    (directory/'asset.rgba').write_bytes(data)
    (directory/'asset_bytes.hex').write_text(''.join(f'{v:02x}\n' for v in data),encoding='ascii')
    (directory/'crc.hex').write_text(f'{zlib.crc32(data):08x}\n',encoding='ascii')
    raw=bytes(((i*173+(i>>4)*19)^0xa5)&255 for i in range(4096))
    (directory/'raw_bytes.hex').write_text(''.join(f'{v:02x}\n' for v in raw),encoding='ascii')
    (directory/'raw_words.hex').write_text(''.join(f'{int.from_bytes(raw[i:i+16],"little"):032x}\n' for i in range(0,4096,16)),encoding='ascii')
    saved=records.math.texture;records.math.texture=lambda x,y:records.rgba(x,y,7)
    counts=dict(box=0,point=0,avatar=0)
    try:
        with (directory/'expected.hex').open('w',encoding='ascii') as out:
            for mode in range(3):
                cfg=records.decode_record(rows[mode+1],mode)
                for y in range(h):
                    for x in range(w):
                        rgb=(((x*7+31)&255)<<16)|(((y*11+17)&255)<<8)|((x*3+y*13)&255)
                        value,flags,_=records.math.reference(cfg,(0,0,1,x,y,rgb,1,0,0,0,0))
                        out.write(f'{value|(sum(v<<i for i,v in enumerate(flags))<<24):07x}\n')
                        for k,hit in zip(('box','point','avatar'),flags):counts[k]+=hit
    finally:records.math.texture=saved
    write_json(directory/'fixture.json',dict(w=w,h=h,asset_bytes=len(data),asset_crc=zlib.crc32(data),asset_sha256=sha256(directory/'asset.rgba'),reference_counts=counts))

def main():
    work=fresh_run('record_renderer');latest=ROOT/'build/video/latest_record_renderer_component.json'
    result=dict(status='running',directory=work.relative_to(ROOT).as_posix());write_json(latest,result)
    try:
        mp=ROOT/'fpga/pg2l100h/project/video_record_renderer.json';m=json.loads(mp.read_text())
        paths=[ROOT/p for p in m['sources']+m['tests']+m['constraints']]+[mp,ROOT/'scripts/video/test_record_renderer.py',ROOT/'scripts/video/common.py',ROOT/'tb/video/check_record_pixels.py',ROOT/'tb/video/overlay_reference.py',ROOT/'rtl/video/include/video_display.vh',ROOT/'rtl/video/include/video_cfg.vh']
        result.update(inputs=input_hashes(paths),tools={str(tool(t)):sha256(tool(t)) for t in ('iverilog','vvp')},arbiter={},renderer={})
        for t in ('iverilog','vvp'):run_logged([tool(t),'-V'],work/(t+'_version.log'))
        files=[ROOT/p for p in m['sources']+m['tests']]
        for case in [0,1,2,3,4,5,6,7,8,9,10,11,13,14]:
            cw=work/f'arbiter_{case}';cw.mkdir();binary=cw/'sim.vvp'
            run_logged([tool('iverilog'),'-g2012','-Wall','-I',ROOT/'rtl/video/include','-s','tb_video_read_arbiter',f'-Ptb_video_read_arbiter.CASE_ID={case}','-o',binary,*files],cw/'compile.log')
            log=run_logged([tool('vvp'),binary],cw/'simulation.log');found=re.findall('READ_ARBITER_PASS (.*)',log)
            if len(found)!=1:raise RuntimeError('Missing arbiter pass')
            result['arbiter'][str(case)]={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',found[0])}
        for name,w,h,case,half in [('probe',80,64,0,12.5),('ratio',80,64,0,17),('wait',80,64,3,12.5),('crc',80,64,4,12.5),('reset',80,64,5,12.5),('full',800,600,0,12.5)]:
            cw=work/name;print('RENDERER_CASE',name,flush=True);fixtures(cw,w,h);binary=cw/'sim.vvp'
            run_logged([tool('iverilog'),'-g2012','-Wall','-I',ROOT/'rtl/video/include','-s','tb_video_record_renderer',f'-Ptb_video_record_renderer.W={w}',f'-Ptb_video_record_renderer.H={h}',f'-Ptb_video_record_renderer.CASE_ID={case}',f'-Ptb_video_record_renderer.PIXEL_HALF={half}','-o',binary,*files],cw/'compile.log')
            log=run_logged([tool('vvp'),binary,'+DIR='+cw.as_posix()],cw/'simulation.log',timeout=1800)
            found=re.findall('RECORD_RENDERER_PASS (.*)',log)
            if len(found)!=1:raise RuntimeError('Missing renderer pass '+name)
            result['renderer'][name]={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',found[0])}
        if result['inputs']!=input_hashes(paths) or any(sha256(p)!=h for p,h in result['tools'].items()):raise RuntimeError('Inputs/tools changed')
        result.update(status='pass',actual_raw_scanner_identity_integrated=False,physical_board=False,artifacts=input_hashes(p for p in work.rglob('*') if p.is_file()))
    except Exception as error:result.update(status='fail',error=str(error));print(str(error),file=sys.stderr)
    write_json(work/'result.json',result);write_json(latest,result);print('RECORD_RENDERER_'+result['status'].upper(),work)
    return 0 if result['status']=='pass' else 1

if __name__=='__main__':raise SystemExit(main())

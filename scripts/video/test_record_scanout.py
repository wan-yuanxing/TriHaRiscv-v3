"""Actual scanner/record rendering and joint Video reference retirement."""
import json,re,sys
from common import ROOT,fresh_run,input_hashes,run_logged,tool,sha256,write_json
from test_record_renderer import fixtures

def main():
    work=fresh_run('record_scanout');latest=ROOT/'build/video/latest_record_scanout_component.json'
    result=dict(status='running',directory=work.relative_to(ROOT).as_posix());write_json(latest,result)
    try:
        mp=ROOT/'fpga/pg2l100h/project/video_record_scanout.json';m=json.loads(mp.read_text())
        paths=[ROOT/p for p in m['sources']+m['tests']+m['constraints']]+[mp,ROOT/'scripts/video/test_record_scanout.py',ROOT/'scripts/video/test_record_renderer.py',ROOT/'scripts/video/common.py',ROOT/'tb/video/check_record_pixels.py',ROOT/'tb/video/overlay_reference.py',ROOT/'rtl/video/include/avatar_span_table.vh',ROOT/'rtl/video/include/avatar_span_identity.vh',ROOT/'rtl/video/include/video_display.vh',ROOT/'rtl/video/include/video_cfg.vh']
        result.update(inputs=input_hashes(paths),tools={str(tool(t)):sha256(tool(t)) for t in ('iverilog','vvp')},link={},scanout={})
        for t in ('iverilog','vvp'):run_logged([tool(t),'-V'],work/(t+'_version.log'))
        files=[ROOT/p for p in m['sources']+m['tests']]
        for case in range(7):
            cw=work/f'link_{case}';cw.mkdir();binary=cw/'sim.vvp'
            run_logged([tool('iverilog'),'-g2012','-Wall','-I',ROOT/'rtl/video/include','-s','tb_display_record_link',f'-Ptb_display_record_link.CASE_ID={case}','-o',binary,*files],cw/'compile.log')
            log=run_logged([tool('vvp'),binary],cw/'simulation.log');found=re.findall('DISPLAY_RECORD_LINK_PASS (.*)',log)
            if len(found)!=1:raise RuntimeError('Missing link pass')
            result['link'][str(case)]={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',found[0])}
        cases=[('probe',80,64,12.5),('ratio',80,64,17),('full',800,600,12.5)]
        for name,w,h,half in cases:
            cw=work/name;print('SCANOUT_CASE',name,flush=True);fixtures(cw,w,h);binary=cw/'sim.vvp'
            run_logged([tool('iverilog'),'-g2012','-Wall','-I',ROOT/'rtl/video/include','-s','tb_video_record_scanout',f'-Ptb_video_record_scanout.W={w}',f'-Ptb_video_record_scanout.H={h}',f'-Ptb_video_record_scanout.PIXEL_HALF={half}','-o',binary,*files],cw/'compile.log')
            log=run_logged([tool('vvp'),binary,'+DIR='+cw.as_posix()],cw/'simulation.log',timeout=2400)
            found=re.findall('VIDEO_RECORD_SCANOUT_PASS (.*)',log)
            if len(found)!=1:raise RuntimeError('Missing scanout pass '+name)
            result['scanout'][name]={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',found[0])}
        if result['inputs']!=input_hashes(paths) or any(sha256(p)!=h for p,h in result['tools'].items()):raise RuntimeError('Inputs/tools changed')
        result.update(status='pass',actual_raw_scanner_identity_integrated=True,joint_scanner_pixel_retirement=True,physical_board=False,artifacts=input_hashes(p for p in work.rglob('*') if p.is_file()))
    except Exception as error:result.update(status='fail',error=str(error));print(str(error),file=sys.stderr)
    write_json(work/'result.json',result);write_json(latest,result);print('RECORD_SCANOUT_'+result['status'].upper(),work)
    return 0 if result['status']=='pass' else 1

if __name__=='__main__':raise SystemExit(main())

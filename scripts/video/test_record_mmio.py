"""Frozen display ABI with actual RAW/material consumers and opt-in health."""
import json,re,sys
from common import ROOT,fresh_run,input_hashes,run_logged,tool,sha256,write_json
from test_record_renderer import fixtures

def main():
    work=fresh_run('record_mmio');latest=ROOT/'build/video/latest_record_mmio_component.json'
    result=dict(status='running',directory=work.relative_to(ROOT).as_posix());write_json(latest,result)
    try:
        mp=ROOT/'fpga/pg2l100h/project/video_display_record.json';m=json.loads(mp.read_text())
        paths=[ROOT/p for p in m['sources']+m['tests']+m['constraints']]+[mp,ROOT/'scripts/video/test_record_mmio.py',ROOT/'scripts/video/test_record_renderer.py',ROOT/'scripts/video/common.py',ROOT/'tb/video/check_record_pixels.py',ROOT/'tb/video/overlay_reference.py',ROOT/'rtl/video/include/avatar_span_table.vh',ROOT/'rtl/video/include/avatar_span_identity.vh',ROOT/'rtl/video/include/video_display.vh',ROOT/'rtl/video/include/video_cfg.vh']
        result.update(inputs=input_hashes(paths),tools={str(tool(t)):sha256(tool(t)) for t in ('iverilog','vvp')},health={},display={})
        for t in ('iverilog','vvp'):run_logged([tool(t),'-V'],work/(t+'_version.log'))
        files=[ROOT/p for p in m['sources']+m['tests']]
        for case in range(6):
            cw=work/f'health_{case}';cw.mkdir();binary=cw/'sim.vvp'
            run_logged([tool('iverilog'),'-g2012','-Wall','-I',ROOT/'rtl/video/include','-s','tb_video_display_health',f'-Ptb_video_display_health.CASE_ID={case}','-o',binary,*files],cw/'compile.log')
            log=run_logged([tool('vvp'),binary],cw/'simulation.log');found=re.findall('VIDEO_DISPLAY_HEALTH_PASS (.*)',log)
            if len(found)!=1:raise RuntimeError('Missing health pass')
            result['health'][str(case)]={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',found[0])}
        for name,case,half in [('normal',0,12.5),('ratio',0,17),('asset_wait',1,12.5)]:
            cw=work/name;print('RECORD_MMIO_CASE',name,flush=True);fixtures(cw,80,64);binary=cw/'sim.vvp'
            run_logged([tool('iverilog'),'-g2012','-Wall','-I',ROOT/'rtl/video/include','-s','tb_video_display_record',f'-Ptb_video_display_record.CASE_ID={case}',f'-Ptb_video_display_record.PIXEL_HALF={half}','-o',binary,*files],cw/'compile.log')
            log=run_logged([tool('vvp'),binary,'+DIR='+cw.as_posix()],cw/'simulation.log',timeout=600)
            found=re.findall('VIDEO_DISPLAY_RECORD_PASS (.*)',log)
            if len(found)!=1:raise RuntimeError('Missing display pass '+name)
            result['display'][name]={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',found[0])}
        if result['inputs']!=input_hashes(paths) or any(sha256(p)!=h for p,h in result['tools'].items()):raise RuntimeError('Inputs/tools changed')
        result.update(status='pass',physical_board=False,artifacts=input_hashes(p for p in work.rglob('*') if p.is_file()))
    except Exception as error:result.update(status='fail',error=str(error));print(str(error),file=sys.stderr)
    write_json(work/'result.json',result);write_json(latest,result);print('RECORD_MMIO_'+result['status'].upper(),work)
    return 0 if result['status']=='pass' else 1

if __name__=='__main__':raise SystemExit(main())

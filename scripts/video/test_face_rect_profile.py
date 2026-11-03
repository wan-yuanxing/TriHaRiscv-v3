"""Check generic and face-board record guards, including all disabled point lanes."""
import json,sys
from common import ROOT,fresh_run,input_hashes,run_logged,tool,sha256,write_json

def main():
    work=fresh_run('face_rect_profile')
    names=['rtl/video/display_record_guard.sv','tb/video/tb_display_record_guard.sv',
           'rtl/video/include/video_display.vh','rtl/video/include/video_cfg.vh',
           'scripts/video/test_face_rect_profile.py','scripts/video/common.py']
    paths=[ROOT/n for n in names]
    result=dict(status='running',directory=work.relative_to(ROOT).as_posix(),
                inputs=input_hashes(paths),cases={},tools={str(tool(t)):sha256(tool(t)) for t in ('iverilog','vvp')})
    try:
        for enabled,expected in [(1,248),(0,249)]:
            stem='landmarks_'+str(enabled);binary=work/(stem+'.vvp')
            run_logged([tool('iverilog'),'-g2012','-Wall','-I',ROOT/'rtl/video/include',
                        '-s','tb_display_record_guard',f'-Ptb_display_record_guard.ENABLE_LANDMARKS={enabled}',
                        '-o',binary,paths[0],paths[1]],work/(stem+'_compile.log'))
            log=run_logged([tool('vvp'),binary],work/(stem+'.log'))
            if f'DISPLAY_RECORD_GUARD_PASS cases={expected}' not in log:
                raise ValueError('Guard coverage differs')
            result['cases'][stem]=expected
        if result['inputs']!=input_hashes(paths):raise ValueError('Input changed')
        result.update(status='pass',artifacts=input_hashes(p for p in work.iterdir() if p.is_file()))
    except Exception as error:result.update(status='fail',error=str(error));print(str(error),file=sys.stderr)
    write_json(work/'result.json',result)
    print('FACE_RECT_PROFILE',result['status'],work)
    return result['status']!='pass'

if __name__=='__main__':raise SystemExit(main())

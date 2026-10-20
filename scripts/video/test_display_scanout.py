"""Execute unchanged C pool/driver and generate wait-only real scanout replay."""
from pathlib import Path
import os,re,subprocess,sys
from common import ROOT,fresh_run,input_hashes,sha256,write_json

def main():
    work=fresh_run('display_scanout_native');latest=ROOT/'build/video/latest_display_scanout_native.json'
    result=dict(status='running',directory=work.relative_to(ROOT).as_posix());write_json(latest,result)
    try:
        cc=Path(os.environ.get('TRIHA_HOST_CC','D:/Xilinx/Vivado/2018.3/msys64/mingw64/bin/gcc.exe'))
        paths=[ROOT/p for p in ('scripts/video/test_display_scanout.py','scripts/video/common.py',
            'sw/drivers/video_frame_pool.c','sw/drivers/video_display.c','sw/include/video_frame_pool.h',
            'sw/include/video_display.h','sw/include/video_display_abi.h','sw/include/video_cfg.h','tb/video/test_display_scanout.c')]
        result['inputs']=input_hashes(paths);result['tools']={str(cc):sha256(cc)}
        env=dict(os.environ);env['PATH']=str(cc.parent)+os.pathsep+env['PATH']
        def run(args,name):
            p=subprocess.run(list(map(str,args)),cwd=ROOT,env=env,capture_output=True,timeout=90)
            (work/name).write_bytes(p.stdout+p.stderr)
            if p.returncode:raise RuntimeError(name+': '+(p.stdout+p.stderr).decode(errors='replace')[-3000:])
            return p.stdout.decode('ascii')
        run([cc,'--version'],'compiler.log');exe=work/'display_scanout.exe'
        run([cc,'-static','-std=c99','-O2','-Wall','-Wextra','-Werror','-I',ROOT/'sw/include',
            ROOT/'sw/drivers/video_frame_pool.c',ROOT/'sw/drivers/video_display.c',ROOT/'tb/video/test_display_scanout.c','-o',exe],'compile.log')
        output=run([exe],'test.log');match=re.fullmatch(r'DISPLAY_SCANOUT_C_PASS frames=6 modes=2 releases=5 checks=(\d+)\s*',output)
        if not match:raise RuntimeError('Missing C PASS')
        trace=run([exe,'--trace'],'trace.txt');rows=trace.splitlines()
        if rows[-1]!='END' or any(not re.fullmatch(r'(?:[RW] [0-9a-f]{8} [0-9a-f]{8}|A [13]|F|END)',r) for r in rows):
            raise RuntimeError('Non wait-only trace token')
        counts={k:sum(r==k or r.startswith(k+' ') for r in rows) for k in ('R','W','F','A')}
        assert counts['A']==8 and counts['W']>1300
        assert input_hashes(paths)==result['inputs'] and sha256(cc)==result['tools'][str(cc)]
        result.update(status='pass',checks=int(match[1]),trace_counts=counts,trace=(work/'trace.txt').relative_to(ROOT).as_posix(),
            native_C_executed=True,CPU_executed=False,event_model_reference_only=True,fabricated_RTL_feedback=False,
            artifacts=input_hashes(p for p in work.iterdir()))
    except Exception as error:
        result.update(status='fail',error=str(error));print(str(error),file=sys.stderr)
    write_json(work/'result.json',result);write_json(latest,result)
    print('DISPLAY_SCANOUT_NATIVE_'+result['status'].upper(),work);return 0 if result['status']=='pass' else 1
if __name__=='__main__':raise SystemExit(main())

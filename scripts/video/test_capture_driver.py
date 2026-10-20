"""Run the native ABI2 driver and emit actual MMIO reads/writes for RTL replay."""
from pathlib import Path
import os,subprocess,sys,re
from common import ROOT,fresh_run,input_hashes,sha256,write_json
def main():
    work=fresh_run('capture_driver');latest=ROOT/'build/video/latest_capture_driver.json'
    result=dict(status='running',directory=work.relative_to(ROOT).as_posix())
    write_json(latest,result)
    try:
        cc=Path(os.environ.get('TRIHA_HOST_CC','D:/Xilinx/Vivado/2018.3/msys64/mingw64/bin/gcc.exe'))
        rv=Path(os.environ.get('TRIHA_RISCV_GCC','D:/AI_Tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe'))
        inputs=[Path(__file__).resolve(),*[ROOT/p for p in ('sw/drivers/video_capture.c','sw/include/video_capture.h',
            'sw/include/video_capture_v2.h','sw/include/video_cfg.h','sw/include/video_frame_pool.h',
            'sw/include/video_display.h','sw/include/video_display_abi.h','tb/video/test_capture_driver.c')]]
        result['inputs']=input_hashes(inputs);result['tools']={str(p):sha256(p) for p in (cc,rv)}
        env=dict(os.environ);env['PATH']=str(cc.parent)+os.pathsep+str(cc.parents[2]/'usr/bin')+os.pathsep+env['PATH']
        def run(cmd,name):
            r=subprocess.run(list(map(str,cmd)),cwd=ROOT,env=env,capture_output=True,timeout=60)
            data=r.stdout+r.stderr;(work/name).write_bytes(data)
            if r.returncode:raise RuntimeError(name+': '+data.decode(errors='replace')[-3000:])
            return data
        exe=work/'driver.exe'
        run([cc,'--version'],'host_version.log');run([rv,'--version'],'rv_version.log')
        run([cc,'-static','-std=c99','-O2','-Wall','-Wextra','-Werror','-I',ROOT/'sw/include',
            ROOT/'sw/drivers/video_capture.c',ROOT/'tb/video/test_capture_driver.c','-o',exe],'compile.log')
        log=run([exe],'test.log');assert b'CAPTURE_DRIVER_PASS' in log
        trace=run([exe,'--trace'],'trace.txt');assert trace.splitlines()[-1]==b'END'
        run([rv,'-march=rv32i','-mabi=ilp32','-ffreestanding','-fno-builtin','-std=c99','-O2','-Wall','-Wextra','-Werror',
            '-I',ROOT/'sw/include','-c',ROOT/'sw/drivers/video_capture.c','-o',work/'driver_rv32i.o'],'rv_compile.log')
        assert input_hashes(inputs)==result['inputs']
        assert all(sha256(p)==h for p,h in result['tools'].items())
        counts={k:sum(s.startswith(k.encode()+b' ') if k!='F' else s==b'F' for s in trace.splitlines()) for k in ('R','W','E','F')}
        result.update(status='pass',native_driver_executed=True,rv32i_compiled_only=True,cpu_executed=False,
            trace_counts=counts,trace=(work/'trace.txt').relative_to(ROOT).as_posix(),
            artifacts=input_hashes(p for p in work.iterdir() if p.name!='result.json'))
    except Exception as error:result.update(status='fail',error=str(error));print(str(error),file=sys.stderr)
    write_json(work/'result.json',result);write_json(latest,result)
    print('CAPTURE_DRIVER_'+result['status'].upper(),work);return 0 if result['status']=='pass' else 1
if __name__=='__main__':raise SystemExit(main())

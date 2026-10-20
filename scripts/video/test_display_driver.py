"""Compile/run portable display driver tests and emit actual writes for RTL replay."""
from pathlib import Path
import os,subprocess,sys
from common import ROOT,fresh_run,input_hashes,sha256,write_json
def main():
    work=fresh_run('display_driver');latest=ROOT/'build/video/latest_display_driver.json'
    result=dict(status='running',directory=work.relative_to(ROOT).as_posix())
    write_json(latest,result)
    try:
        cc=Path(os.environ.get('TRIHA_HOST_CC','D:/Xilinx/Vivado/2018.3/msys64/mingw64/bin/gcc.exe'))
        rv=Path(os.environ.get('TRIHA_RISCV_GCC','D:/AI_Tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe'))
        inputs=[Path(__file__).resolve(),ROOT/'sw/drivers/video_display.c',ROOT/'sw/include/video_display.h',
          ROOT/'sw/include/video_display_abi.h',ROOT/'sw/include/video_cfg.h',ROOT/'tb/video/test_display_driver.c']
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
             ROOT/'sw/drivers/video_display.c',ROOT/'tb/video/test_display_driver.c','-o',exe],'compile.log')
        assert b'DISPLAY_DRIVER_PASS' in run([exe],'test.log')
        trace=run([exe,'--trace'],'writes.hex');assert len(trace.splitlines())==163
        run([rv,'-march=rv32i','-mabi=ilp32','-ffreestanding','-fno-builtin','-std=c99','-O2','-Wall','-Wextra','-Werror',
             '-I',ROOT/'sw/include','-c',ROOT/'sw/drivers/video_display.c','-o',work/'driver_rv32i.o'],'rv_compile.log')
        assert input_hashes(inputs)==result['inputs']
        assert all(sha256(p)==h for p,h in result['tools'].items())
        result.update(status='pass',native_driver_executed=True,rv32i_compiled_only=True,trace_writes=163,
            trace=(work/'writes.hex').relative_to(ROOT).as_posix(),artifacts=input_hashes([p for p in work.iterdir() if p.name!='result.json']))
    except Exception as error:result.update(status='fail',error=str(error));print(str(error),file=sys.stderr)
    write_json(work/'result.json',result);write_json(latest,result)
    print('DISPLAY_DRIVER_'+result['status'].upper(),work);return 0 if result['status']=='pass' else 1
if __name__=='__main__':raise SystemExit(main())

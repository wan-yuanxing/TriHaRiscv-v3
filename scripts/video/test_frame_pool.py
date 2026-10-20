"""Execute CPU frame ownership tests and emit actual driver I/O for RTL replay."""
from pathlib import Path
import os,re,subprocess,sys
from common import ROOT,fresh_run,input_hashes,sha256,write_json

def main():
    work=fresh_run('frame_pool_native')
    latest=ROOT/'build/video/latest_frame_pool_native.json'
    result=dict(status='running',directory=work.relative_to(ROOT).as_posix())
    write_json(latest,result)
    try:
        cc=Path(os.environ.get('TRIHA_HOST_CC','D:/Xilinx/Vivado/2018.3/msys64/mingw64/bin/gcc.exe'))
        rv=Path(os.environ.get('TRIHA_RISCV_GCC','D:/AI_Tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe'))
        nm=rv.with_name('riscv-none-elf-nm.exe')
        names=['scripts/video/test_frame_pool.py','scripts/video/common.py','sw/drivers/video_frame_pool.c',
            'sw/include/video_frame_pool.h','sw/drivers/video_display.c','sw/include/video_display.h',
            'sw/include/video_display_abi.h','sw/include/video_cfg.h','tb/video/test_video_frame_pool.c']
        paths=[ROOT/p for p in names]
        result['inputs']=input_hashes(paths)
        result['tools']={str(p):sha256(p) for p in (cc,rv,nm)}
        env=dict(os.environ)
        env['PATH']=str(cc.parent)+os.pathsep+str(cc.parents[2]/'usr/bin')+os.pathsep+env['PATH']
        def run(command,name):
            command=list(map(str,command))
            done=subprocess.run(command,cwd=ROOT,env=env,capture_output=True,timeout=90)
            (work/name).write_bytes(done.stdout+done.stderr)
            if done.returncode:raise RuntimeError(name+': '+(done.stdout+done.stderr).decode(errors='replace')[-3000:])
            return done.stdout
        run([cc,'--version'],'host_version.log')
        run([rv,'--version'],'rv_version.log')
        executable=work/'frame_pool.exe'
        run([cc,'-static','-std=c99','-O2','-Wall','-Wextra','-Werror','-I',ROOT/'sw/include',
            ROOT/'sw/drivers/video_frame_pool.c',ROOT/'sw/drivers/video_display.c',
            ROOT/'tb/video/test_video_frame_pool.c','-o',executable],'compile.log')
        output=run([executable],'native.log').decode('utf-8')
        match=re.fullmatch(r'FRAME_POOL_NATIVE_PASS cases=(\d+) checks=(\d+) callback_failures=(\d+) stress_frames=(\d+)\s*',output)
        if not match:raise RuntimeError('Missing precise native PASS')
        counts=dict(zip(('cases','checks','callback_failures','stress_frames'),map(int,match.groups())))
        assert counts['cases']==11 and counts['stress_frames']==1000 and counts['callback_failures']>170
        trace=run([executable,'--trace'],'trace.txt')
        records=trace.decode('ascii').splitlines()
        assert records[-1]=='END'
        trace_counts={kind:sum(line.startswith(kind+' ') or line==kind for line in records) for kind in ('R','W','Q','T','J','F')}
        assert trace_counts['Q']==6 and trace_counts['T']==2 and trace_counts['J']==1 and trace_counts['W']>1100
        obj=work/'frame_pool_rv32i.o'
        run([rv,'-march=rv32i','-mabi=ilp32','-ffreestanding','-fno-builtin','-std=c99','-O2','-Wall','-Wextra','-Werror',
            '-I',ROOT/'sw/include','-c',ROOT/'sw/drivers/video_frame_pool.c','-o',obj],'rv_compile.log')
        undefined=run([nm,'-u',obj],'rv_undefined.log').decode('ascii')
        assert not any(name in undefined for name in ('malloc','memset','memcpy','printf'))
        assert result['inputs']==input_hashes(paths)
        assert all(sha256(p)==h for p,h in result['tools'].items())
        result.update(status='pass',native_C_executed=True,RV32I_compiled_only=True,cpu_executed=False,
            physical_fence_verified=False,real_capture_or_NPU=False,counts=counts,trace_counts=trace_counts,
            trace=(work/'trace.txt').relative_to(ROOT).as_posix(),
            artifacts=input_hashes([p for p in work.iterdir() if p.name!='result.json']))
    except Exception as error:
        result.update(status='fail',error=str(error));print(str(error),file=sys.stderr)
    write_json(work/'result.json',result);write_json(latest,result)
    print('FRAME_POOL_NATIVE_'+result['status'].upper(),work)
    return 0 if result['status']=='pass' else 1

if __name__=='__main__':raise SystemExit(main())

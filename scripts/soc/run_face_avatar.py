"""Native host state-loop tests and freestanding RV32 application build."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ['sw/apps/face_avatar/face_avatar.c', 'sw/drivers/video_frame_pool.c',
           'sw/drivers/video_capture.c', 'sw/drivers/video_display.c', 'sw/drivers/npu_frame.c']
HEADERS = ['face_avatar.h','avatar_preset.h','video_frame_pool.h','video_capture.h','video_capture_v2.h',
           'video_display.h','video_display_abi.h','video_cfg.h','npu_frame.h','frame_config.h']
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--broken',action='store_true');args=ap.parse_args()
    out=ROOT/'build/soc/face_avatar'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ');out.mkdir(parents=True)
    row={'status':'RUNNING','scope':'Host production driver/application state loop with injected peripherals; RV32 firmware compile/link only','commands':[]}
    inputs={};tools={};env=dict(os.environ)
    def run(command,label,expected=0):
        command=list(map(str,command));tools[command[0]]=sha(command[0]);p=subprocess.run(command,cwd=out,env=env,capture_output=True,text=True,timeout=120)
        text=p.stdout+p.stderr;(out/(label+'.log')).write_text(text,encoding='utf-8')
        row['commands'].append({'argv':command,'returncode':p.returncode,'log':label+'.log'})
        if p.returncode!=expected:raise RuntimeError(label+' failed: '+text[-3000:])
        return text
    try:
        names=SOURCES+['sw/include/'+x for x in HEADERS]+['tb/soc/test_face_avatar.c','scripts/soc/run_face_avatar.py',
            'sw/apps/face_avatar/main.c','sw/apps/face_avatar/memory.c','sw/apps/face_avatar/start.S','sw/apps/face_avatar/link.ld','config/cpu_toolchain.json']
        for name in names:
            src=ROOT/name;dst=out/'inputs'/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst);inputs[name]=sha(src)
        cc=Path(os.environ.get('TRIHA_HOST_CC','D:/Xilinx/Vivado/2018.3/msys64/mingw64/bin/gcc.exe'))
        env['PATH']=str(cc.parent)+os.pathsep+str(cc.parents[2]/'usr/bin')+os.pathsep+env['PATH']
        rv=Path(os.environ.get('TRIHA_RISCV_GCC') or json.loads((ROOT/'config/cpu_toolchain.json').read_text())['compiler'])
        frozen=out/'inputs';includes=['-I'+str(frozen/'sw/include')];sources=[frozen/x for x in SOURCES]
        run([cc,'--version'],'host_version');run([rv,'--version'],'rv_version')
        run([cc,'-static','-std=c99','-O2','-Wall','-Wextra','-Werror',*includes,*(['-DFACE_AVATAR_BROKEN'] if args.broken else []),
             frozen/'tb/soc/test_face_avatar.c',*sources,'-o',out/'test.exe'],'host_compile')
        host=run([out/'test.exe'],'host_test',1 if args.broken else 0)
        if args.broken:
            if 'FACE_AVATAR_FAIL' not in host:raise RuntimeError('negative lacks rejection')
            row['negative_rejected']=True
        elif 'PASS FACE_AVATAR checks=' not in host:raise RuntimeError('missing host pass')
        flags=['-march=rv32im_zicsr','-mabi=ilp32','-Os','-ffreestanding','-fno-builtin','-fno-pic','-fno-pie',
               '-msmall-data-limit=0','-mno-relax','-nostdlib','-nostartfiles','-Wall','-Wextra','-Werror']
        app=frozen/'sw/apps/face_avatar'
        run([rv,*flags,*includes,'-Wl,--build-id=none','-T',app/'link.ld',app/'start.S',app/'main.c',app/'memory.c',*sources,'-o',out/'face_avatar.elf'],'firmware')
        nm=rv.with_name(rv.name.replace('gcc.exe','nm.exe'));undefined=run([nm,'-u',out/'face_avatar.elf'],'undefined')
        if undefined.strip():raise RuntimeError('firmware has unresolved symbols')
        size=rv.with_name(rv.name.replace('gcc.exe','size.exe'));row['size']=run([size,out/'face_avatar.elf'],'size').strip()
        row['host_marker']=next((x for x in host.splitlines() if 'PASS FACE_AVATAR' in x or 'FACE_AVATAR_FAIL' in x),'')
        row['status']='FAIL' if args.broken else 'PASS'
    except Exception as e:row.update(status='FAIL',error=str(e))
    finally:
        row['input_hashes']=inputs;row['tool_hashes']=tools
        row['inputs_unchanged']=all(sha(ROOT/k)==v and sha(out/'inputs'/k)==v for k,v in inputs.items())
        row['tools_unchanged']=all(sha(k)==v for k,v in tools.items())
        if not row['inputs_unchanged'] or not row['tools_unchanged']:row.update(status='FAIL',error='inputs changed')
        row['output_hashes']={p.relative_to(out).as_posix():sha(p) for p in out.rglob('*') if p.is_file() and p.name!='result.json'}
        (out/'result.json').write_text(json.dumps(row,indent=2)+'\n',encoding='utf-8')
    print('FACE_AVATAR_'+row['status'],out,row.get('host_marker',''),row.get('error',''))
    return int(row['status']!='PASS')
if __name__=='__main__':sys.exit(main())

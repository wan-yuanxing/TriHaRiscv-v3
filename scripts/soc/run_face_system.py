"""Production face_avatar CPU + actual capture/B03/display, native DDR storage proxy."""
import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import time
import zlib
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/cpu'));sys.path.insert(0,str(ROOT/'scripts/npu'))
from admission_common import validate,sha,save,SIM
from frozen_inputs import FrozenInputs
from run_b03_frame import checked_asset,load_manifest,DEFAULT_ASSETS,DEFAULT_MANIFEST,VENDOR,VENDOR_FILES,read_hex_bytes
import import_b03

def need(value,message):
    if not value:raise RuntimeError(message)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--timeout',type=int,default=7200);parser.add_argument('--compile-only',action='store_true');parser.add_argument('--board-profile',action='store_true');parser.add_argument('--boot-load',action='store_true');parser.add_argument('--boot-only',action='store_true');parser.add_argument('--fixture',type=Path);args=parser.parse_args()
    if args.boot_only:args.boot_load=True
    out=ROOT/'build/soc'/('face_system-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'));out.mkdir(parents=True)
    row={'status':'RUNNING','scope':__doc__,'board_verified':False,'model_loader_verified':False,'board_profile':args.board_profile,'boot_load':args.boot_load,'boot_only':args.boot_only,'commands':[]};save(out/'result.json',row)
    print('FACE_SYSTEM_RUN',out,flush=True);frozen=None
    def run(command,label,timeout=120):
        command=list(map(str,command));frozen.track(Path(command[0]));start=time.monotonic()
        with (out/(label+'.log')).open('wb') as log:
            p=subprocess.Popen(command,cwd=out,stdout=log,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            save(out/(label+'_process.json'),{'pid':p.pid,'argv':command,'timeout':timeout})
            try:code=p.wait(timeout=timeout)
            except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=30);raise RuntimeError(label+' timeout')
        text=(out/(label+'.log')).read_text(errors='replace');row['commands'].append({'argv':command,'returncode':code,'seconds':time.monotonic()-start})
        need(code==0,label+' exit='+str(code)+' '+text[-2500:]);return text
    try:
        admitted=validate();import_b03.verify_import(ROOT)
        source_manifest='config/soc_face_sources.f'
        # Default preserves the preloaded regression; boot mode uses the real
        # packet loader and actual DDR write/verification path before CPU start.
        prod=[p for p in (ROOT/source_manifest).read_text().splitlines() if p and not p.startswith('+') and (args.boot_load or p!='rtl/soc/triha_model_loader.v')]
        prod=list(dict.fromkeys(prod))
        c_sources=['sw/apps/face_avatar/main.c','sw/apps/face_avatar/memory.c','sw/apps/face_avatar/face_avatar.c',
            'sw/drivers/npu_frame.c','sw/drivers/video_capture.c','sw/drivers/video_display.c','sw/drivers/video_frame_pool.c']
        support=c_sources+['tb/soc/tb_face_system.sv','sw/apps/face_avatar/start.S','sw/apps/face_avatar/link.ld']
        support+=['sw/include/'+x for x in ['face_avatar.h','video_capture.h','video_capture_v2.h','video_display.h','video_display_abi.h',
            'video_frame_pool.h','video_cfg.h','npu_frame.h','frame_config.h']]
        support+=['rtl/soc/include/frame_config.vh','rtl/video/include/video_cfg.vh','rtl/video/include/video_capture_v2.vh','rtl/video/include/video_display.vh',
            source_manifest,'config/soc_memory.json','config/cpu_admission.json','config/cpu_toolchain.json','config/npu_b03_sources.f',
            'scripts/soc/run_face_system.py','scripts/npu/frozen_inputs.py','scripts/npu/run_b03_frame.py','scripts/npu/audit_b03_assets.py',
            'scripts/npu/import_b03.py','scripts/cpu/admission_common.py','scripts/video/common.py']+admitted['core']['headers']
        frozen=FrozenInputs(ROOT,out/'inputs',list(dict.fromkeys(prod+support)))
        vendor={Path(x['path']).name:Path(x['path']) for x in admitted['simulation_models']};vendor.update({leaf:VENDOR/leaf for leaf in VENDOR_FILES})
        for leaf,path in vendor.items():frozen.external(path,out/'vendor'/leaf)
        manifest=load_manifest(DEFAULT_MANIFEST);frozen.track(DEFAULT_MANIFEST);raw={}
        for name in ['program.bin','parameter_image.bin','post_table.bin','heads_init.bin','cases/zero/heads_golden.bin','cases/zero/records_golden.bin']:
            raw[name]=checked_asset(DEFAULT_ASSETS,name,manifest['files_sha256']);frozen.external(DEFAULT_ASSETS/name,out/'assets'/name)
        source_rgb=bytes(800*600*3);source_input=bytes(307200);expected_heads=raw['cases/zero/heads_golden.bin'];expected_faces=0;expected_roi=[0,0,0,0]
        if args.fixture:
            need(args.board_profile,'natural fixture currently requires CPU-post board profile')
            fixture=args.fixture.resolve();reference=json.loads((fixture/'reference.json').read_text(encoding='utf-8'))
            frozen.external(fixture/'reference.json',out/'fixture/reference.json')
            need(reference['status']=='PASS_HOST_REFERENCE' and reference['faces']==1,'one-face independent fixture required')
            need(reference['generator_sha256']==sha(ROOT/'scripts/npu/prepare_natural_face.py'),'fixture generator hash differs')
            frozen.track(ROOT/'scripts/npu/prepare_natural_face.py')
            for name in ['frame_rgb.bin','input.bin','heads.bin','records.bin']:
                need(sha(fixture/name)==reference['files'][name],'fixture byte identity '+name)
                frozen.external(fixture/name,out/'fixture'/name)
            source_rgb=(fixture/'frame_rgb.bin').read_bytes();source_input=(fixture/'input.bin').read_bytes();expected_heads=(fixture/'heads.bin').read_bytes()
            need((len(source_rgb),len(source_input),len(expected_heads))==(1440000,307200,26368),'fixture shapes')
            expected_faces=1;expected_roi=reference['records'][0]['roi'];row['fixture_sha256']=sha(fixture/'reference.json')
        (out/'source_rgb.hex').write_text(''.join(source_rgb[n:n+3].hex()+'\n' for n in range(0,len(source_rgb),3)),encoding='ascii')
        (out/'source_input.hex').write_text(''.join(f'{v:02x}\n' for v in source_input),encoding='ascii')
        cfg=json.loads((out/'inputs/config/soc_memory.json').read_text())['b03']
        uploads=[(cfg['program_base'],'program.bin'),(cfg['workspace_base']+cfg['parameter_origin'],'parameter_image.bin'),(cfg['post_table_base'],'post_table.bin')]
        uploads += [(base,'heads_init.bin') for base in cfg['output_bases']]
        lines=[]
        for i,(address,name) in enumerate(uploads):
            data=raw[name];need(address%32==0 and len(data)%32==0,'unaligned preload');leaf=f'upload_{i}.hex'
            (out/leaf).write_text(''.join(data[n:n+32][::-1].hex()+'\n' for n in range(0,len(data),32)),encoding='ascii')
            lines.append(f'{address:08x} {len(data)} {leaf}\n')
        (out/'uploads.txt').write_text(str(len(lines))+'\n'+''.join(lines),encoding='ascii')
        (out/'heads_golden.hex').write_text(''.join(f'{v:02x}\n' for v in expected_heads),encoding='ascii')
        (out/'preload_verified.txt').write_text('54524948\n',encoding='ascii')
        gcc=Path(json.loads((out/'inputs/config/cpu_toolchain.json').read_text())['compiler']);app=out/'inputs/sw/apps/face_avatar'
        offsets={name:'offsetof(struct face_avatar,pool.stats.'+name+')' for name in ['allocated','captured','graph_starts','results','display_submits','display_commits','releases','no_free','faults']}
        offsets.update(slots='offsetof(struct face_avatar,pool.slots)',slot_bytes='sizeof(struct video_frame_slot)',slot_state='offsetof(struct video_frame_slot,state)',slot_frame='offsetof(struct video_frame_slot,id.frame)')
        offsets.update(result_valid='offsetof(struct face_avatar,result.valid)',result_faces='offsetof(struct face_avatar,result.face_count)',result_display='offsetof(struct face_avatar,result.display_count)')
        layout='#include <stddef.h>\n#include "face_avatar.h"\nconst unsigned face_test_layout[]={'+','.join(offsets.values())+'};\n'
        (out/'layout.c').write_text(layout,encoding='ascii');frozen.track(out/'layout.c')
        run([gcc,'--version'],'compiler_version');run([SIM/'vsim.exe','-version'],'simulator_version')
        run([gcc,'-march=rv32im_zicsr','-mabi=ilp32','-Os','-ffreestanding','-fno-builtin','-msmall-data-limit=0','-mno-relax',
             '-nostdlib','-nostartfiles','-Wall','-Wextra','-Werror','-Wl,--build-id=none','-I'+str(out/'inputs/sw/include'),'-T',app/'link.ld',
             app/'start.S',*[out/'inputs'/p for p in c_sources],out/'layout.c','-o',out/'firmware.elf'],'firmware')
        nm=gcc.with_name(gcc.name.replace('gcc.exe','nm.exe'));need(not run([nm,'-u',out/'firmware.elf'],'undefined').strip(),'undefined symbols')
        symbols={m[2]:int(m[0],16) for m in re.findall(r'^([0-9a-f]+)\s+(\w)\s+(\S+)$',run([nm,'-n',out/'firmware.elf'],'symbols'),re.M)}
        elf=(out/'firmware.elf').read_bytes();sram=bytearray(32768);rom=bytearray(b'\x73\x00\x10\x00'*2048);rom[:8]=struct.pack('<II',0x000102b7,0x00028067)
        ph=struct.unpack_from('<I',elf,28)[0];size,count=struct.unpack_from('<HH',elf,42)
        for i in range(count):
            kind,start,va,pa,filesz,memsz=struct.unpack_from('<6I',elf,ph+i*size)
            if kind==1:
                local=pa-0x10000;need(va==pa and 0<=local and local+memsz<=len(sram) and filesz<=memsz,'ELF SRAM bounds');sram[local:local+filesz]=elf[start:start+filesz]
        values=struct.unpack_from('<'+str(len(offsets))+'I',sram,symbols['face_test_layout']-0x10000)
        defines='`define APP_BASE 32\'h%08x\n'%symbols['face_avatar_application']
        for name in ['face_avatar_run_status','face_avatar_trap_cause','face_avatar_trap_pc','face_avatar_trap_value']:
            defines+='`define '+name.upper()+" 32'h%08x\n"%symbols[name]
        for name,value in zip(offsets,values):defines+='`define OFF_'+name.upper()+" 32'd"+str(value)+'\n'
        defines+='`define SOURCE_CRC 32\'h%08x\n'%zlib.crc32(source_rgb)
        for name,value in zip(['EXPECTED_FACES','EXPECTED_X','EXPECTED_Y','EXPECTED_W','EXPECTED_H'],[expected_faces,*expected_roi]):
            defines+='`define '+name+" 32'd"+str(value)+'\n'
        (out/'test_config.vh').write_text(defines,encoding='ascii');frozen.track(out/'test_config.vh')
        for name,data in [('rom',rom),('sram',sram)]:
            (out/(name+'.hex')).write_text(''.join(data[n:n+8][::-1].hex()+'\n' for n in range(0,len(data),8)),encoding='ascii')
        for p in list(out.glob('*.hex'))+[out/'uploads.txt',out/'preload_verified.txt',out/'firmware.elf']:frozen.track(p)
        sources=[out/'vendor'/leaf for leaf in vendor]+[out/'inputs'/p for p in prod]+[out/'inputs/tb/soc/tb_face_system.sv']
        (out/'sources.f').write_text(''.join('"'+p.as_posix()+'"\n' for p in sources),encoding='ascii')
        inc=[out,out/'inputs/rtl/cpu/vendor/src/core',out/'inputs/rtl/soc/include',out/'inputs/rtl/video/include']
        do='onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nvlib work\nvlog -sv -mfcu -f sources.f '+' '.join('{+incdir+'+p.as_posix()+'}' for p in inc)+'\nvsim -t 1ps work.tb_face_system -gBOARD_PROFILE='+str(int(args.board_profile))+' -gBOOT_LOAD='+str(int(args.boot_load))+' -gBOOT_ONLY='+str(int(args.boot_only))+'\n'+('run 1ns\n' if args.compile_only else 'run -all\n')+'quit -code 0 -force\n'
        (out/'run.do').write_text(do,encoding='ascii')
        for p in [out/'sources.f',out/'run.do',SIM/'vlog.exe',SIM/'vopt.exe',SIM/'vlib.exe']:frozen.track(p)
        frozen.verify();save(out/'result.json',{**row,'source_sha256':frozen.inputs})
        print('FACE_SYSTEM_SIM_START',flush=True);text=run([SIM/'vsim.exe','-c','-do','run.do'],'simulation',args.timeout)
        need(not re.search(r'\*\* (?:Error|Fatal)',text),'simulator failure '+text[-3000:])
        if args.compile_only:row.update(status='PASS_COMPILE_ONLY')
        elif args.boot_only:
            need('FACE_BOOT_PASS segments=6 ' in text,'missing actual loader/CPU admission PASS '+text[-3000:])
            row.update(status='PASS_BOOT_ONLY',real_cpu=True,model_loader_verified=True,model_preloaded=False,
                scope='All six admitted assets through actual loader and DDR write/readback bridge; exact memory bytes and CPU admission; no completed inference/display or serial wire/board proof')
        else:
            need('FACE_SYSTEM_PASS' in text,'missing actual application PASS '+text[-3000:])
            for i in range(2):
                heads=read_hex_bytes(out/f'heads_actual_{i}.hex');result=read_hex_bytes(out/f'result_actual_{i}.hex');h=struct.unpack('<32I',result)
                need(heads==expected_heads,'independent HEAD bytes')
                if args.board_profile:need(result==bytes(128),'CPU-post hardware result region changed')
                else:need(h[:10]==(0x3352504e,1,128,1,0,0,i+1,7,i+1,0) and h[10]==h[11]==h[12]==0 and zlib.crc32(result[:124])==h[31],'NPR3 identity/emptyCRC')
            row.update(status='PASS',real_cpu=True,actual_capture=True,actual_npu=True,actual_display=True,model_preloaded=not args.boot_load,model_loader_verified=args.boot_load,
                source_frames='natural face RGB through actual capture/preprocess' if args.fixture else 'zero RGB through actual capture/preprocess',expected_faces=expected_faces,scope='Actual production application loop and display pixels/retirement; native DDR storage proxy; no board proof')
        frozen.verify()
    except Exception as e:row.update(status='FAIL',error=str(e));print('FACE_SYSTEM_FAIL',e,flush=True)
    finally:
        if frozen:
            row.update(source_sha256=frozen.inputs,external_sha256=frozen.external_inputs,tracked_sha256=frozen.tracked)
            try:frozen.verify();row['inputs_unchanged']=True
            except Exception as e:row.update(status='FAIL',inputs_unchanged=False,error=str(e))
        row['output_sha256']={p.relative_to(out).as_posix():sha(p) for p in out.glob('*') if p.is_file() and p.name!='result.json'};save(out/'result.json',row)
    print('FACE_SYSTEM_'+row['status'],out,flush=True);return int(row['status'] not in ('PASS','PASS_COMPILE_ONLY','PASS_BOOT_ONLY'))
if __name__=='__main__':sys.exit(main())

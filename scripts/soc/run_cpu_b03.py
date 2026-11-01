"""Actual CPU/real B03/CDC/shared fabric/HMIC bridge with native byte-memory proxy."""
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

def need(condition,message):
    if not condition:raise RuntimeError(message)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--timeout',type=int,default=7200);args=parser.parse_args()
    out=ROOT/'build/soc'/('cpu_b03-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'));out.mkdir(parents=True)
    row={'status':'RUNNING','scope':__doc__,'board_verified':False,'commands':[]};save(out/'result.json',row)
    print('CPU_B03_RUN',out,flush=True)
    frozen=None
    def run(command,label,timeout=120):
        command=list(map(str,command));frozen.track(Path(command[0]));started=time.monotonic()
        with (out/(label+'.log')).open('wb') as log:
            p=subprocess.Popen(command,cwd=out,stdout=log,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            save(out/(label+'_process.json'),{'pid':p.pid,'argv':command,'timeout':timeout})
            try:code=p.wait(timeout=timeout)
            except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=30);raise RuntimeError(label+' timeout')
        text=(out/(label+'.log')).read_text(errors='replace');row['commands'].append({'argv':command,'returncode':code,'seconds':time.monotonic()-started})
        need(code==0,label+' exit='+str(code)+' '+text[-3000:]);return text
    try:
        admitted=validate();import_b03.verify_import(ROOT)
        prod=admitted['core']['sources']+admitted['cache_sources']+[
            'rtl/soc/triha_sram.v','rtl/soc/triha_boot_rom.v','rtl/soc/cpu_native_axil.v','rtl/soc/triha_application_router.v',
            'rtl/soc/triha_application_cpu.v','rtl/soc/triha_compute_system.v','rtl/soc/triha_axi128_cdc.v','rtl/soc/soc_axi128_arbiter.v',
            'rtl/soc/soc_ddr_fabric.v','rtl/soc/npu_service_axi128.v','rtl/video/video_async_fifo.sv','rtl/video/axi128_hmic256.sv',
            'rtl/npu/npu_frame_mmio.v','rtl/npu/npu_frame_top.v','rtl/npu/b03_frame_service.v','rtl/npu/b03_block_dma_compact.v']
        prod+=(ROOT/import_b03.FILELIST).read_text().splitlines();prod=list(dict.fromkeys(prod))
        support=['tb/soc/tb_cpu_b03.sv','sw/tests/npu_frame/main.c','sw/tests/npu_frame/start.S','sw/tests/npu_frame/link.ld',
            'sw/drivers/npu_frame.c','sw/include/npu_frame.h','sw/include/frame_config.h','rtl/soc/include/frame_config.vh',
            'config/soc_memory.json','config/cpu_admission.json','config/cpu_toolchain.json','config/npu_b03_sources.f',
            'scripts/soc/run_cpu_b03.py','scripts/npu/frozen_inputs.py','scripts/npu/run_b03_frame.py','scripts/npu/audit_b03_assets.py',
            'scripts/npu/import_b03.py','scripts/cpu/admission_common.py','scripts/video/common.py']+admitted['core']['headers']
        frozen=FrozenInputs(ROOT,out/'inputs',list(dict.fromkeys(prod+support)))
        vendor={Path(x['path']).name:Path(x['path']) for x in admitted['simulation_models']}
        vendor.update({leaf:VENDOR/leaf for leaf in VENDOR_FILES})
        for leaf,path in vendor.items():frozen.external(path,out/'vendor'/leaf)
        manifest=load_manifest(DEFAULT_MANIFEST);frozen.track(DEFAULT_MANIFEST);raw={}
        names=['program.bin','parameter_image.bin','post_table.bin','heads_init.bin']+[f'cases/{case}/{leaf}.bin' for case in ['zero','pattern'] for leaf in ['input','heads_golden','records_golden']]
        for name in names:
            raw[name]=checked_asset(DEFAULT_ASSETS,name,manifest['files_sha256']);frozen.external(DEFAULT_ASSETS/name,out/'assets'/name)
        cfg=json.loads((out/'inputs/config/soc_memory.json').read_text())['b03']
        uploads=[(cfg['program_base'],'program.bin'),(cfg['workspace_base']+cfg['parameter_origin'],'parameter_image.bin'),
                 (cfg['post_table_base'],'post_table.bin')]
        for i,case in enumerate(['zero','pattern']):
            uploads.extend([(cfg['input_bases'][i],f'cases/{case}/input.bin'),(cfg['output_bases'][i],'heads_init.bin')])
            gold=raw[f'cases/{case}/heads_golden.bin'];(out/f'heads_golden_{i}.hex').write_text(''.join(f'{b:02x}\n' for b in gold),encoding='ascii')
        lines=[]
        for i,(address,name) in enumerate(uploads):
            data=raw[name];need(address%32==0 and len(data)%32==0,'unaligned preload')
            leaf=f'upload_{i}.hex';(out/leaf).write_text(''.join(data[n:n+32][::-1].hex()+'\n' for n in range(0,len(data),32)),encoding='ascii')
            lines.append(f'{address:08x} {len(data)} {leaf}\n')
        (out/'uploads.txt').write_text(str(len(lines))+'\n'+''.join(lines),encoding='ascii')
        (out/'preload_verified.txt').write_text('54524948\n',encoding='ascii')
        for p in out.glob('*.hex'):frozen.track(p)
        frozen.track(out/'uploads.txt');frozen.track(out/'preload_verified.txt')
        gcc=Path(json.loads((out/'inputs/config/cpu_toolchain.json').read_text())['compiler']);app=out/'inputs/sw/tests/npu_frame'
        run([gcc,'--version'],'compiler_version');run([SIM/'vsim.exe','-version'],'simulator_version')
        run([gcc,'-march=rv32im_zicsr','-mabi=ilp32','-O2','-ffreestanding','-fno-builtin','-msmall-data-limit=0','-mno-relax',
             '-nostdlib','-nostartfiles','-Wall','-Wextra','-Werror','-Wl,--build-id=none','-I'+str(out/'inputs/sw/include'),'-T',app/'link.ld',
             app/'start.S',app/'main.c',out/'inputs/sw/drivers/npu_frame.c','-o',out/'firmware.elf'],'firmware')
        nm=gcc.with_name(gcc.name.replace('gcc.exe','nm.exe'));need(not run([nm,'-u',out/'firmware.elf'],'undefined').strip(),'unresolved symbols')
        elf=(out/'firmware.elf').read_bytes();sram=bytearray(32768);rom=bytearray(b'\x73\x00\x10\x00'*2048)
        rom[:8]=struct.pack('<II',0x000102b7,0x00028067);ph=struct.unpack_from('<I',elf,28)[0];size,count=struct.unpack_from('<HH',elf,42)
        for i in range(count):
            kind,start,va,pa,filesz,memsz=struct.unpack_from('<6I',elf,ph+i*size)
            if kind==1:
                local=pa-0x10000;need(va==pa and 0<=local and local+memsz<=len(sram) and filesz<=memsz,'ELF SRAM bounds')
                sram[local:local+filesz]=elf[start:start+filesz]
        for name,data in [('rom',rom),('sram',sram)]:
            p=out/(name+'.hex');p.write_text(''.join(data[n:n+8][::-1].hex()+'\n' for n in range(0,len(data),8)),encoding='ascii');frozen.track(p)
        sources=[out/'vendor'/leaf for leaf in vendor]+[out/'inputs'/p for p in prod]+[out/'inputs/tb/soc/tb_cpu_b03.sv']
        (out/'sources.f').write_text(''.join('"'+p.as_posix()+'"\n' for p in sources),encoding='ascii')
        inc=[out/'inputs/rtl/cpu/vendor/src/core',out/'inputs/rtl/soc/include']
        do='onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nvlib work\nvlog -sv -mfcu -f sources.f '+ ' '.join('{+incdir+'+p.as_posix()+'}' for p in inc)+'\nvsim -t 1ps work.tb_cpu_b03\nrun -all\nquit -code 0 -force\n'
        (out/'run.do').write_text(do,encoding='ascii');frozen.track(out/'sources.f');frozen.track(out/'run.do');frozen.track(out/'firmware.elf')
        frozen.verify();save(out/'result.json',{**row,'source_sha256':frozen.inputs,'external_sha256':frozen.external_inputs})
        print('CPU_B03_SIM_START timeout='+str(args.timeout),flush=True)
        text=run([SIM/'vsim.exe','-c','-do','run.do'],'simulation',args.timeout)
        need('CPU_B03_PASS frames=2' in text and not re.search(r'\*\* (?:Error|Fatal)',text),'missing CPU real-frame PASS: '+text[-3000:])
        frames=[]
        for i,case in enumerate(['zero','pattern']):
            heads=read_hex_bytes(out/f'heads_actual_{i}.hex');result=read_hex_bytes(out/f'result_actual_{i}.hex');h=struct.unpack('<32I',result[:128])
            need(heads==raw[f'cases/{case}/heads_golden.bin'],'HEAD exact bytes mismatch')
            need(h[:10]==(0x3352504e,1,128,1,0,0,101+i,7,1001+i,0),'result identity')
            need(zlib.crc32(result[:124])==h[31] and result[128:]==raw[f'cases/{case}/records_golden.bin'] and zlib.crc32(result[128:])==h[12],'result CRC/oracle')
            need(h[13]==cfg['output_bases'][i]+cfg['result_offset']+128-0x82000000,'record pointer')
            frames.append({'case':case,'slot':i,'faces':h[10],'heads_sha256':sha(out/f'heads_actual_{i}.hex'),'result_sha256':sha(out/f'result_actual_{i}.hex')})
        frozen.verify();row.update(status='PASS',frames=frames,real_cpu=True,actual_79op_model_post=True,leaf_completions_injected=False,
            cdc_100_to_125=True,single_shared_hmic_bridge=True,native_byte_memory_proxy=True)
    except Exception as e:row.update(status='FAIL',error=str(e));print('CPU_B03_FAIL',e,flush=True)
    finally:
        if frozen:
            row.update(source_sha256=frozen.inputs,external_sha256=frozen.external_inputs,tracked_sha256=frozen.tracked)
            try:frozen.verify();row['inputs_unchanged']=True
            except Exception as e:row.update(status='FAIL',inputs_unchanged=False,error=str(e))
        row['output_sha256']={p.relative_to(out).as_posix():sha(p) for p in out.glob('*') if p.is_file() and p.name!='result.json'}
        save(out/'result.json',row)
    print('CPU_B03_'+row['status'],out,flush=True);return int(row['status']!='PASS')
if __name__=='__main__':sys.exit(main())

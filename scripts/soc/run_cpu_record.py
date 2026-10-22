"""Pinned real RV32 CPU executes the capture/display/frame-pool C drivers.

Digital same-clock diagnostic; no CPU production import, CDC, physical memory
visibility or board result. CPU sources are read only from fixed Git objects.
"""
from pathlib import Path
import argparse,json,os,re,subprocess,sys,zlib
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/video'))
from common import fresh_run,input_hashes,sha256,tool,write_json
from record_pipeline_reference import fixtures,channel
from run_cpu_video import load_fixture,export_cpu,copy_inputs,verify_snapshots

OWN=['scripts/soc/run_cpu_record.py','scripts/soc/run_cpu_video.py','config/cpu_video_fixture.json',
     'tb/soc/tb_cpu_record_firmware.sv','rtl/soc/video_axil_decode.v','rtl/soc/cpu_native_axil.v',
     'sw/tests/video_record/start.S','sw/tests/video_record/main.c','sw/tests/video_record/link.ld',
     'sw/drivers/video_capture.c','sw/drivers/video_display.c','sw/drivers/video_frame_pool.c',
     'sw/include/video_capture.h','sw/include/video_capture_v2.h','sw/include/video_display.h',
     'sw/include/video_display_abi.h','sw/include/video_frame_pool.h','sw/include/video_cfg.h',
     'scripts/video/record_pipeline_reference.py','scripts/video/common.py',
     'tb/video/check_record_pixels.py','tb/video/overlay_reference.py',
     'rtl/video/include/video_cfg.vh','rtl/video/include/video_capture_v2.vh','rtl/video/include/video_display.vh',
     'config/video_capture_v2.json','config/video_display.json','config/video_cfg.json']

def signature_valid(words,failure):
    return len(words)==16 and words[0]==0x43505246 and words[1]==99 and words[2]==3 and words[3:6]==([0,0,0] if failure else [2,3,1]) and words[6]>0

def verify_digests(table,base=None):
    for name,digest in table.items():
        path=Path(name) if base is None else base/name
        if sha256(path)!=digest:raise RuntimeError('frozen input/tool changed: '+str(path))

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case',choices=('all','normal','bad_eof','no_control','bad_memory'),default='all')
    args=parser.parse_args(argv)
    work=fresh_run('cpu_record');latest=ROOT/'build/video/latest_cpu_record.json'
    result=dict(status='running',directory=work.relative_to(ROOT).as_posix(),inputs={},runs={},commands=[],cpu_executed=False,real_NPU=False,physical_visibility_verified=False,physical_board=False)
    write_json(latest,result);source_records=[];cpu_records=[];tools={};generated={}
    def verify():
        verify_snapshots(work/'inputs',source_records);verify_snapshots(work/'cpu_snapshot',cpu_records)
        verify_digests(tools);verify_digests(generated,work)
        verify_digests(result['inputs'],ROOT)
    def execute(command,name,timeout=180,negative=None):
        verify();command=list(map(str,command));log=work/(name+'.log')
        result['commands'].append(dict(argv=command,cwd=str(work),log=log.name))
        with log.open('w',encoding='utf-8') as stream:
            run=subprocess.run(command,cwd=work,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
        result['commands'][-1]['exit']=run.returncode;verify();text=log.read_text(encoding='utf-8',errors='replace')
        if negative:
            if run.returncode==0 or negative not in text or 'CPU_RECORD_FIRMWARE_PASS' in text:raise RuntimeError('negative was not rejected: '+name+'\n'+text[-3000:])
        elif run.returncode:raise RuntimeError(name+'\n'+text[-4000:])
        print(name,'REJECTED' if negative else 'OK',flush=True);return text
    try:
        manifest_name='fpga/pg2l100h/project/video_record_pipeline.json';m=json.loads((ROOT/manifest_name).read_text(encoding='utf-8'))
        names=set(OWN+m['sources']+m['tests']+[manifest_name])
        result['inputs']=input_hashes(ROOT/p for p in names)
        source_records=copy_inputs(names,work/'inputs',result['inputs'])
        fixture=load_fixture();cpu_records=export_cpu(fixture,work/'cpu_snapshot')
        result['cpu']=dict(revision=fixture['cpu_revision'],blobs=cpu_records)
        primitives=json.loads((work/'cpu_snapshot/config/cpu_primitives.json').read_text(encoding='utf-8'))
        gcc=Path(os.environ.get('TRIHA_RISCV_GCC',fixture['gcc']));vsim=tool('vsim')
        executables={'gcc':gcc,'objcopy':gcc.with_name(gcc.name.replace('gcc.exe','objcopy.exe')),'objdump':gcc.with_name(gcc.name.replace('gcc.exe','objdump.exe')),'nm':gcc.with_name(gcc.name.replace('gcc.exe','nm.exe')),'vsim':vsim,'vlog':vsim.with_name('vlog.exe'),'vlib':vsim.with_name('vlib.exe'),'python':Path(sys.executable)}
        for p in executables.values():
            if not p.is_file():raise FileNotFoundError(p)
            tools[str(p)]=sha256(p)
        for model in primitives['simulation_models']:
            if sha256(model['path'])!=model['sha256']:raise RuntimeError('primitive hash mismatch')
            tools[model['path']]=model['sha256']
        result['tools']=tools;result['source_snapshot']=source_records
        execute([gcc,'--version'],'gcc_version');execute([vsim,'-version'],'modelsim_version')
        # Compile and operate only frozen source copies, never a live CPU checkout.
        sources=[work/'cpu_snapshot'/p for p in fixture['cpu_sources']]+[Path(p['path']) for p in primitives['simulation_models']]
        sources += [work/'inputs'/p for p in m['sources']+m['tests'] if p!='tb/video/tb_video_record_pipeline.sv']
        sources += [work/'inputs'/p for p in ('rtl/soc/cpu_native_axil.v','rtl/soc/video_axil_decode.v','tb/soc/tb_cpu_record_firmware.sv')]
        execute([executables['vlib'],'work'],'library')
        execute([executables['vlog'],'-sv','-mfcu','-work','work','+incdir+'+(work/'cpu_snapshot/rtl/cpu/vendor/src/core').as_posix(),'+incdir+'+(work/'inputs/rtl/video/include').as_posix(),*sources],'compile',300)
        for name,height,case,bad,no_control,negative in [('no_control',10,1,0,1,'CPU_RECORD_FAIL timeout'),('bad_eof',10,1,0,0,None),('normal',600,0,0,0,None),('bad_memory',10,0,1,0,'PIPELINE_FAULT')]:
            if args.case not in ('all',name):continue
            cw=work/name;cw.mkdir();print('CPU_RECORD_FIXTURES',name,flush=True);fixtures(cw,height)
            record=(cw/'record.bin').read_bytes();words=[int.from_bytes(record[i:i+4],'little') for i in range(0,640,4)]
            raw=[];preview=[];crcs=[]
            for tag in range(5):
                data=bytes(channel(x,y,c,tag) for y in range(height) for x in range(800) for c in range(3));crcs.append(zlib.crc32(data))
                if tag in (1,2):
                    raw.append(crcs[-1]);preview.append(zlib.crc32(bytes((sum(channel(x*2+dx,y*2+dy,c,tag) for dy in range(2) for dx in range(2))+2)//4 for y in range(height//2) for x in range(400) for c in range(3))))
            (cw/'source_crc.hex').write_text(''.join(f'{c:08x}\n' for c in crcs),encoding='ascii')
            header='static const uint32_t fixture_words[160]={'+','.join(f'0x{v:08x}u' for v in words)+'};\n'
            header+='static const uint32_t fixture_raw_crc[2]={'+','.join(f'0x{v:08x}u' for v in raw)+'};\n'
            header+='static const uint32_t fixture_preview_crc[2]={'+','.join(f'0x{v:08x}u' for v in preview)+'};\n'
            (cw/'fixture.h').write_text(header,encoding='ascii')
            for p in cw.iterdir():
                if p.is_file():generated[p.relative_to(work).as_posix()]=sha256(p)
            elf=cw/'firmware.elf';binary=cw/'firmware.bin';ss=work/'inputs/sw/tests/video_record'
            execute([gcc,'-march=rv32i_zicsr','-mabi=ilp32','-Os','-ffreestanding','-fno-builtin','-ffunction-sections','-fdata-sections','-fno-pic','-fno-pie','-msmall-data-limit=0','-mno-relax','-nostdlib','-nostartfiles','-Wall','-Wextra','-Werror','-I'+str(work/'inputs/sw/include'),'-I'+str(cw),'-DTEST_CASE='+str(case),'-T',ss/'link.ld','-Wl,--build-id=none','-Wl,--gc-sections',ss/'start.S',ss/'main.c',*[work/'inputs/sw/drivers'/p for p in ('video_capture.c','video_display.c','video_frame_pool.c')],'-lgcc','-o',elf],name+'_gcc')
            execute([executables['objcopy'],'-O','binary',elf,binary],name+'_objcopy');data=binary.read_bytes()
            if len(data)>32768:raise RuntimeError('ROM exceeds 32KiB')
            binary.write_bytes(data.ljust(32768,b'\0'));generated[binary.relative_to(work).as_posix()]=sha256(binary);generated[elf.relative_to(work).as_posix()]=sha256(elf)
            execute([executables['objdump'],'-d',elf],name+'_disassembly')
            symbols=execute([executables['nm'],'-n',elf],name+'_symbols')
            signature=cw/'signature.hex';macro=cw/'run.do'
            macro.write_text('onerror {quit -code 1}\nonbreak {if {[file exists '+signature.as_posix()+']} {quit -code 0} else {quit -code 2}}\nrun -all\nquit -code 3\n',encoding='ascii',newline='\n');generated[macro.relative_to(work).as_posix()]=sha256(macro)
            text=execute([vsim,'-c','-onfinish','stop','work.tb_cpu_record_firmware','-gH='+str(height),'-gCASE_ID='+str(case),'-gBAD_PIXEL='+str(bad),'-gNO_CONTROL='+str(no_control),'+DIR='+cw.as_posix(),'+CRC='+(cw/'source_crc.hex').as_posix(),'+ROM_IMAGE='+binary.as_posix(),'+SIGNATURE='+signature.as_posix(),'-do',macro.as_posix()],name+'_simulation',900,negative)
            if negative:
                if signature.exists():raise RuntimeError('negative run unexpectedly produced success signature: '+name)
                result['runs'][name]=dict(status='rejected',reason=negative)
            else:
                words=[int(v,16) for v in signature.read_text(encoding='ascii').splitlines()] if signature.is_file() else []
                if text.count('CPU_RECORD_FIRMWARE_PASS')!=1 or not signature_valid(words,case!=0):raise RuntimeError('incomplete CPU signature '+name)
                result['runs'][name]=dict(status='pass',signature=words,counts={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',next(line for line in text.splitlines() if 'CPU_RECORD_FIRMWARE_PASS' in line))},firmware_bytes=len(data))
        verify();result.update(status='pass',cpu_executed=True,artifacts=input_hashes(p for p in work.rglob('*') if p.is_file() and 'work' not in p.relative_to(work).parts))
    except Exception as error:result.update(status='fail',error=str(error));print('CPU_RECORD_FAIL',error,file=sys.stderr,flush=True)
    result['generated']=generated;write_json(work/'result.json',result);write_json(latest,result)
    print('CPU_RECORD_'+result['status'].upper(),work,flush=True)
    return 0 if result['status']=='pass' else 1
if __name__=='__main__':raise SystemExit(main())

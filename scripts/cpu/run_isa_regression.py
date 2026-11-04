"""Replay official ELF tests on frozen current RTL using native Windows ModelSim."""
import argparse
import collections
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import time
from admission_common import validate, prepare_isa_inputs

ROOT = Path(__file__).resolve().parents[2]
BASE, SIZE = 0x80000000, 262144


def sha(path, algorithm='sha256'):
    return hashlib.new(algorithm, Path(path).read_bytes()).hexdigest()


def save(path, data):
    tmp = path.with_suffix(path.suffix+'.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    tmp.replace(path)


def load_elf(data):
    if len(data) < 52 or data[:7] != b'\x7fELF\x01\x01\x01' or struct.unpack_from('<H',data,18)[0] != 243:
        raise ValueError('Expected little-endian ELF32 RISC-V')
    entry, phoff, shoff, flags = struct.unpack_from('<4I',data,24)
    phsize, phnum, shsize, shnum = struct.unpack_from('<4H',data,42)
    if entry != BASE or phsize != 32 or phoff+phnum*phsize > len(data):
        raise ValueError('Invalid entry/program headers')
    image, segments = bytearray(SIZE), []
    for i in range(phnum):
        kind, offset, vaddr, addr, filesz, memsz, perm, align = struct.unpack_from('<8I',data,phoff+i*phsize)
        if kind != 1:
            continue
        if addr != vaddr or addr < BASE or addr+memsz > BASE+SIZE or filesz > memsz or offset+filesz > len(data):
            raise ValueError('PT_LOAD exceeds test RAM/file or has inconsistent address')
        image[addr-BASE:addr-BASE+filesz] = data[offset:offset+filesz]
        segments.append({'address':hex(addr),'file_bytes':filesz,'memory_bytes':memsz,'flags':perm})
    if not segments or shsize != 40 or shoff+shnum*40 > len(data):
        raise ValueError('Missing segments/invalid section headers')
    sections = [struct.unpack_from('<10I',data,shoff+i*40) for i in range(shnum)]
    symbols = {}
    for section in sections:
        if section[1] != 2:
            continue
        strings = sections[section[6]]
        names = data[strings[4]:strings[4]+strings[5]]
        for offset in range(section[4],section[4]+section[5],section[9]):
            name,value,length,info,other,index = struct.unpack_from('<IIIBBH',data,offset)
            symbols[names[name:names.find(b'\0',name)].decode('utf-8',errors='replace')] = value
    tohost = symbols.get('tohost')
    if tohost is None or not BASE <= tohost <= BASE+SIZE-4 or tohost%4:
        raise ValueError('Missing or unmapped tohost')
    return bytes(image), {'entry':hex(entry),'elf_flags':hex(flags),'tohost':tohost,'segments':segments}


def classify(text, code, suite, timed_out=False):
    if timed_out or 'RV32_ISA_FAIL reason=timeout' in text:
        return 'TIMEOUT'
    if code != 0 or re.search(r'RV32_ISA_FAIL|\*\* (?:Error|Fatal)',text):
        return 'FAIL'
    if len(re.findall(r'RV32_ISA_PASS tohost=00000001 cycles=\d+',text)) != 1:
        return 'FAIL'
    if suite == 'act4' and 'RVCP-SUMMARY: TEST PASSED' not in text:
        return 'FAIL'
    return 'PASS'


def native(exe, options, cwd, log, timeout=120):
    log.parent.mkdir(parents=True,exist_ok=True)
    errlog = log.with_suffix('.stderr.log')
    start = time.monotonic()
    command = list(map(str,[exe,*options]))
    with log.open('wb') as out, errlog.open('wb') as err:
        p = subprocess.Popen(command,cwd=cwd,stdout=out,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW)
        timed_out = False
        try:
            code = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],capture_output=True)
            code = p.wait(timeout=15)
    rec = {'command':command,'cwd':str(cwd),'pid':p.pid,'return_code':code,'timed_out':timed_out,
           'elapsed_seconds':round(time.monotonic()-start,3),'stdout':str(log),'stderr':str(errlog),
           'stdout_sha256':sha(log),'stderr_sha256':sha(errlog)}
    return rec, log.read_text(encoding='utf-8',errors='replace')+errlog.read_text(encoding='utf-8',errors='replace')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--suite',choices=['all','riscv-tests','act4'],default='all')
    ap.add_argument('--filter',default='')
    ap.add_argument('--self-test',action='store_true')
    ap.add_argument('--dual-issue',type=int,choices=[0,1],default=0)
    ap.add_argument('--minimal-control',type=int,choices=[0,1],default=0)
    ap.add_argument('--max-cycles',type=int,default=2000000)
    ap.add_argument('--timeout',type=int,default=120)
    ap.add_argument('--input-root',type=Path,default=None)
    ap.add_argument('--act4-root',type=Path,default=None,
                    help='ACT4 profile directory containing elfs/, build/ and .act_build_cache.json')
    ap.add_argument('--support',type=Path,default=None)
    args = ap.parse_args()
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    run = ROOT/'build/cpu'/('isa-'+stamp)
    frozen = run/'frozen'
    frozen.mkdir(parents=True)
    result = {'status':'RUNNING','started_utc':stamp,'run_directory':str(run),'cpu_root':str(ROOT),
              'configuration':'rv32im_zicsr','dual_issue':args.dual_issue,'minimal_control_cpu':args.minimal_control,
              'btb_entries':2 if args.minimal_control else 512,'bht_entries':2 if args.minimal_control else 512,'ras_entries':4,'gshare':0,
              'memory':'256 KiB test RAM at 0x80000000, no cache/DDR; not production SoC memory map',
              'suite':args.suite,'filter':args.filter,'self_test':args.self_test,'max_cycles':args.max_cycles,
              'wall_timeout_seconds':args.timeout,'rtl_hashes':{},'input_hashes':{},'tools':{},'commands':[],'cases':[],
              'official_dut_results_reused':False,'new_sail_execution':False,
              'oracle':'Preserved ACT4 self-checking ELF/Sail 0.12 results, no new Sail generation',
              'act4_commit':'375292312d3d02b7468272eb550d81cb74be53d8'}
    def checkpoint():
        result['counts'] = dict(collections.Counter(c['status'] for c in result['cases']))
        result['heartbeat_utc'] = dt.datetime.now(dt.timezone.utc).isoformat()
        save(run/'result.json',result)
    try:
        admission = validate(ROOT)
        if not args.self_test and args.input_root is None:
            staged = prepare_isa_inputs(ROOT, run/'isa-inputs')
            args.input_root, args.act4_root, args.support = staged['input_root'], staged['act4_root'], staged['support']
            result['staged_archive_sha256'] = staged['archive_sha256']
        for p in (args.input_root,args.act4_root,args.support):
            if p is not None and not p.resolve().is_relative_to(ROOT):
                raise ValueError('ISA inputs must be staged inside main project')
        filelist = [s.strip() for s in (ROOT/'config/cpu_sources.f').read_text(encoding='utf-8').splitlines()
                    if s.strip() and not s.startswith('#') and not s.startswith('tb/') and '/tb/' not in s]
        headers = ['rtl/cpu/vendor/src/core/biriscv_defs.v']
        extras = ['config/cpu_sources.f','config/cpu_toolchain.json','config/cpu_admission.json',
                  'rtl/cpu/ADAPTATIONS.json','rtl/cpu/vendor/LICENSE','rtl/cpu/vendor/UPSTREAM.json',
                  'tb/cpu/tb_triha_isa_official.v','scripts/cpu/run_modelsim.do',
                  'scripts/cpu/run_isa_regression.py','scripts/cpu/admission_common.py']
        for rel in dict.fromkeys(filelist+headers+extras):
            source, dest = ROOT/rel, frozen/rel
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source,dest)
            result['input_hashes'][str(source)] = sha(source)
            if rel.startswith('rtl/'):
                result['rtl_hashes'][rel] = sha(source)
        manifest = json.loads((ROOT/'rtl/cpu/ADAPTATIONS.json').read_text(encoding='utf-8'))
        for entry in manifest['adaptations']:
            for key in ['base','derived']:
                if sha(ROOT/entry[key]) != entry[key+'_sha256']:
                    raise ValueError('Adaptation hash mismatch: '+entry[key])
        primitives = admission['simulation_models']
        for p in primitives:
            if sha(p['path']) != p['sha256']:
                raise ValueError('Primitive hash mismatch: '+p['path'])
            result['input_hashes'][p['path']] = p['sha256']
        tools = Path(r'D:\modeltech64_2020.4\win64')
        gcc = Path(json.loads((ROOT/'config/cpu_toolchain.json').read_text(encoding='utf-8'))['compiler'])
        for tool,opts in [(gcc,['--version']),(tools/'vsim.exe',['-version'])]:
            rec,text = native(tool,opts,run,run/(tool.stem+'-version.log'))
            result['tools'][str(tool)] = {'sha256':sha(tool),'version':text.strip()}
            result['commands'].append(rec)
        for name,opts in [('vmap',['-c']),('vlib',['work'])]:
            rec,text = native(tools/(name+'.exe'),opts,run,run/(name+'.log'))
            result['commands'].append(rec)
            if rec['return_code']:
                raise RuntimeError(name+' failed: '+text[-1500:])
        opts = ['-work','work','+incdir+'+str(frozen/'rtl/cpu/vendor/src/core'),
                *[str(frozen/f) for f in filelist],*[p['path'] for p in primitives],
                str(frozen/'tb/cpu/tb_triha_isa_official.v')]
        rec,text = native(tools/'vlog.exe',opts,run,run/'compile.log',180)
        result['commands'].append(rec)
        if rec['return_code'] or '** Error:' in text:
            raise RuntimeError('RTL compile failed: '+text[-2000:])
        actroot = args.act4_root
        if args.suite in ('act4','all') and not args.self_test and args.act4_root:
            # UDB preprocessing and the Sail simulator have separate configs.
            # Freeze and check both; selecting I/M tests alone does not disable
            # compressed-instruction semantics in Sail's EPC oracle.
            configroot = actroot.parent.parent
            sail = (configroot/'sail.json').read_text(encoding='utf-8')
            udb = (configroot/'triha-rv32im-zicsr.yaml').read_text(encoding='utf-8')
            defines = (actroot/'rvtest_config.svh').read_text(encoding='utf-8')
            if (not re.search(r'"Zca"\s*:\s*\{\s*"supported"\s*:\s*false',sail)
                    or re.search(r'name:\s*(?:C|Zca),',udb)
                    or re.search(r'`define (?:C|ZCA)_SUPPORTED',defines)):
                raise ValueError('ACT4 UDB/Sail configuration must both disable C/Zca for this CPU')
            result['oracle'] = 'Pinned no-C ACT4/Sail 0.12 self-checking ELFs replayed locally; fresh Windows ModelSim DUT execution'
            result['new_sail_execution'] = False
            result['sail_execution_environment'] = 'Historical one-time generation only; current run uses main-tree pinned archive, no WSL or cross-tree runtime dependency'
            result['generation_inputs'] = {}
            for name in ['sail.json','triha-rv32im-zicsr.yaml','test_config.yaml','link.ld','rvmodel_macros.h',
                         'generation.log','generation-exit.json','generate.sh']:
                f = configroot/name
                result['generation_inputs'][str(f)] = sha(f)
                result['input_hashes'][str(f)] = sha(f)
            generation_exit = json.loads((configroot/'generation-exit.json').read_text(encoding='utf-8-sig'))
            if generation_exit['return_code'] != 0:
                raise ValueError('ACT4 input generation failed')
        tests = []
        if args.self_test:
            for name,code in [('monitor-pass',1),('monitor-fail',3),('monitor-timeout',None)]:
                image = bytearray(SIZE)
                words = [0x800012b7,((code or 0)<<20)|0x313,0x0062a223,0x0000006f] if code else [0x0000006f]
                for i,w in enumerate(words):
                    struct.pack_into('<I',image,4*i,w)
                tests.append({'suite':'monitor','case':name,'image_bytes':bytes(image),'tohost':0x80001004})
        else:
            for suite in (['riscv-tests','act4'] if args.suite=='all' else [args.suite]):
                listing = args.support/(suite+'-cases.csv')
                result['input_hashes'][str(listing)] = sha(listing)
                for row in csv.DictReader(listing.open(encoding='utf-8-sig',newline='')):
                    if args.filter and not re.search(args.filter,row['case']):
                        continue
                    elf = (args.input_root/'riscv-tests'/row['case']/(row['case']+'.elf') if suite=='riscv-tests'
                           else actroot/'elfs/rv32i'/row['category']/(row['case']+'.elf'))
                    tests.append({'suite':suite,'case':row['case'],'category':row['category'],'elf':elf})
            if not args.filter and len(tests) != (103 if args.suite=='all' else 50 if args.suite=='riscv-tests' else 53):
                raise ValueError('Unexpected official test count')
        result['total'] = len(tests)
        checkpoint()
        for test in tests:
            case = run/test['suite']/test['case']
            case.mkdir(parents=True)
            detail = {k:v for k,v in test.items() if k not in ['image_bytes','elf']}
            if 'elf' in test:
                source = test['elf']
                data = source.read_bytes()
                image,attrs = load_elf(data)
                detail.update(attrs)
                elf = case/'test.elf'
                elf.write_bytes(data)
                result['input_hashes'][str(source)] = sha(source)
                detail.update(original_elf=str(source),elf_sha256=sha(elf))
                if test['suite']=='act4':
                    cache = json.loads((actroot/'.act_build_cache.json').read_text(encoding='utf-8'))
                    rel = source.relative_to(actroot).as_posix()
                    # ACT4's cache stores truncated Merkle recipe hashes, not
                    # content hashes. The full DAG is not present in this
                    # Windows checkout, so record the recipe entry as
                    # provenance and bind the actual ELF with SHA-256 below.
                    if rel not in cache:
                        raise ValueError('ACT4 input is absent from build cache: '+rel)
                    detail['oracle_files'] = {}
                    for suffix in ['.sig','.sig.log','.results','.sig.elf']:
                        f = actroot/'build/rv32i'/test['category']/(test['case']+suffix)
                        detail['oracle_files'][str(f)] = sha(f)
                        result['input_hashes'][str(f)] = sha(f)
                        shutil.copyfile(f,case/f.name)
                    detail['oracle_cache_recipe_recorded'] = cache[rel]
                rec,text = native(gcc.parent/'riscv-none-elf-objdump.exe',['-d',elf],run,case/'disassembly.log')
                if rec['return_code'] or re.search(r'^\s*[0-9a-f]+:\s+[0-9a-f]{4}\s+(?!\.)(?:\S+)',text,re.M):
                    raise ValueError('Disassembly failed/16-bit instruction found: '+test['case'])
                detail['no_16bit_instructions_in_disassembly'] = True
            else:
                image = test['image_bytes']
            imagefile = case/'image.bin'
            imagefile.write_bytes(image)
            detail['image_sha256'] = sha(imagefile)
            opts = ['-c','-onfinish','exit','-t','1ps','-voptargs=+acc',
                    "-gTOHOST_ADDR=32'h"+format(detail['tohost'],'08x'),
                    '-gMAX_CYCLES='+str(500 if args.self_test else args.max_cycles),
                    '-gDUAL_ISSUE='+str(args.dual_issue),'-gMINIMAL_CONTROL_CPU='+str(args.minimal_control),
                    'work.tb_triha_isa_official','+MEM_IMAGE='+imagefile.as_posix(),
                    '-l',str(case/'transcript.log'),'-do',str(frozen/'scripts/cpu/run_modelsim.do')]
            rec,text = native(tools/'vsim.exe',opts,run,case/'simulation.log',args.timeout)
            detail['execution'] = rec
            detail['status'] = classify(text,rec['return_code'],test['suite'],rec['timed_out'])
            match = re.search(r'RV32_ISA_(?:PASS|FAIL)[^\n]*cycles=(\d+)',text)
            detail['cycles'] = int(match[1]) if match else None
            if args.self_test:
                detail['expected_status'] = {'monitor-pass':'PASS','monitor-fail':'FAIL','monitor-timeout':'TIMEOUT'}[test['case']]
                detail['monitor_check_pass'] = detail['status']==detail['expected_status']
            save(case/'result.json',detail)
            result['cases'].append(detail)
            checkpoint()
            print(f"{test['suite']} {test['case']} {detail['status']} cycles={detail['cycles']}",flush=True)
        result['status'] = 'PASS' if all(c.get('monitor_check_pass',c['status']=='PASS') for c in result['cases']) else 'FAIL'
    except Exception as e:
        result['status']='ERROR'
        result['error']=f'{type(e).__name__}: {e}'
        print(result['error'],flush=True)
    finally:
        changed = [p for p,h in result['input_hashes'].items() if not Path(p).is_file() or sha(p)!=h]
        result['changed_inputs']=changed
        result['source_unchanged']=not changed
        if changed:
            result['status']='INPUT_CHANGED'
        result['finished_utc']=dt.datetime.now(dt.timezone.utc).isoformat()
        checkpoint()
        print(f"ISA_REGRESSION {result['status']} counts={result['counts']} result={run/'result.json'}",flush=True)
    return 0 if result['status']=='PASS' else 1


if __name__=='__main__':
    sys.exit(main())

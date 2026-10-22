"""Cycle-exact display MMIO comparison against the frozen byte-enable leaf."""
from pathlib import Path
import json,re,subprocess,sys
from common import ROOT,BUILD,fresh_run,input_hashes,run_logged,tool,sha256,write_json

REFERENCE='2c9c67f1797470fe038ec3de9b0cbcb2986b7daa'
LEAF='rtl/video/video_display_mmio.sv'


def ports(source):
    header=source.split(');',1)[0]
    header=re.sub(r'//[^\n]*','',header)
    result=[]
    pattern=r'\b(input|output)\s+(wire|reg)\s*(\[\d+:0\])?\s*(.*?)(?=\b(?:input|output)\s+(?:wire|reg)\b|$)'
    for match in re.finditer(pattern,header,re.S):
        direction,_,width,names=match.groups()
        for name in names.strip().strip(',').split(','):
            name=name.strip()
            if not re.fullmatch(r'\w+',name):raise ValueError('Unsupported miter port '+name)
            result.append((direction,width or '',name))
    if not result or len({p[2] for p in result})!=len(result):raise ValueError('Missing/duplicate miter ports')
    if len(re.findall(r'\b(?:input|output|inout)\b',header))!=len(list(re.finditer(pattern,header,re.S))):
        raise ValueError('Unparsed miter declaration')
    return result


def miter(source):
    interface=ports(source)
    text=source.split(');',1)[0].replace('output reg','output wire')+');\n'
    for direction,width,name in interface:
        if direction=='output':text+=f'wire {width} ref_{name};\n'
    for suffix in ('candidate','reference'):
        text+=f'video_display_mmio_{suffix} #(.EXTERNAL_HEALTH(EXTERNAL_HEALTH)) u_{suffix}(\n'
        text+=',\n'.join(' .'+name+'('+('ref_' if suffix=='reference' and direction=='output' else '')+name+')'
                         for direction,_,name in interface)+');\n'
    text+='integer miter_cycles=0;\nalways @(posedge clk_i) begin #1;\n'
    for direction,_,name in interface:
        if direction=='output':text+=f'if({name} !== ref_{name}) $fatal(1,"SHADOW_MITER_MISMATCH {name} cycle=%0d",miter_cycles);\n'
    text+='miter_cycles=miter_cycles+1;end\nendmodule\n`default_nettype wire\n'
    return text


def main():
    work=fresh_run('shadow_decode');latest=BUILD/'latest_shadow_decode.json'
    result={'status':'running','directory':work.relative_to(ROOT).as_posix(),
            'reference_commit':REFERENCE,'cases':[],'mutations':[],
            'physical_board':False,'timing_closed':False,
            'scope':'All leaf outputs sampled every core cycle on existing MMIO and poisoned-bus byte-store traffic; frozen leaf equivalence, not formal proof or system timing.'}
    write_json(latest,result)
    try:
        manifest='fpga/pg2l100h/project/video_display_mmio.json'
        m=json.loads((ROOT/manifest).read_text(encoding='utf-8'))
        names=m['sources']+m['tests']+[manifest,'tb/video/tb_display_shadow_bytes.sv',
            'rtl/video/include/video_display.vh','rtl/video/include/video_cfg.vh',
            'scripts/video/test_shadow_decode.py','scripts/video/common.py','scripts/video/test_display_driver.py',
            'sw/drivers/video_display.c','sw/include/video_display.h','sw/include/video_display_abi.h',
            'sw/include/video_cfg.h','tb/video/test_display_driver.c']
        result['inputs']=input_hashes(ROOT/n for n in names)
        for n in names:
            p=work/'src'/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((ROOT/n).read_bytes())
        baseline=subprocess.check_output(['git','show',REFERENCE+':'+LEAF],cwd=ROOT)
        reference=baseline.decode('utf-8');candidate=(work/'src'/LEAF).read_text(encoding='utf-8')
        if ports(reference)!=ports(candidate):raise ValueError('MMIO interface changed')
        (work/'reference_original.sv').write_bytes(baseline)
        result['reference_sha256']=sha256(work/'reference_original.sv')
        result['compared_outputs']=[n for d,_,n in ports(candidate) if d=='output']
        result['wrapper_port_count']=len(ports(candidate))
        for suffix,text in [('reference',reference),('candidate',candidate)]:
            text,count=re.subn(r'\bmodule video_display_mmio\b','module video_display_mmio_'+suffix,text)
            if count!=1:raise ValueError('MMIO module anchor changed')
            (work/(suffix+'.sv')).write_text(text,encoding='utf-8',newline='\n')
        (work/'miter.sv').write_text(miter(candidate),encoding='utf-8',newline='\n')
        cc=tool('iverilog');runtime=tool('vvp')
        result['tools']={str(p):sha256(p) for p in (cc,runtime)}
        for name,p in [('iverilog',cc),('vvp',runtime)]:run_logged([p,'-V'],work/(name+'_version.log'))
        run_logged([sys.executable,ROOT/'scripts/video/test_display_driver.py'],work/'driver_cli.log')
        driver=json.loads((BUILD/'latest_display_driver.json').read_text(encoding='utf-8'))
        if driver['status']!='pass' or not driver['native_driver_executed'] or driver['trace_writes']!=163:
            raise ValueError('Native driver trace missing')
        trace=work/'driver_writes.hex';trace.write_bytes((ROOT/driver['trace']).read_bytes())
        result['driver_result']={'path':driver['directory']+'/result.json',
                                 'sha256':sha256(ROOT/driver['directory']/'result.json')}
        common=[work/'src'/n for n in m['sources'] if n!=LEAF]+[work/'reference.sv',work/'miter.sv']
        def compile_run(label,top,tb,source,args=(),negative=False):
            d=work/label;d.mkdir();binary=d/'sim.vvp'
            run_logged([cc,'-g2012','-I',work/'src/rtl/video/include','-s',top,'-o',binary,
                        *common,source,work/'src'/tb],d/'compile.log')
            process=subprocess.run([runtime,binary,*args],cwd=ROOT,capture_output=True,timeout=120)
            log=process.stdout+process.stderr;(d/'run.log').write_bytes(log)
            if negative:
                if process.returncode==0 or b'SHADOW_MITER_MISMATCH' not in log:
                    raise ValueError('Compiled mutation did not trigger cycle comparison: '+label)
            elif process.returncode or (b'DISPLAY_MMIO_PASS' not in log and b'DISPLAY_SHADOW_BYTES_PASS writes=2723 reads=2883' not in log):
                raise ValueError('Miter regression failed '+label+': '+log.decode(errors='replace')[-1500:])
            return {'name':label,'exit_code':process.returncode,'status':'rejected' if negative else 'pass'}
        for case in range(10):
            args=['+CASE='+str(case)]
            if case==9:args+=['+DRIVER_TRACE='+str(trace)]
            result['cases'].append(compile_run('mmio_'+str(case),'tb_video_display_mmio',m['tests'][0],work/'candidate.sv',args))
        result['cases'].append(compile_run('bytes','tb_display_shadow_bytes','tb/video/tb_display_shadow_bytes.sv',work/'candidate.sv'))
        mutations=[('wrong_aw','awaddr<=s_axi_awaddr_i','awaddr<=s_axi_awaddr_i^32\'d1'),
                   ('missing_bvalid','s_axi_bvalid_o<=1','s_axi_bvalid_o<=0'),
                   ('reset_fault_code','assign fault_code_o=error_code;',
                    "assign fault_code_o=rst_ni ? error_code : 8'hff;")]
        for label,anchor,replacement in mutations:
            text=(work/'candidate.sv').read_text(encoding='utf-8')
            if text.count(anchor)!=1:raise ValueError('Mutation anchor changed '+label)
            source=work/(label+'.sv');source.write_text(text.replace(anchor,replacement),encoding='utf-8',newline='\n')
            result['mutations'].append(compile_run(label,'tb_display_shadow_bytes','tb/video/tb_display_shadow_bytes.sv',source,negative=True))
        for n,h in result['inputs'].items():
            if sha256(ROOT/n)!=h or sha256(work/'src'/n)!=h:raise ValueError('Input changed '+n)
        for p,h in result['tools'].items():
            if sha256(p)!=h:raise ValueError('Simulation tool changed')
        if sha256(ROOT/driver['directory']/'result.json')!=result['driver_result']['sha256']:
            raise ValueError('Driver result changed')
        result.update(status='pass',artifacts={p.relative_to(work).as_posix():sha256(p) for p in work.rglob('*') if p.is_file()})
    except Exception as error:
        result.update(status='fail',error=str(error));print(error,file=sys.stderr)
    write_json(work/'result.json',result);write_json(latest,result)
    print('SHADOW_DECODE_'+result['status'].upper()+': '+str(work),flush=True)
    return 0 if result['status']=='pass' else 1


if __name__=='__main__':raise SystemExit(main())

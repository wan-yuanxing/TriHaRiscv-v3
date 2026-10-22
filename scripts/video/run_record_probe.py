"""Native boundary wiring/scan tests plus a real full-size DUT reset/idle smoke."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from common import ROOT, BUILD, fresh_run, input_hashes, run_logged, sha256, tool, write_json
from gen_record_probe import WRAPPER, MANIFEST, interface


def boundary_fixture(source, mapping):
    ports=interface(source)
    inputs=[p['name'] for p in ports if p['direction']=='input' and p['name'] not in
            ('clk_i','rst_ni','pixel_clk','pixel_reset_n')]
    stub=source.split(');',1)[0]+');\n'
    input_bits=sum(p['width'] for p in ports if p['name'] in inputs)
    output_ports=[p for p in ports if p['direction']=='output']
    selectors={p['name']:(i*5)%input_bits for i,p in enumerate(output_ports)}
    if len(set(selectors.values()))!=len(selectors):
        raise ValueError('Output wiring signatures are not unique')
    stub+=f'wire [{input_bits-1}:0] probe_stimulus={{'+','.join(inputs)+'};\n'
    constants={p['name']:int.from_bytes(hashlib.sha256(p['name'].encode()).digest(),'big') &
               ((1<<p['width'])-1) for p in ports if p['direction']=='output'}
    for p in ports:
        if p['direction']=='output':
            stub+=f"assign {p['name']} = {p['width']}'h{constants[p['name']]:x} ^ {{{p['width']}{{probe_stimulus[{selectors[p['name']]}]}}}};\n"
    stub+='endmodule\n'
    tb=['`timescale 1ns/1ps','module tb_record_probe_boundary;',
        'reg clk_i=0,pixel_clk=0,rst_ni=0,pixel_reset_n=0;',
        'integer i,checks=0;']
    for d,b in mapping.items():
        ni,no=b['input_bits'],b['output_bits']
        tb += [f'reg {d}_scan_i=0,{d}_shift_i=0,{d}_capture_i=0;',f'wire {d}_scan_o;',
               f'reg [{ni-1}:0] expected_{d}_input=0;', f'reg [{no-1}:0] expected_{d}_output=0;',
               f'wire [{no-1}:0] expected_{d}_sampled;']
    input_expressions={p['name']:f"expected_{d}_input[{p['offset']} +: {p['width']}]"
                       for d,b in mapping.items() for p in b['inputs']}
    tb += [f'wire [{input_bits-1}:0] expected_stimulus={{'+
           ','.join(input_expressions[n] for n in inputs)+'};']
    for d,b in mapping.items():
        for p in b['outputs']:
            tb += [f"assign expected_{d}_sampled[{p['offset']} +: {p['width']}] = "
                   f"{p['width']}'h{constants[p['name']]:x} ^ {{{p['width']}{{expected_stimulus[{selectors[p['name']]}]}}}};"]
    tb+=['video_record_probe u_probe(.*);','task check_all;begin']
    for d,b in mapping.items():
        for kind in ('input','output'):
            tb += [f'if(u_probe.{d}_{kind}_q !== expected_{d}_{kind}) $fatal(1,"record probe {d} {kind} shift/capture mismatch");']
        tb += [f'if({d}_scan_o !== expected_{d}_output[0]) $fatal(1,"record probe {d} serial output mismatch");']
        for p in b['inputs']:
            tb += [f"if(u_probe.u_pipeline.{p['name']} !== expected_{d}_input[{p['offset']} +: {p['width']}]) $fatal(1,\"record probe input port {p['name']} mismatch\");"]
        for p in b['outputs']:
            expression=f"expected_{d}_sampled[{p['offset']} +: {p['width']}]"
            tb += [f"if(u_probe.{d}_sampled[{p['offset']} +: {p['width']}] !== ({expression})) $fatal(1,\"record probe output port {p['name']} mismatch\");"]
    for n in ('clk_i','rst_ni','pixel_clk','pixel_reset_n'):
        tb += [f'if(u_probe.u_pipeline.{n} !== {n}) $fatal(1,"record probe direct port {n} mismatch");']
    tb+=['checks=checks+1;end endtask']
    for d,b in mapping.items():
        ni,no=b['input_bits'],b['output_bits'];clock=b['clock']
        tb += [f'task tick_{d};reg [{no-1}:0] old_sample;begin',
               f'old_sample=expected_{d}_sampled;',
               f'#3;{clock}=1;',
               f'if({d}_shift_i) expected_{d}_input={{{d}_scan_i,expected_{d}_input[{ni-1}:1]}};',
               f'if({d}_capture_i) expected_{d}_output=old_sample;',
               f"else if({d}_shift_i) expected_{d}_output={{1'b0,expected_{d}_output[{no-1}:1]}};",
               f'#1;check_all();#3;{clock}=0;end endtask']
    tb+=['initial begin rst_ni=1;pixel_reset_n=1;#1;rst_ni=0;pixel_reset_n=0;',
         '#1;check_all();#1;rst_ni=1;pixel_reset_n=1;']
    for d,b in mapping.items():
        tb += [f'{d}_shift_i=1;',f'for(i=0;i<{b["input_bits"]+2};i=i+1) begin',
               f'{d}_scan_i=(i==0);{d}_capture_i=(i%17==0);tick_{d}();end',
               f'{d}_shift_i=0;{d}_capture_i=0;repeat(3) tick_{d}();',
               f'{d}_capture_i=1;tick_{d}();{d}_capture_i=0;']
    for d,b in mapping.items():
        tb += [f'{d}_shift_i=1;{d}_scan_i=0;repeat({b["output_bits"]+2}) tick_{d}();',
               f'{d}_scan_i=1;{d}_capture_i=1;tick_{d}();',
               f'{d}_shift_i=0;{d}_capture_i=0;tick_{d}();']
    tb += ['rst_ni=0;expected_core_input=0;expected_core_output=0;#1;check_all();',
           'pixel_reset_n=0;expected_pixel_input=0;expected_pixel_output=0;#1;check_all();',
           '$display("RECORD_PROBE_BOUNDARY_PASS checks=%0d",checks);$finish;end',
           'initial begin #1000000;$fatal(1,"record probe boundary timeout");end','endmodule','']
    return stub,'\n'.join(tb)


def main():
    work=fresh_run('record_probe_sim')
    result={'status':'running','directory':work.relative_to(ROOT).as_posix(),
            'scope':'Boundary wiring with explicit stub; real full DUT reset/idle and actual display shadow byte stores. No full-pipeline legal-traffic or board claim.',
            'cases':[]}
    latest=BUILD/'latest_record_probe_sim.json';write_json(latest,result)
    try:
        run_logged([sys.executable,ROOT/'scripts/video/gen_record_probe.py','--check'],work/'generated_check.log')
        manifest=json.loads((ROOT/MANIFEST).read_text(encoding='utf-8'))
        names=manifest['sources']+manifest['tests']+manifest['constraints']+[MANIFEST,
            'fpga/pg2l100h/project/video_record_pipeline.json',
            'fpga/pg2l100h/constraints/video_record_pipeline.fdc',
            'rtl/video/include/video_cfg.vh','rtl/video/include/video_capture_v2.vh',
            'rtl/video/include/video_display.vh','scripts/video/run_record_probe.py',
            'scripts/video/gen_record_probe.py','scripts/video/common.py',
            'tb/video/tb_display_shadow_bytes.sv']
        result['inputs']=input_hashes(ROOT/n for n in names)
        for n in names:
            p=work/'src'/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((ROOT/n).read_bytes())
        compiler=tool('iverilog');runtime=tool('vvp')
        result['tools']={name:{'path':str(p),'sha256':sha256(p)} for name,p in
                         [('iverilog',compiler),('vvp',runtime)]}
        stub,tb=boundary_fixture((work/'src/rtl/video/video_record_pipeline.sv').read_text(encoding='utf-8'),manifest['boundary'])
        (work/'stub.sv').write_text(stub,encoding='utf-8',newline='\n');(work/'boundary_tb.sv').write_text(tb,encoding='utf-8',newline='\n')
        original=(work/'src'/WRAPPER).read_text(encoding='utf-8')
        mapping=manifest['boundary']['core']['inputs']
        src=next(p for p in mapping if p['name']=='src_data')
        old=f".src_data(core_input_q[{src['offset']} +: {src['width']}])"
        if original.count(old)!=1 or original.count('else if (core_shift_i)')!=1:
            raise ValueError('Mutation anchor changed')
        cases=[('boundary',original,False),
               ('wrong_input_bit',original.replace(old,old.replace(f"[{src['offset']} +:",f"[{src['offset']+1} +:")),True),
               ('wrong_capture_priority',original.replace('else if (core_shift_i)','if (core_shift_i)'),True)]
        scalar=[next(p for p in manifest['boundary']['core']['outputs'] if p['name']==n)
                for n in ('src_ready','arm_toggle')]
        a,b=[f".{p['name']}(core_sampled[{p['offset']} +: 1])" for p in scalar]
        swapped=original.replace(a,'__SWAP_PORT__').replace(b,b.replace(
            f"[{scalar[1]['offset']} +:",f"[{scalar[0]['offset']} +:")).replace(
            '__SWAP_PORT__',a.replace(f"[{scalar[0]['offset']} +:",f"[{scalar[1]['offset']} +:"))
        cases.append(('swapped_scalar_outputs',swapped,True))
        for label,wrapper,negative in cases:
            directory=work/label;directory.mkdir();path=directory/'probe.sv';path.write_text(wrapper,encoding='utf-8',newline='\n')
            exe=directory/'sim.vvp'
            run_logged([compiler,'-g2012','-I',work/'src/rtl/video/include','-s','tb_record_probe_boundary',
                        '-o',exe,path,work/'stub.sv',work/'boundary_tb.sv'],directory/'compile.log')
            process=subprocess.run([runtime,exe],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
            (directory/'run.log').write_bytes(process.stdout)
            if negative:
                if process.returncode==0 or b'record probe ' not in process.stdout:
                    raise ValueError('Boundary mutation was not detected: '+label)
            elif process.returncode or b'RECORD_PROBE_BOUNDARY_PASS' not in process.stdout:
                raise ValueError('Boundary simulation failed: '+process.stdout.decode(errors='replace'))
            result['cases'].append({'name':label,'status':'rejected' if negative else 'pass',
                                    'exit_code':process.returncode})
        exe=work/'real_idle.vvp'
        run_logged([compiler,'-g2012','-I',work/'src/rtl/video/include','-s','tb_record_probe_idle',
                    '-o',exe]+[work/'src'/n for n in manifest['sources']+manifest['tests']],work/'real_compile.log')
        log=run_logged([runtime,exe],work/'real_idle.log',timeout=60)
        if 'RECORD_PROBE_REAL_IDLE_PASS' not in log:
            raise ValueError('Real DUT smoke did not finish')
        result['cases'].append({'name':'real_default_dut_idle','status':'pass','exit_code':0})
        exe=work/'shadow_bytes.vvp'
        run_logged([compiler,'-g2012','-I',work/'src/rtl/video/include','-s','tb_display_shadow_bytes',
                    '-o',exe]+[work/'src'/n for n in manifest['sources']]+
                   [work/'src/tb/video/tb_display_shadow_bytes.sv'],work/'shadow_compile.log')
        log=run_logged([runtime,exe],work/'shadow_bytes.log',timeout=120)
        if 'DISPLAY_SHADOW_BYTES_PASS writes=2723 reads=2883' not in log:
            raise ValueError('Shadow byte-store regression did not finish')
        result['cases'].append({'name':'shadow_byte_strobes','status':'pass','exit_code':0,
                                'writes':2723,'reads':2883})
        for name,expected in result['inputs'].items():
            if sha256(ROOT/name)!=expected or sha256(work/'src'/name)!=expected:
                raise ValueError('Simulation source changed: '+name)
        for p in (compiler,runtime):
            if sha256(p) != result['tools']['iverilog' if p==compiler else 'vvp']['sha256']:
                raise ValueError('Simulation tool changed')
        result['artifacts']={p.relative_to(work).as_posix():sha256(p) for p in work.rglob('*') if p.is_file()}
        result['status']='pass'
    except Exception as error:
        result.update(status='fail',error=str(error));print(str(error),file=sys.stderr)
    write_json(work/'result.json',result);write_json(latest,result)
    print('VIDEO_RECORD_PROBE_SIM_'+result['status'].upper()+': '+str(work))
    return 0 if result['status']=='pass' else 1


if __name__=='__main__': raise SystemExit(main())

"""Extract actual kept address LUT chains; check enable-qualified equivalence."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]
SIM=Path('D:/modeltech64_2020.4/win64')


def extract(path,label):
    text=path.read_text(encoding='utf-8')
    start=text.index('// Native write-address minimum delay')
    end=text.index('        wire [23:0] write_metadata',start)
    block=text[start:end]
    return 'module address_'+label+''' #(parameter BLOCK=0)(input [7:0] write_row_i,input rst_i,write_i,output [4:0] address_o);
localparam block_index=BLOCK;
wire metadata_we=write_i && write_row_i[7:5]==block_index;
genvar address_bit;
generate
'''+block+'\nendgenerate\nassign address_o=write_address_w;\nendmodule\n'


def main():
    p=argparse.ArgumentParser();p.add_argument('parent',type=Path);p.add_argument('candidate',type=Path);p.add_argument('output',type=Path);p.add_argument('--old',action='store_true');a=p.parse_args()
    out=a.output.resolve();assert out.is_relative_to(ROOT/'build/cpu');out.mkdir(parents=True,exist_ok=False)
    config=ROOT/'config/cpu_primitives.json';cfg=json.loads(config.read_text())
    models=[Path(i['path']) for i in cfg['simulation_models']]
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    for i in cfg['simulation_models']:assert sha(Path(i['path']))==i['sha256']
    tb=ROOT/'tb/cpu/tb_btb_address_control.v'
    inputs=[a.parent,a.candidate,config,tb,Path(__file__).resolve(),*models]
    r=dict(status='RUNNING',input_hashes={str(p.resolve()):sha(p) for p in inputs},commands=[])
    try:
        (out/'chains.v').write_text(extract(a.parent,'parent')+extract(a.candidate,'candidate'),encoding='utf-8',newline='\n')
        calls=[('vlib','vlib.exe',['work'],None),('compile','vlog.exe',['chains.v',str(tb),*map(str,models)],None),
               ('semantic','vsim.exe',['-c','tb_btb_address_control','-do','run -all; quit -f'],False),
               ('control','vsim.exe',['-c','tb_btb_address_control','+POISON_CONTROL','-do','run -all; quit -f'],a.old),
               ('negative','vsim.exe',['-c','tb_btb_address_control','+FAULT_ADDRESS','-do','run -all; quit -f'],True)]
        for label,tool,args,fail in calls:
            command=[str(SIM/tool),*args];v=subprocess.run(command,cwd=out,capture_output=True,timeout=120)
            log=v.stdout+v.stderr;(out/(label+'.log')).write_bytes(log);r['commands'].append(dict(command=command,return_code=v.returncode))
            assert v.returncode==0,label+' tool failure'
            if fail is not None:
                assert (b'BTB_ADDRESS_FAIL' in log)==fail,label
                if not fail:assert b'BTB_ADDRESS_PASS' in log,label
        assert all(sha(Path(n))==h for n,h in r['input_hashes'].items())
        r['status']='PASS'
    except Exception as e:r.update(status='FAIL',error=str(e));raise
    finally:
        r['output_hashes']={p.name:sha(p) for p in out.iterdir() if p.is_file()}
        (out/'result.json').write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('BTB_ADDRESS_CHECK_PASS',out)


if __name__=='__main__':main()

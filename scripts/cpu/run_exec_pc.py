"""Native ModelSim whole-execute-unit miter and genuine output-fault rejection."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]
SIM=Path('D:/modeltech64_2020.4/win64')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--broken',action='store_true')
    args=parser.parse_args()
    work=ROOT/'build/cpu'/('exec-pc-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    result=dict(status='RUNNING',broken=args.broken,directory=str(work),input_hashes={},tool_hashes={},commands=[],source_unchanged=False)
    print('EXEC_PC_RUN',work,flush=True)
    try:
        names=['rtl/cpu/triha_exec.v','rtl/cpu/vendor/src/core/biriscv_exec.v',
               'rtl/cpu/vendor/src/core/biriscv_alu.v','rtl/cpu/vendor/src/core/biriscv_defs.v',
               'tb/cpu/tb_exec_pc.v','scripts/cpu/run_exec_pc.py','scripts/cpu/run_modelsim.do']
        for name in names:
            source=ROOT/name;target=work/'src'/name
            result['input_hashes'][name]=sha(source)
            target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(source.read_bytes())
        def native(name,arguments,label):
            exe=SIM/name;result['tool_hashes'][str(exe)]=sha(exe)
            command=[str(exe),*map(str,arguments)]
            p=subprocess.run(command,cwd=work,capture_output=True,timeout=90,creationflags=subprocess.CREATE_NO_WINDOW)
            (work/(label+'.log')).write_bytes(p.stdout+p.stderr)
            result['commands'].append(dict(command=command,return_code=p.returncode))
            if p.returncode:raise RuntimeError(label+' returned '+str(p.returncode))
            return (p.stdout+p.stderr).decode('utf-8',errors='replace')
        native('vmap.exe',['-c'],'vmap');native('vlib.exe',['work'],'vlib')
        native('vlog.exe',['+incdir+'+str(work/'src/rtl/cpu/vendor/src/core'),
            *[work/'src'/n for n in names if n.endswith('.v')]],'compile')
        text=native('vsim.exe',['-c','work.tb_exec_pc','-gBROKEN='+str(int(args.broken)),
            '-do','do {'+str(work/'src/scripts/cpu/run_modelsim.do')+'}'],'simulation')
        if 'EXEC_PC_PASS' not in text or 'EXEC_PC_FAIL' in text:raise RuntimeError('execute-unit miter rejected output; see simulation.log')
        result['status']='PASS'
    except (OSError,RuntimeError,subprocess.TimeoutExpired) as error:
        result.update(status='FAIL',error=str(error))
    finally:
        result['source_unchanged']=all(sha(ROOT/n)==d for n,d in result['input_hashes'].items())
        result['output_hashes']={str(p.relative_to(work)).replace('\\','/'):sha(p) for p in work.rglob('*') if p.is_file() and p.name!='result.json'}
        (work/'result.json').write_bytes((json.dumps(result,indent=2)+'\n').encode('utf-8'))
    print('EXEC_PC',result['status'],result.get('error',''))
    return 0 if result['status']=='PASS' and result['source_unchanged'] else 1


if __name__=='__main__':raise SystemExit(main())

"""P0-1/P0-2 public-port CSR/LSU regression, frozen native Windows ModelSim inputs."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SIM = Path('D:/modeltech64_2020.4/win64')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=['red', 'green'], required=True)
    args = parser.parse_args()
    work = ROOT/'build/cpu'/('document-csr-'+args.phase+'-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    row = dict(status='RUNNING', phase=args.phase, commands=[], input_hashes={}, tools={}, cases=[],
               scope='Public CSR and LSU ports; no PDS/timing/board acceptance')
    def save():
        (work/'result.json').write_text(json.dumps(row, indent=2)+'\n', encoding='utf-8')
    def native(tool, options, label, cwd):
        exe = SIM/(tool+'.exe')
        row['tools'][str(exe)] = sha(exe)
        cmd = [str(exe), *map(str, options)]
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=90,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        log = work/(label+'.log')
        log.write_bytes(result.stdout+result.stderr)
        row['commands'].append(dict(command=cmd, cwd=str(cwd), return_code=result.returncode, log=log.name, sha256=sha(log)))
        return result.returncode, log.read_text(encoding='utf-8', errors='replace')
    save()
    try:
        if (ROOT/'config/cpu_admission.json').is_file():
            from admission_common import validate
            validate()
            row['admission_validated'] = True
        regfile = 'rtl/cpu/triha_csr_regfile.v'
        if not (ROOT/regfile).is_file():
            regfile = 'rtl/cpu/vendor/src/core/biriscv_csr_regfile.v'
        sources = [regfile, 'rtl/cpu/triha_csr.v', 'rtl/cpu/triha_lsu.v', 'tb/cpu/tb_document_csr.v']
        names = sources+['rtl/cpu/vendor/src/core/biriscv_defs.v', 'scripts/cpu/run_modelsim.do',
                         'scripts/cpu/run_document_csr.py', 'rtl/cpu/ADAPTATIONS.json', 'rtl/cpu/vendor/UPSTREAM.json']
        if (ROOT/'config/cpu_admission.json').is_file():
            names += ['config/cpu_admission.json', 'scripts/cpu/admission_common.py']
        for name in names:
            dest = work/'src'/name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/name,dest)
            row['input_hashes'][name] = sha(dest)
        native('vsim',['-version'],'version',work)
        for sim in [0,1,2]:
            folder=work/('sim'+str(sim)); folder.mkdir()
            for tool, opts in [('vmap',['-c']),('vlib',['work']),('vlog',
                [*(['+define+verilog_sim'] if sim==1 else (['+define+TRIHA_SIM_CTRL_EXTERNAL'] if sim==2 else [])), '+incdir+'+(work/'src/rtl/cpu/vendor/src/core').as_posix(),
                 *[(work/'src'/s).as_posix() for s in sources]])]:
                code, out=native(tool,opts,f'sim{sim}-{tool}',folder)
                if code or '** Error' in out: raise RuntimeError('compile/setup failed: '+tool)
            for super_mode in [0,1]:
                code,out=native('vsim',['-c','-onfinish','exit','-gSUPER='+str(super_mode),
                    '-gSIM_CONTROL='+str(sim),'work.tb_document_csr','-do',(work/'src/scripts/cpu/run_modelsim.do').as_posix()],
                    f'sim{sim}-super{super_mode}',folder)
                ok=code==0 and 'DOC_CSR_PASS' in out and 'DOC_CSR_FAIL' not in out and '** Error' not in out
                row['cases'].append(dict(sim_control=sim, support_super=super_mode,status='PASS' if ok else 'FAIL',
                    summary=[line for line in out.splitlines() if 'DOC_CSR_SUMMARY' in line]))
                save()
        row['status']='PASS' if all(c['status']=='PASS' for c in row['cases']) else 'FAIL'
    except Exception as error:
        row.update(status='FAIL',error=str(error))
    row['source_unchanged']=all(sha(ROOT/p)==h for p,h in row['input_hashes'].items())
    if not row['source_unchanged']: row.update(status='FAIL', error='inputs changed during run')
    row['output_hashes']={p.relative_to(work).as_posix():sha(p) for p in work.rglob('*.log')}
    save()
    print(row['status'],work/'result.json',row.get('error',''),flush=True)
    return 0 if row['status']=='PASS' else 1


if __name__=='__main__':
    sys.exit(main())

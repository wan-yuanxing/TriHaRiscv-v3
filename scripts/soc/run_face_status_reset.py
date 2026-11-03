"""Check real SoC status reset ownership, with prior-connection mutations."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'video'))
from common import ROOT, tool, sha256, write_json


def run(out, baseline):
    out = out.resolve(); out.mkdir(parents=True, exist_ok=False)
    names = ['rtl/soc/triha_face_system.v', 'tb/soc/tb_face_status_reset.sv',
             'rtl/soc/include/avatar_preset.vh',
             'scripts/soc/run_face_status_reset.py']
    hashes = {}
    for name in names:
        src = ROOT/name; dst = out/src.name
        dst.write_bytes(src.read_bytes()); hashes[name] = sha256(src)
    source = (out/'triha_face_system.v').read_text()
    cases = [('baseline', source, 1, 1, 'IRQ_ESCAPED_LOCAL_RESET'),
             ('baseline_fault', source, 1, 2, 'FAULT_ESCAPED_LOCAL_RESET')] if baseline else [
                 ('phase_'+str(phase), source, phase, 0, None) for phase in (1, 3, 7)]
    if not baseline:
        for label,clk,reset,signal,which,marker in [
            ('irq', 'compute_clk_i', 'compute_reset_n', 'video_irq_sync', 1, 'IRQ_ESCAPED_LOCAL_RESET'),
            ('fault', 'video_clk_i', 'video_reset_n', 'compute_fault_sync', 2, 'FAULT_ESCAPED_LOCAL_RESET')]:
            before=f'always @(posedge {clk} or negedge {reset})\n        if(!{reset}){signal}'
            after=f'always @(posedge {clk} or negedge rst_ni)\n        if(!rst_ni){signal}'
            assert source.count(before)==1
            cases.append(('negative_'+label, source.replace(before,after), 1, which, marker))
    result={'status':'RUNNING','scope':__doc__,'source_sha256':hashes,'cases':[]}
    write_json(out/'result.json',result)
    try:
        for name,text,phase,which,marker in cases:
            dut=out/(name+'.v');dut.write_text(text)
            binary=out/(name+'.vvp')
            cp=subprocess.run([str(tool('iverilog')),'-g2012','-i','-I',str(out),'-s','tb_face_status_reset',
                '-Ptb_face_status_reset.PHASE='+str(phase),'-o',str(binary),str(dut),
                str(out/'tb_face_status_reset.sv')],capture_output=True,text=True,timeout=60)
            (out/(name+'.compile.log')).write_text(cp.stdout+cp.stderr)
            assert cp.returncode==0,cp.stderr
            cp=subprocess.run([str(tool('vvp')),str(binary),'+CASE='+str(which)],capture_output=True,text=True,timeout=60)
            log=cp.stdout+cp.stderr;(out/(name+'.log')).write_text(log)
            assert (cp.returncode!=0 and marker in log) if marker else (cp.returncode==0 and 'FACE_STATUS_RESET_PASS' in log),log
            result['cases'].append({'name':name,'expected_rejection':marker,'exit_code':cp.returncode})
        assert all(sha256(ROOT/n)==h and sha256(out/Path(n).name)==h for n,h in hashes.items())
        result['status']='NEGATIVE_CONFIRMED' if baseline else 'PASS'
    except Exception as e:
        result.update(status='FAIL',error=str(e))
    write_json(out/'result.json',result);print(result['status'],result.get('error',''))
    return int(result['status']=='FAIL')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--baseline',action='store_true')
    a=p.parse_args();sys.exit(run(a.output,a.baseline))

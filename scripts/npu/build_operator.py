"""Explicit isolated PDS implementation; preserve failed timing as failed evidence."""
import argparse,hashlib,json,re,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
from frozen_inputs import FrozenInputs
ROOT=Path(__file__).resolve().parents[2]
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def mapping_completed(text):
    return re.search(r'(?m)^Executing : dev_map(?: -detail)? successfully\.\s*$',text) is not None

def require(condition, message):
    if not condition:raise RuntimeError(message)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--stage',choices=('map','route'),default='route');args=parser.parse_args()
    out=ROOT/'build/npu'/datetime.now(timezone.utc).strftime('pds-%Y%m%dT%H%M%S_%fZ');out.mkdir(parents=True)
    result={'status':'RUNNING','directory':str(out),'stage':args.stage,'commands':[],'scope':'registered-boundary scalar operator component; no CPU/DDR/CDC/board/system signoff'}
    guard=None
    def run(cmd,name,timeout=900):
        if guard:guard.verify()
        log=out/(name+'.log')
        try:
            with log.open('w',encoding='utf-8') as f:p=subprocess.run([str(x) for x in cmd],cwd=out,stdout=f,stderr=subprocess.STDOUT,timeout=timeout)
        finally:
            if guard:guard.verify()
        result['commands'].append({'argv':[str(x) for x in cmd],'exit_code':p.returncode,'log':str(log),'sha256':sha(log)})
        text=log.read_text(encoding='utf-8',errors='replace')
        if p.returncode or re.search(r'(?m)^\s*E:',text):raise RuntimeError(name+' failed: '+text[-2000:])
        return text
    try:
        manifest_path=ROOT/'fpga/pg2l100h/project/npu_operator_probe.json'
        manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
        names=manifest['sources']+manifest['constraints']+['rtl/npu/include/npu_regs.vh','sw/include/npu_regs.h','config/npu_regs.json','scripts/npu/gen_regs.py','scripts/npu/build_operator.py','scripts/npu/frozen_inputs.py','fpga/pg2l100h/project/npu_operator_probe.json']
        guard=FrozenInputs(ROOT,out/'src',names)
        result['input_sha256']=guard.inputs
        run([sys.executable,out/'src/scripts/npu/gen_regs.py','--check'],'registers')
        shell=Path('D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe');guard.track(shell)
        result['tool']={'path':str(shell),'sha256':sha(shell)}
        run([shell,'-version'],'version',30)
        lines=['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
        lines+=['add_design {'+(out/'src'/p).as_posix()+'}' for p in manifest['sources']]
        lines+=['add_constraint {'+(out/'src'/p).as_posix()+'}' for p in manifest['constraints']]
        lines+=['compile -top_module npu_operator_probe -include_path {'+(out/'src/rtl/npu/include').as_posix()+'}', 'synthesize -ads','dev_map -detail']
        if args.stage=='route':lines+=['pnr -optimize_multi_corner_timing -fix_hold_violation','report_timing']
        lines+=['exit'];script=out/'build.tcl';script.write_text('\n'.join(lines)+'\n',encoding='utf-8')
        text=run([shell,'-file',script,'-work_dir',out,'-project_name','npu_operator_probe'],'implementation')
        require(mapping_completed(text),'missing mapping completion')
        resource=out/'device_map/run.log';result['resources_with_probe']={k:float(v) for k,v in re.findall(r'\| (LUT|FF|DRM|APM|GPLL)\s+\| ([0-9.]+)',resource.read_text(encoding='utf-8'))}
        result['timing_closed']=False
        if args.stage=='route':
            require('Executing : report_timing successfully.' in text,'missing final timing report')
            report=out/'report_timing/npu_operator_probe.rtr';timing=report.read_text(encoding='utf-8');rows={}
            for kind in ('Setup','Hold'):
                for corner in ('Slow','Fast'):
                    block=timing.split(kind+' Summary('+corner+' Corner):',1)[1].split('====',1)[0]
                    m=re.search(r'core_clk\s+core_clk\s+([-\d.]+)\s+([-\d.]+)\s+(\d+)\s+(\d+)',block)
                    require(m is not None,'missing timing row')
                    rows[kind+'_'+corner]={'worst_slack_ns':float(m[1]),'tns_ns':float(m[2]),'failing_endpoints':int(m[3]),'endpoints':int(m[4])}
            require(re.search(r'core_clk\s+10\.0000',timing) is not None,'clock period mismatch')
            result['timing']=rows;result['timing_report']={'path':str(report),'sha256':sha(report)}
            result['timing_closed']='Design Summary : All Constraints Met.' in timing and all(r['worst_slack_ns']>=0 and r['failing_endpoints']==0 and r['endpoints']>0 for r in rows.values())
        guard.verify()
        result['source_unchanged']=True;result['status']='PASS' if args.stage=='map' or result['timing_closed'] else 'TIMING_FAIL'
    except Exception as e:result['status']='FAIL';result['error']=str(e);print(str(e),file=sys.stderr)
    result['artifacts_sha256']={str(p.relative_to(out)):sha(p) for p in out.rglob('*') if p.is_file() and p.name!='result.json'}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(result['status'],out/'result.json',flush=True)
    return 0 if result['status']=='PASS' else 2 if result['status']=='TIMING_FAIL' else 1
if __name__=='__main__':raise SystemExit(main())

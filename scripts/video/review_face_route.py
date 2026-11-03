"""Create immutable, source-bound reports from a completed BOX route."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys,time
root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'scripts/video'))
from build_pds import verify_build_inputs,tcl_path
from face_timing import parse_tables,require_routed_report,gray_bounds,audit_paths
from face_route_evidence import route_record
from face_gray_netlist import load_evidence
parser=argparse.ArgumentParser(description=__doc__)
for name in ('base','route','output'):parser.add_argument('--'+name,type=Path,required=True)
parser.add_argument('--pds',type=Path,default=Path('D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe'))
args=parser.parse_args()
base=args.base.resolve();route=args.route.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
q=tcl_path
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
tool=args.pds.resolve()
result={'status':'RUNNING','scope':'Routed timing and actual-site evidence; no bitstream or board acceptance implied','started':time.time()}
def save(): (out/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
def run(name,lines):
    work=out/name;work.mkdir()
    script=work/'run.tcl';script.write_text('\n'.join(['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']+lines)+'\n',encoding='utf-8')
    with (work/'console.log').open('wb') as log:
        proc=subprocess.Popen([str(tool),'-file',str(script),'-work_dir',str(work),'-project_name',name],cwd=work,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        result['active']={'name':name,'pid':proc.pid};save()
        try:rc=proc.wait(timeout=600)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True,timeout=30);proc.wait(timeout=30);raise
    if rc: raise RuntimeError(name+' failed: '+str(rc))
    return work
try:
    br=json.loads((base/'result.json').read_text(encoding='utf-8'));rr=route_record(route)
    if rr['status']!='ROUTE_REVIEW_READY':raise RuntimeError('Route has not completed')
    verify_build_inputs(base,br)
    for name,digest in rr['inputs'].items():
        if sha(Path(name))!=digest:raise RuntimeError('Changed route input: '+name)
    db=Path(rr['routed_db'])
    if sha(db)!=rr['routed_db_sha256']:raise RuntimeError('Changed route DB')
    result['route_evidence']=rr
    result['inputs']={str(p):sha(p) for p in [Path(__file__),tool,base/'result.json',Path(rr['record_path']),db,root/'scripts/video/face_timing.py',root/'scripts/video/face_gray_netlist.py',root/'scripts/video/face_route_evidence.py',base/'compile/triha_face_board_top_comp.adf',base/'synthesize/triha_face_board_top_syn.adf',base/'device_map/triha_face_board_top_map.adf']}
    work=run('timing',['report_timing -force_to_run -input_db_file '+q(db)+' -max_path 128 -nworst 1 -report_max_skew -report_io_datasheet'])
    report=work/'report_timing/triha_face_board_top.rtr';text=report.read_text(encoding='utf-8')
    require_routed_report(text,db.as_posix());result['timing']=parse_tables(text)
    result['paths']=audit_paths(text,result['timing'])
    result['report']={'path':str(report),'sha256':sha(report)};save()
    work=run('sites',['generate_constraint -db '+q(db)+' -compile_db '+q(base/'compile/triha_face_board_top_comp.adf')+' -synthesize_db '+q(base/'synthesize/triha_face_board_top_syn.adf')+' -devmap_db '+q(base/'device_map/triha_face_board_top_map.adf')+' -file '+q(out/'sites/sites.pcf')])
    sites=work/'sites.pcf';result['sites']={'path':str(sites),'sha256':sha(sites)}
    fdc=(base/'src/fpga/pg2l100h/constraints/triha_face_cdc.fdc').read_text(encoding='utf-8')
    physical=sites.read_text(encoding='utf-8')
    try:
        result['gray']=gray_bounds(text,fdc,physical)
    except ValueError as error:
        if str(error)!='Gray physical buffer requires native netlist identity proof':raise
        work=run('netlist',['gen_netlist -force_to_run -input_db_file '+q(db)+' -func_sim_only'])
        netlist=work/'generate_netlist/triha_face_board_top_sim.v'
        model=tool.parent.parent/'arch/vendor/pango/verilog/bsim/V_BUF.v'
        result['gray_netlist']=dict(routed_db_sha256=sha(db),
            netlist=dict(path=str(netlist),sha256=sha(netlist)),model=dict(path=str(model),sha256=sha(model)))
        for path in (netlist,model,work/'run.tcl',work/'console.log'):
            result['inputs'][str(path)]=sha(path)
        proof=load_evidence(result['gray_netlist'],rr['routed_db_sha256'])
        result['gray']=gray_bounds(text,fdc,physical,proof)
    verify_build_inputs(base,br)
    for name,digest in result['inputs'].items():
        if sha(Path(name))!=digest:raise RuntimeError('Review input changed: '+name)
    result['status']='REPORTS_READY' if result['timing']['all_tables_met'] else 'TIMING_FAILED'
except Exception as e:result.update(status='FAIL',error=str(e))
finally:result.pop('active',None);result['elapsed']=time.time()-result['started'];save()
print(result['status'],result.get('error',''),flush=True)

raise SystemExit(0 if result['status']=='REPORTS_READY' else 1)

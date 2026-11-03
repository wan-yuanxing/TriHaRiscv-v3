"""Bound all Gray crossing arrival windows using routed clock and data delays.

For each group and corner, the relative arrival spread is bounded by source
clock spread + nonnegative datapath-delay upper bound + destination clock
spread. Both early/late clock models and all 116 bits are required. This
conservative check does not depend on PDS's omitted max-skew summary.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
from face_timing import field, path_blocks, finite


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(text, groups, stages):
    source_cells={p['start'] for g in groups for p in g['paths']}
    meta_cells={p['end'] for g in groups for p in g['paths']}
    observations={}
    for block in path_blocks(text):
        if field(block,'Path Class')!='sequential timing path': continue
        typ=re.fullmatch(r'(max|min) \((slow|fast) corner\)',field(block,'Path Type'))
        if not typ: raise ValueError('Unknown clock-path type')
        start=field(block,'Startpoint').removesuffix('/CLK')
        end=field(block,'Endpoint').removesuffix('/D')
        if end in source_cells:
            role,cell,label='source',end,'Capture Clock Delay'
        elif start in meta_cells and stages.get(start)==end:
            role,cell,label='destination',start,'Launch Clock Delay'
        else: continue
        clocks=re.findall(r'^\s*Clock (\S+) \((?:rising|falling) edge\)',block,re.M)
        if len(clocks)!=2 or clocks[0]!=clocks[1]:
            raise ValueError('Clock query must use a local synchronous data path')
        key=(role,cell,typ[2],typ[1])
        if key in observations: raise ValueError('Duplicate clock observation')
        values=re.findall(r'^[ \t]*'+label+r'\s*:\s*([^\n]+)',block,re.M)
        if len(values)!=1: raise ValueError('Missing/duplicate '+label)
        delay=finite(values[0])
        if delay<0: raise ValueError('Unexpected negative clock delay')
        observations[key]=dict(delay_ns=delay,clock=clocks[1])
    expected={(role,cell,c,t) for role,cells in [('source',source_cells),('destination',meta_cells)]
              for cell in cells for c in ('slow','fast') for t in ('max','min')}
    if set(observations)!=expected:
        missing=expected-set(observations)
        raise ValueError('Missing clock bit/corner/early-late coverage: '+str(sorted(missing)[:4])+', total '+str(len(missing)))
    result=[]
    for group in groups:
        sources={p['start'] for p in group['paths']};destinations={p['end'] for p in group['paths']}
        corners={}
        for corner in ('slow','fast'):
            components={}
            for role,cells in [('source',sources),('destination',destinations)]:
                values=[observations[(role,cell,corner,t)] for cell in cells for t in ('max','min')]
                if len({x['clock'] for x in values})!=1: raise ValueError('A Gray group spans different source/destination clocks')
                lo=min(x['delay_ns'] for x in values);hi=max(x['delay_ns'] for x in values)
                components[role]=dict(clock=values[0]['clock'],min_ns=lo,max_ns=hi,spread_bound_ns=hi-lo+0.002)
            data=max(p['upper_bound_ns'] for p in group['paths'] if p['corner']==corner)
            upper=data+sum(v['spread_bound_ns'] for v in components.values())
            if upper>=group['limit_ns']: raise ValueError('Clock-inclusive Gray skew bound exceeds constraint')
            corners[corner]=dict(clocks=components,datapath_bound_ns=data,relative_arrival_spread_bound_ns=upper)
        result.append(dict(constraint=group['constraint'],bits=group['bits'],limit_ns=group['limit_ns'],corners=corners))
    return dict(status='PASS_CONSERVATIVE_CLOCK_AND_DATA_BOUND',bits=len(source_cells),
                clock_observations=len(observations),groups=result,
                native_max_skew_report=False,all_bits_both_corners_early_late=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--review',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--report',type=Path,help='Reanalyze an existing native query bound to the same routed DB')
    parser.add_argument('--pds',type=Path,default=Path('D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe'))
    args=parser.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    receipt=dict(status='RUNNING',started=time.time(),scope=__doc__)
    def save(): (out/'result.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    try:
        review=json.loads(args.review.read_text(encoding='utf-8'));groups=review['gray']['groups']
        dbs=[Path(p) for p in review['inputs'] if p.endswith('_pnr.adf')]
        if len(dbs)!=1: raise ValueError('Expected one routed DB')
        db=dbs[0]
        if sha(db)!=review['inputs'][str(db)]: raise ValueError('Routed DB changed')
        sites=Path(review['sites']['path'])
        if sha(sites)!=review['sites']['sha256']: raise ValueError('Site export changed')
        site_cells=re.findall(r'^def_inst_site \{([^}]+)\}',sites.read_text(encoding='utf-8'),re.M)
        logical={re.sub(r'/opit_\d+(?:_inv)?$','',n):n for n in site_cells}
        stages={};pins=set()
        for group in groups:
            for p in group['paths']:
                pins.add(p['start']+'/D')
                meta=re.sub(r'/opit_\d+(?:_inv)?$','',p['end'])
                nxt=meta.replace('gray_rd_sync1[','gray_rd_sync2[').replace('gray_wr_sync1[','gray_wr_sync2[').replace('gray_meta[','gray_sync[')
                if nxt==meta or nxt not in logical: raise ValueError('Missing mapped second Gray synchronizer')
                stages[p['end']]=logical[nxt];pins.add(logical[nxt]+'/D')
        q=lambda p:'{'+str(p).replace('\\','/')+'}'
        script=out/'query.tcl'
        script.write_text('set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676\n'
            +'report_timing -force_to_run -input_db_file '+q(db)+' -max_path 512 -nworst 1 -to {'
            +' '.join(q(p) for p in sorted(pins))+'}\n',encoding='utf-8')
        receipt['inputs']={str(p.resolve()):sha(p) for p in [args.review,db,sites,script,Path(__file__),args.pds]}
        if args.report:
            report=args.report.resolve()
            receipt['inputs'][str(report)]=sha(report)
        else:
            with (out/'console.log').open('wb') as log:
                process=subprocess.Popen([str(args.pds),'-file',str(script),'-work_dir',str(out),'-project_name','gray_clocks'],cwd=out,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
                receipt['pid']=process.pid;save()
                try: code=process.wait(timeout=600)
                except subprocess.TimeoutExpired:
                    subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],capture_output=True,timeout=30)
                    process.wait(timeout=30);raise
            if code: raise RuntimeError('Clock query failed')
            report=out/'report_timing/triha_face_board_top.rtr'
        text=report.read_text(encoding='utf-8')
        if re.findall(r'^\| Input\s*\|\s*(.+?)\s*$',text,re.M)!=[db.as_posix()]:
            raise ValueError('Clock report belongs to a different database')
        receipt['report']={'path':str(report),'sha256':sha(report)}
        receipt['analysis']=audit(text,groups,stages)
        for name,digest in receipt['inputs'].items():
            if sha(Path(name))!=digest: raise ValueError('Clock-review input changed: '+name)
        receipt['status']='PASS'
    except Exception as e: receipt.update(status='FAIL',error=str(e))
    finally: receipt['elapsed']=time.time()-receipt['started'];save()
    print(receipt['status'],receipt.get('error',''),flush=True)
    return 0 if receipt['status']=='PASS' else 1


if __name__=='__main__': raise SystemExit(main())

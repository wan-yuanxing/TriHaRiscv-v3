"""Cycle equivalence against a hash-checked pre-change synthesis snapshot."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from frozen_inputs import FrozenInputs
from run_b03_frame import ROOT, VENDOR, VENDOR_FILES, common, check_log, need


def run(args):
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    result=dict(status='RUNNING',board_verified=False,legacy_capacity=args.legacy_capacity)
    frozen=None
    try:
        prefix='rtl/npu/upstream/b03/rtl/platform/'
        names=(ROOT/'config/npu_b03_sources.f').read_text(encoding='utf-8').splitlines()
        names+=['tb/npu/tb_b03_quant_capacity.sv','scripts/npu/run_b03_quant_capacity.py',
                'scripts/npu/frozen_inputs.py','scripts/npu/run_b03_frame.py','scripts/video/common.py']
        frozen=FrozenInputs(ROOT,out/'inputs',names)
        refmeta=json.loads((args.reference/'result.json').read_text(encoding='utf-8'))
        vendors=[]
        for name in VENDOR_FILES:
            target=out/'vendor'/name;frozen.external(VENDOR/name,target);vendors.append(target)
        vsim=common.tool('vsim');frozen.track(vsim)
        sources=vendors+[frozen.directory/n for n in names if n.endswith(('.v','.sv'))]
        for lanes in (1,2):
            module='b03_quant8_tdm'+str(lanes);name=prefix+module+'.v'
            lane_sources=list(sources)
            if args.candidate_dir:
                candidate=out/'candidate'/(module+'.v')
                frozen.external(args.candidate_dir/(module+'.v'),candidate)
                lane_sources=[candidate if p==frozen.directory/name else p for p in lane_sources]
            target=out/(module+'_original.v');frozen.external(args.reference/'src'/name,target)
            need(hashlib.sha256(target.read_bytes()).hexdigest()==refmeta['inputs'][name],'reference hash')
            raw=target.read_text(encoding='utf-8')
            need(raw.count('module '+module+'(')==1,'reference module')
            ref=out/(module+'_reference.v')
            ref.write_text(raw.replace('module '+module+'(','module '+module+'_reference('),encoding='utf-8');frozen.track(ref)
            script='onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\n'
            if lanes==1:script+='vlib work\n'
            script+='vlog -sv +define+DUT='+module+' +define+REFERENCE='+module+'_reference'
            if args.legacy_capacity:script+=' +define+LEGACY_CAPACITY'
            script+=' '+' '.join('{'+p.as_posix()+'}' for p in lane_sources+[ref])+'\n'
            script+='vsim -t 1ps work.tb_b03_quant_capacity\nrun -all\nquit -code 0 -force\n'
            do=out/(module+'.do');do.write_text(script,encoding='utf-8');frozen.track(do)
            log=out/(module+'.log')
            with log.open('wb') as stream:
                proc=subprocess.run([str(vsim),'-c','-do',do.name],cwd=out,stdout=stream,
                    stderr=subprocess.STDOUT,timeout=180,creationflags=subprocess.CREATE_NO_WINDOW)
            text=log.read_text(encoding='utf-8',errors='replace')
            need(proc.returncode==0,text[-2500:]);check_log(text,['PASS B03_QUANT_CAPACITY checks=40000'])
            result[module]=next(x for x in text.splitlines() if 'PASS B03_QUANT_CAPACITY' in x)
        frozen.verify();result['status']='PASS'
    except Exception as exc:result.update(status='FAIL',error=str(exc))
    if frozen:
        result.update(source_sha256=frozen.inputs,external_sha256=frozen.external_inputs,tracked_sha256=frozen.tracked)
        try:frozen.verify();result['inputs_unchanged']=True
        except Exception as exc:result.update(status='FAIL',error=str(exc),inputs_unchanged=False)
    common.write_json(out/'result.json',result)
    print(result['status'],out,result.get('error',''),flush=True)
    return int(result['status']!='PASS')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--reference',type=Path,default=ROOT/'build/video/pds/20261101T050627_702707Z')
    parser.add_argument('--legacy-capacity',action='store_true')
    parser.add_argument('--candidate-dir',type=Path)
    sys.exit(run(parser.parse_args()))

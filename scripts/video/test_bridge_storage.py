"""Independent bridge fault/byte scoreboards and optional storage mapping probe."""
import argparse
from pathlib import Path
import subprocess
import sys
sys.path[:0]=[str(Path(__file__).resolve().parents[1]/'soc'),str(Path(__file__).resolve().parents[1]/'npu')]
from common import ROOT,tool,write_json
from frozen_inputs import FrozenInputs
from run_npu_service_compact import scan_fixture
from resource_probe import resource_report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=ROOT/'rtl/video/axi128_hmic256.sv')
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--synth',action='store_true');args=parser.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    result=dict(status='RUNNING',board_verified=False,routed=False);frozen=None
    try:
        names=['tb/video/tb_axi128_hmic256.sv','tb/video/models/axi_bridge_native_model.sv',
               'scripts/video/test_bridge_storage.py','scripts/soc/run_npu_service_compact.py',
               'scripts/soc/resource_probe.py','scripts/npu/frozen_inputs.py','scripts/video/common.py']
        frozen=FrozenInputs(ROOT,out/'inputs',names)
        source=out/'axi128_hmic256.sv';frozen.external(args.source.resolve(),source)
        tb=out/'test.sv';tb.write_text((frozen.directory/names[0]).read_text(encoding='utf-8').replace(
            'AXI128_HMIC256_PASS cases=%0d",cases','AXI128_HMIC256_PASS cases=%0d ticks=%0t",cases,$time'),encoding='utf-8');frozen.track(tb)
        iv,vvp=tool('iverilog'),tool('vvp');frozen.track(iv);frozen.track(vvp)
        def execute(command,log,timeout=120):
            with (out/log).open('wb') as stream:
                proc=subprocess.run(list(map(str,command)),cwd=out,stdout=stream,stderr=subprocess.STDOUT,
                    timeout=timeout,creationflags=subprocess.CREATE_NO_WINDOW)
            text=(out/log).read_text(encoding='utf-8',errors='replace')
            if proc.returncode or 'FATAL:' in text or '** Error' in text:raise RuntimeError(text[-3000:])
            return text
        execute([iv,'-g2012','-s','tb_axi128_hmic256','-o',out/'test.vvp',source,tb,frozen.directory/names[1]],'compile.log')
        log=execute([vvp,out/'test.vvp'],'simulation.log',600)
        lines=[x for x in log.splitlines() if 'AXI128_HMIC256_PASS cases=' in x]
        if len(lines)!=1:raise RuntimeError('missing bridge scoreboard PASS')
        result['simulation']=lines[0]
        if args.synth:
            fixture,_,_=scan_fixture('axi128_hmic256',source.read_text(encoding='utf-8'))
            (out/'scan_fixture.v').write_text(fixture,encoding='utf-8');frozen.track(out/'scan_fixture.v')
            (out/'boundary.fdc').write_text('create_clock -name core_clk -period 8.000 [get_ports {clk_i}]\n',encoding='utf-8');frozen.track(out/'boundary.fdc')
            script='set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676\n'
            for p in [source,out/'scan_fixture.v']:script+='add_design {'+p.as_posix()+'}\n'
            script+='add_constraint {'+(out/'boundary.fdc').as_posix()+'}\ncompile -system_verilog -top_module npu_compact_scan_top\nsynthesize -ads\n'
            (out/'build.tcl').write_text(script,encoding='utf-8');frozen.track(out/'build.tcl')
            pds=tool('pds_shell');frozen.track(pds)
            log=execute([pds,'-file',out/'build.tcl','-work_dir',out],'synthesis.log',600)
            if 'Executing : synthesize -ads successfully.' not in log:raise RuntimeError('missing synthesis completion')
            report=resource_report(out/'synthesize/npu_compact_scan_top.snr','synth')
            result['resources']=next(x for x in report['hierarchy'] if x['path']=='u_service')
        frozen.verify();result['status']='PASS'
    except Exception as exc:result.update(status='FAIL',error=str(exc))
    if frozen:
        result.update(source_sha256=frozen.inputs,external_sha256=frozen.external_inputs,tracked_sha256=frozen.tracked)
        try:frozen.verify();result['inputs_unchanged']=True
        except Exception as exc:result.update(status='FAIL',error=str(exc),inputs_unchanged=False)
    write_json(out/'result.json',result);print(result['status'],out,result.get('simulation',''),result.get('resources',result.get('error','')),flush=True)
    return int(result['status']!='PASS')


if __name__=='__main__':sys.exit(main())

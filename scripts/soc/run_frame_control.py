"""Run the application's frame MMIO contract with run-local frozen inputs."""
from datetime import datetime, timezone
from pathlib import Path
import re
import sys
from gen_config import ROOT, generate, need
sys.path.insert(0,str(ROOT/'scripts/video'))
sys.path.insert(0,str(ROOT/'scripts/npu'))
from common import tool, run_logged, write_json, sha256
from frozen_inputs import FrozenInputs


def main():
    out=ROOT/'build/soc/frame_control'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    out.mkdir(parents=True)
    result={'status':'RUNNING','scope':'AXI-Lite frame control; injected completion, no real NPU/DDR'}
    try:
        for name,data in generate(ROOT).items():need((ROOT/name).read_bytes()==data,'stale config '+name)
        names=['rtl/npu/npu_frame_mmio.v','tb/npu/tb_npu_frame_mmio.sv','rtl/soc/include/frame_config.vh',
               'tb/npu/tb_npu_frame_layout_admission.sv',
               'scripts/soc/run_frame_control.py','scripts/soc/gen_config.py','config/soc_memory.json',
               'config/npu_frame_regs.json','config/video_cfg.json','scripts/video/common.py','scripts/npu/frozen_inputs.py']
        snap=out/'inputs';frozen=FrozenInputs(ROOT,snap,names)
        compiler,simulator=tool('iverilog'),tool('vvp')
        frozen.track(compiler);frozen.track(simulator)
        profiles=[]
        for cpu_post in (0,1):
            run_logged([compiler,'-g2012','-I'+str(snap/'rtl/soc/include'),'-s','tb_npu_frame_mmio',
                        '-Ptb_npu_frame_mmio.CPU_POST='+str(cpu_post),
                        '-o',out/'sim.vvp',snap/names[0],snap/names[1]],out/f'compile_{cpu_post}.log')
            output=run_logged([simulator,out/'sim.vvp'],out/f'simulation_{cpu_post}.log')
            need(not re.search(r'\b(?:ERROR|FATAL)\b',output,re.I),'simulation diagnostic')
            match=re.search(r'PASS NPU_FRAME_MMIO checks=(\d+) starts=(\d+)',output)
            need(match and int(match[1])>=431 and int(match[2])==7,'incomplete frame test')
            profiles.append({'cpu_post':cpu_post,'checks':int(match[1]),'starts':int(match[2])})
        run_logged([compiler,'-g2012','-I'+str(snap/'rtl/soc/include'),'-s','tb_npu_frame_layout_admission',
                    '-o',out/'layout.vvp',snap/names[0],snap/'tb/npu/tb_npu_frame_layout_admission.sv'],out/'layout_compile.log')
        layout=run_logged([simulator,out/'layout.vvp'],out/'layout_simulation.log')
        need('LAYOUT_ADMISSION_PASS cases=1056 slots=3' in layout and not re.search(r'\b(?:ERROR|FATAL)\b',layout,re.I),
             'fixed layout admission test failed')
        frozen.verify()
        result.update(status='PASS',profiles=profiles,inputs=frozen.inputs,
                      layout_bit_mutations=1056,layout_slots=3,
                      tools={str(p):sha256(p) for p in (compiler,simulator)})
    except Exception as e:
        result.update(status='FAIL',error=str(e))
    write_json(out/'result.json',result)
    print('FRAME_CONTROL_'+result['status'],out)
    if result['status']!='PASS':print(result['error'],file=sys.stderr);return 1
    return 0


if __name__=='__main__':raise SystemExit(main())

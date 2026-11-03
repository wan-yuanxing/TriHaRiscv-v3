"""Frozen ModelSim UART and model-loader checks; no board claim."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'scripts/npu'),str(ROOT/'scripts/video')]
from frozen_inputs import FrozenInputs
from common import tool, write_json


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--loader',action='store_true')
    parser.add_argument('--avatar',action='store_true',help='Also check the seventh fixed avatar segment')
    parser.add_argument('--buffer',action='store_true')
    args=parser.parse_args()
    out=ROOT/'build/soc'/('boot_uart-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    out.mkdir(parents=True)
    result=dict(status='RUNNING',board_verified=False)
    frozen=None
    try:
        names=['rtl/soc/triha_uart_rx.v','tb/soc/tb_uart_rx.sv','scripts/soc/run_boot_uart.py',
               'scripts/npu/frozen_inputs.py','scripts/video/common.py']
        if args.loader:names+=['rtl/soc/triha_model_loader.v','rtl/soc/triha_boot_buffer.v','rtl/soc/triha_uart_tx.v',
            'rtl/soc/include/frame_config.vh','tb/soc/tb_model_loader.sv']
        if args.buffer:names+=['rtl/soc/triha_boot_buffer.v','tb/soc/tb_boot_buffer.sv']
        names=list(dict.fromkeys(names))
        frozen=FrozenInputs(ROOT,out/'inputs',names)
        sources=[out/'inputs'/p for p in names if p.endswith(('.v','.sv'))]
        inc=(out/'inputs/rtl/soc/include').as_posix()
        script='onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nvlib work\n'
        script+='vlog -sv {+incdir+'+inc+'} '+' '.join('{'+p.as_posix()+'}' for p in sources)+'\n'
        script+='quit -code 0 -force\n'
        (out/'compile.do').write_text(script,encoding='utf-8');frozen.track(out/'compile.do')
        vsim=tool('vsim');frozen.track(vsim)
        jobs=[('compile',['-do','compile.do']),('uart',['-onfinish','exit','work.tb_uart_rx','-do','run -all'])]
        if args.loader:
            jobs += [('loader'+str(n),['-onfinish','exit','work.tb_model_loader','-gSERIAL='+str(n),'-do','run -all']) for n in [0,1]]
            if args.avatar:
                jobs += [('avatar'+str(n),['-onfinish','exit','work.tb_model_loader','-gSERIAL='+str(n),'-gAVATAR=1','-do','run -all']) for n in [0,1]]
                jobs += [('avatar_full',['-onfinish','exit','work.tb_model_loader','-gAVATAR=1','-gAVATAR_BLOCKS=1024','-do','run -all'])]
        if args.buffer:jobs += [('buffer',['-onfinish','exit','work.tb_boot_buffer','-do','run -all'])]
        with (out/'simulation.log').open('wb') as stream:
            for label,arguments in jobs:
                stream.write(('RUN '+label+'\n').encode());stream.flush()
                proc=subprocess.run([str(vsim),'-c',*arguments],cwd=out,stdout=stream,
                    stderr=subprocess.STDOUT,timeout=120,creationflags=subprocess.CREATE_NO_WINDOW)
                if proc.returncode:raise RuntimeError(label+' exit='+str(proc.returncode))
        log=(out/'simulation.log').read_text(encoding='utf-8',errors='replace')
        if proc.returncode or '** Error' in log or '** Fatal' in log or 'PASS UART_RX' not in log:
            raise RuntimeError(log[-3000:])
        if args.loader and log.count('PASS MODEL_LOADER')!=(5 if args.avatar else 2):raise RuntimeError('missing loader PASS')
        if args.buffer and 'PASS BOOT_BUFFER' not in log:raise RuntimeError('missing buffer PASS')
        frozen.verify();result.update(status='PASS',passes=[x for x in log.splitlines() if 'PASS ' in x])
    except Exception as exc:result.update(status='FAIL',error=str(exc))
    finally:
        if frozen:
            result.update(source_sha256=frozen.inputs,tracked_sha256=frozen.tracked)
            try:frozen.verify();result['inputs_unchanged']=True
            except Exception as exc:result.update(status='FAIL',inputs_unchanged=False,error=str(exc))
        write_json(out/'result.json',result)
    print(result['status'],out,result.get('error',result.get('passes')),flush=True)
    return int(result['status']!='PASS')


if __name__=='__main__':sys.exit(main())

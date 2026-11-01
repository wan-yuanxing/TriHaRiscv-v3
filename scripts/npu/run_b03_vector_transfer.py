"""Frozen real-vector transfer boundary/CE/cancel regression (no board claim)."""
import argparse
from pathlib import Path
import subprocess
import sys
import time
from frozen_inputs import FrozenInputs
from run_b03_frame import ROOT, VENDOR, VENDOR_FILES, common, check_log, need


def run(output, source=None):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    result = {'status': 'RUNNING', 'board_verified': False}
    common.write_json(output/'result.json', result)
    started = time.monotonic()
    try:
        names = (ROOT/'config/npu_b03_sources.f').read_text(encoding='utf-8').splitlines()
        names += ['tb/npu/tb_b03_vector_transfer.sv', 'tb/npu/tb_b03_vector_address.sv', 'scripts/npu/run_b03_vector_transfer.py',
                  'scripts/npu/frozen_inputs.py', 'scripts/npu/run_b03_frame.py', 'scripts/video/common.py']
        frozen = FrozenInputs(ROOT, output/'inputs', names)
        vendors = []
        for name in VENDOR_FILES:
            dest = output/'vendor'/name
            frozen.external(VENDOR/name, dest)
            vendors.append(dest)
        vsim = common.tool('vsim')
        frozen.track(vsim)
        sources = vendors+[frozen.directory/n for n in names if n.endswith(('.v','.sv'))]
        if source is not None:
            candidate = output/'candidate/b03_vector_exec_compact.v'
            frozen.external(source.resolve(), candidate)
            original = frozen.directory/'rtl/npu/upstream/b03/rtl/platform/b03_vector_exec_compact.v'
            sources = [candidate if path == original else path for path in sources]
        (output/'sources.f').write_text(''.join('"'+p.as_posix()+'"\n' for p in sources), encoding='utf-8')
        (output/'run.do').write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nvlib work\n'
            'vlog -sv -f sources.f\nvsim -voptargs=+acc -t 1ps work.tb_b03_vector_transfer\n'
            'run -all\nquit -code 0 -force\n', encoding='utf-8')
        frozen.track(output/'sources.f'); frozen.track(output/'run.do')
        with (output/'console.log').open('wb') as stream:
            proc = subprocess.run([str(vsim), '-c', '-do', 'run.do', '-l', 'transcript.log'],
                cwd=output, stdout=stream, stderr=subprocess.STDOUT, timeout=120,
                creationflags=subprocess.CREATE_NO_WINDOW)
        need(proc.returncode==0, 'transfer simulation failed: '+str(output/'console.log'))
        address_script = output/'address.do'
        address_script.write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\n'
            'vsim -voptargs=+acc -t 1ps work.tb_b03_vector_address\n'
            'run -all\nquit -code 0 -force\n', encoding='utf-8')
        frozen.track(address_script)
        with (output/'console.log').open('ab') as stream:
            proc = subprocess.run([str(vsim), '-c', '-do', 'address.do', '-l', 'address_transcript.log'],
                cwd=output, stdout=stream, stderr=subprocess.STDOUT, timeout=120,
                creationflags=subprocess.CREATE_NO_WINDOW)
        frozen.verify()
        need(proc.returncode==0, 'simulation failed: '+str(output/'console.log'))
        log = (output/'console.log').read_text(encoding='utf-8', errors='replace')
        result['diagnostics'] = check_log(log, ['PASS B03_VECTOR_TRANSFER cases=66051',
                                               'PASS B03_VECTOR_ADDRESS cases=8192'])
        result.update(status='PASS', cases=66051, address_cases=8192, source_sha256=frozen.inputs,
                      external_sha256=frozen.external_inputs, tracked_sha256=frozen.tracked)
    except Exception as exc:
        result.update(status='FAIL', error=str(exc))
    result['host_seconds'] = time.monotonic()-started
    common.write_json(output/'result.json', result)
    print(result['status']+' '+result.get('error',''))
    return int(result['status']!='PASS')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--source',type=Path,help='Isolated vector source candidate')
    args=parser.parse_args()
    sys.exit(run(args.output,args.source))

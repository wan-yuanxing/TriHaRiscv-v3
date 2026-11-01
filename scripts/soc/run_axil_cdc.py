"""Frozen 100/125 MHz AXI-Lite CDC tests through the real video decoder."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/video'))
from common import tool, write_json
sys.path.insert(0, str(ROOT / 'scripts/npu'))
from frozen_inputs import FrozenInputs


def run(output):
    output = Path(output).resolve()
    if output.exists():
        raise ValueError('fresh AXI-Lite CDC output required')
    output.mkdir(parents=True)
    write_json(output / 'result.json', {'status': 'RUNNING'})
    started = time.monotonic()
    try:
        sources = ['rtl/soc/soc_axil_cdc.v', 'rtl/soc/video_axil_decode.v',
                   'rtl/video/video_async_fifo.sv', 'tb/soc/tb_soc_axil_cdc.sv']
        names = sources + ['rtl/video/include/video_capture_v2.vh',
                           'rtl/video/include/video_display.vh', 'scripts/soc/run_axil_cdc.py',
                           'scripts/npu/frozen_inputs.py', 'scripts/video/common.py']
        frozen = FrozenInputs(ROOT, output / 'inputs_snapshot', names)
        compiler, simulator = tool('iverilog'), tool('vvp')
        frozen.track(compiler)
        frozen.track(simulator)
        versions = {}
        for name, executable in [('iverilog', compiler), ('vvp', simulator)]:
            version = subprocess.run([str(executable), '-V'], capture_output=True, text=True, timeout=30)
            versions[name] = (version.stdout + version.stderr).splitlines()[0]
        results = []
        for phase in [0, 1, 3]:
            label = 'phase_' + str(phase)
            executable = output / (label + '.vvp')
            commands = [
                [str(compiler), '-g2012', '-s', 'tb_soc_axil_cdc',
                 '-Ptb_soc_axil_cdc.PHASE_NS=' + str(phase),
                 '-I' + str(frozen.directory / 'rtl/video/include'), '-o', str(executable),
                 *[str(frozen.directory / name) for name in sources]],
                [str(simulator), str(executable)],
            ]
            for index, command in enumerate(commands):
                frozen.verify()
                result = subprocess.run(command, cwd=output, capture_output=True, text=True, timeout=120)
                log = result.stdout + result.stderr
                (output / (label + ('.compile.log' if index == 0 else '.simulation.log'))).write_text(log, encoding='utf-8')
                if result.returncode or re.search(r'\b(?:ERROR|FATAL|WARNING)(?=\s|:|!|$)', log, re.I):
                    raise ValueError('AXI-Lite CDC regression failed: ' + log[-2000:])
            pass_lines = [line for line in log.splitlines() if line.startswith('PASS')]
            marker = re.fullmatch(
                r'PASS SOC_AXIL_CDC phase=' + str(phase) +
                r' epochs=2 writes=54 reads=38 b_stalls=([1-9][0-9]*) r_stalls=([1-9][0-9]*)',
                pass_lines[0] if len(pass_lines) == 1 else '')
            if marker is None:
                raise ValueError('missing exact scoreboard PASS: ' + label)
            results.append({'phase_ns': phase, 'epochs': 2, 'writes': 54, 'reads': 38,
                            'b_stalls': int(marker[1]), 'r_stalls': int(marker[2]), 'pass_line': pass_lines[0]})
        frozen.verify()
        report = {'status': 'PASS_RTL_AXIL_CDC_AND_VIDEO_DECODE',
                  'host_seconds': time.monotonic() - started, 'tests': results,
                  'sources_sha256': frozen.inputs, 'tools_sha256': frozen.tracked,
                  'tool_versions': versions,
                  'scope': '100/125 MHz; three phases; real video decoder; two independent register slaves; '
                           'AW/W both orders; WSTRB byte oracle; all channel backpressure; '
                           'OKAY/SLVERR/DECERR; protection bits; response stability; drained coordinated reset.',
                  'physical_CDC_verified': False, 'board_verified': False}
        write_json(output / 'result.json', report)
        print(json.dumps(report, indent=2))
        return report
    except Exception as exc:
        write_json(output / 'result.json', {'status': 'FAIL', 'error': str(exc), 'board_verified': False})
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        run(args.output)
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)

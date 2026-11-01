"""Frozen native-Windows byte-scoreboard regression for B03 service / AXI128."""
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
        raise ValueError('fresh service output required')
    output.mkdir(parents=True)
    write_json(output / 'result.json', {'status': 'RUNNING'})
    started = time.monotonic()
    try:
        sources = ['rtl/soc/npu_service_axi128.v', 'tb/soc/tb_npu_service_axi128.sv']
        frozen = FrozenInputs(ROOT, output / 'inputs_snapshot', sources + ['scripts/soc/run_npu_service.py'])
        compiler, simulator = tool('iverilog'), tool('vvp')
        frozen.track(compiler); frozen.track(simulator)
        commands = [[str(compiler), '-g2012', '-s', 'tb_npu_service_axi128', '-o', str(output / 'test.vvp'),
                     *[str(frozen.directory / name) for name in sources]], [str(simulator), str(output / 'test.vvp')]]
        for index, command in enumerate(commands):
            result = subprocess.run(command, cwd=output, capture_output=True, text=True, timeout=120)
            text = result.stdout + result.stderr
            (output / ('compile.log' if index == 0 else 'simulation.log')).write_text(text, encoding='utf-8')
            if result.returncode or re.search(r'\b(?:ERROR|FATAL|WARNING)(?=\s|:|!|$)', text, re.I):
                raise ValueError('service regression failed: ' + text[-2000:])
        match = re.search(r'PASS NPU_SERVICE_AXI128 checks=(\d+) AW=(\d+) B=(\d+) AR=(\d+) WbeforeAW=(\d+) AWbeforeW=(\d+) splits=(\d+)', text)
        if not match or int(match[1]) < 16:
            raise ValueError('missing service scoreboard coverage')
        frozen.verify()
        report = {'status': 'PASS_RTL_SERVICE_SCOREBOARD', 'host_seconds': time.monotonic() - started,
                  'metrics': dict(zip(('checks', 'AW', 'B', 'AR', 'WbeforeAW', 'AWbeforeW', 'splits'), map(int, match.groups()))),
                  'sources_sha256': frozen.inputs, 'tools_sha256': frozen.tracked,
                  'scope': 'RTL byte scoreboard and protocol injection; no physical DDR, timing or board proof.', 'board_verified': False}
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

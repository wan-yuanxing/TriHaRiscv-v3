"""Frozen byte-scoreboard tests for generic AXI arbitration and the one DDR bridge."""
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
        raise ValueError('fresh arbiter output required')
    output.mkdir(parents=True)
    write_json(output / 'result.json', {'status': 'RUNNING'})
    started = time.monotonic()
    try:
        names = ['rtl/soc/soc_axi128_arbiter.v', 'rtl/soc/soc_ddr_fabric.v',
                 'rtl/video/axi128_hmic256.sv', 'tb/soc/tb_soc_axi128_arbiter.sv']
        frozen = FrozenInputs(ROOT, output / 'inputs_snapshot', names + ['scripts/soc/run_soc_arbiter.py'])
        compiler, simulator = tool('iverilog'), tool('vvp')
        frozen.track(compiler); frozen.track(simulator)
        results = []
        for top, masters, marker in [('tb_axi128_address_legal', 0, 'PASS AXI128_ADDRESS_LEGAL cases=2359301'),
                                    ('tb_soc_axi128_arbiter', 2, 'PASS SOC_AXI128_ARBITER masters=2 checks=34 '),
                                    ('tb_soc_axi128_arbiter', 3, 'PASS SOC_AXI128_ARBITER masters=3 checks=46 '),
                                    ('tb_soc_ddr_fabric', 0, 'PASS SOC_DDR_FABRIC lanes=3 nativeAW=2 nativeAR=3')]:
            label = top + ('_' + str(masters) if masters else '')
            parameters = ['-P' + top + '.M=' + str(masters)] if masters else []
            commands = [[str(compiler), '-g2012', '-s', top, *parameters, '-o', str(output / (label + '.vvp')),
                         *[str(frozen.directory / name) for name in names]],
                        [str(simulator), str(output / (label + '.vvp'))]]
            for index, command in enumerate(commands):
                result = subprocess.run(command, cwd=output, capture_output=True, text=True, timeout=120)
                text = result.stdout + result.stderr
                (output / (label + ('.compile.log' if index == 0 else '.simulation.log'))).write_text(text, encoding='utf-8')
                if result.returncode or re.search(r'\b(?:ERROR|FATAL|WARNING)(?=\s|:|!|$)', text, re.I):
                    raise ValueError('arbiter regression failed: ' + text[-2000:])
            if marker not in text:
                raise ValueError('missing actual scoreboard PASS: ' + top)
            results.append({'top': top, 'masters': masters, 'pass_line': next(line for line in text.splitlines() if marker in line)})
        frozen.verify()
        report = {'status': 'PASS_RTL_ARBITER_AND_FABRIC', 'host_seconds': time.monotonic() - started,
                  'tests': results, 'sources_sha256': frozen.inputs, 'tools_sha256': frozen.tracked,
                  'scope': 'Concurrent AXI masters, independent byte model, and one real AXI/HMIC bridge with native proxy.',
                  'physical_DDR_verified': False, 'board_verified': False}
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

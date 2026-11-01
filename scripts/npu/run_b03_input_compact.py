"""Frozen full input-path scoreboard and cycle-level original/compact comparison."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/video'))
from common import tool, write_json
from frozen_inputs import FrozenInputs
from run_b03_frame import check_log

REVISION = '558280b30219acdcf9f962acd6e907e0f680ab52'
OLD_ROOT = ROOT / 'build/npu/b03_assets_20261030/frozen_upstream'
VENDOR = Path('D:/pango/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')


def run(output, trusted=False, input_source=None):
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    result = {'status': 'RUNNING', 'board_verified': False, 'trusted_model': trusted}
    write_json(output / 'result.json', result)
    try:
        prod = (ROOT / 'config/npu_b03_sources.f').read_text().splitlines()
        names = prod + ['rtl/npu/b03_model_input_compact.v', 'tb/npu/tb_b03_input_compact.sv',
                       'scripts/npu/run_b03_input_compact.py', 'scripts/npu/run_b03_frame.py',
                       'scripts/npu/frozen_inputs.py', 'scripts/video/common.py']
        frozen = FrozenInputs(ROOT, output / 'inputs_snapshot', names)
        frozen.track(Path(sys.executable))
        assets = output / 'assets_snapshot'
        old = 'yunet/reports/program_abi_v0_1_checked/'
        for name in ('program.bin', 'parameter_image.bin'):
            frozen.external(OLD_ROOT / old / name, assets / old / name)
        frozen.external(OLD_ROOT / 'yunet/baseline/program_package_manifest_v0_1.json',
                        assets / old / 'program_package_manifest_v0_1.json')
        frozen.external(ROOT / 'build/npu/b03_assets_20261030/assets/cases/pattern/input.bin',
                        assets / 'yunet/reports/ptq_320_v0_1/bbox16/golden/pattern/input_u8_nchw.bin')
        for source in sorted((OLD_ROOT / 'yunet/python').glob('*.py')):
            frozen.external(source, assets / 'yunet/python' / source.name)
        sys.path.insert(0, str(assets / 'yunet/python'))
        import program_abi
        decoded = program_abi.unpack((assets / old / 'program.bin').read_bytes())
        program_abi.validate(decoded)
        write_json(assets / old / 'program_decoded.json', decoded)
        generator = output / 'upstream_fixture.py'
        generator.write_bytes(subprocess.check_output(['git', '-C', 'D:/FPGA/npu_zgtc', 'show',
            REVISION + ':yunet/python/run_b03_model_input_wordkeys_checks.py']))
        frozen.track(generator)
        spec = importlib.util.spec_from_file_location('b03_frozen_input_fixture', generator)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.ROOT = assets
        fixture = output / 'fixture'
        fixture.mkdir()
        cases = module.fixture(fixture)
        for path in fixture.iterdir():
            frozen.track(path)
        vendors = []
        for name in ('GTP_GRS.v', 'GTP_DRM18K_E1.v', 'GTP_APM_E2.v', 'GTP_RAM32X1DP.v', 'GTP_RAM32X2DP.v', 'GTP_LUT1.v'):
            path = output / 'vendor_snapshot' / name
            frozen.external(VENDOR / name, path)
            vendors.append(path)
        vsim = tool('vsim')
        frozen.track(vsim)
        sim = output / 'simulation'
        sim.mkdir()
        sources = vendors + [frozen.directory / name for name in names if name.endswith(('.v', '.sv'))]
        if input_source is not None:
            candidate = output / 'candidate/b03_model_input_payload.v'
            frozen.external(input_source.resolve(), candidate)
            original = frozen.directory / 'rtl/npu/upstream/b03/rtl/platform/b03_model_input_payload.v'
            sources = [candidate if path == original else path for path in sources]
        (sim / 'sources.f').write_text('\n'.join('"' + p.as_posix() + '"' for p in sources) + '\n')
        script = sim / 'run.do'
        script.write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nvlib work\n'
                          'vlog -sv -f sources.f\nvsim -voptargs=+acc -t 1ps work.tb_b03_input_compact -gTRUSTED_MODEL='+str(int(trusted))+' {+ROOT=' +
                          fixture.as_posix() + '}\nrun -all\nquit -code 0 -force\n', encoding='utf-8')
        command = [str(vsim), '-c', '-do', str(script), '-l', 'transcript.log']
        started = time.monotonic()
        print('INPUT_COMPACT_LOCKSTEP', output, flush=True)
        with (sim / 'console.log').open('wb') as stream:
            process = subprocess.run(command, cwd=sim, stdout=stream, stderr=subprocess.STDOUT,
                                     timeout=600, creationflags=subprocess.CREATE_NO_WINDOW)
        frozen.verify()
        if process.returncode:
            raise ValueError('simulation failed: ' + str(sim / 'console.log'))
        text = (sim / 'console.log').read_text(encoding='utf-8', errors='replace')
        diagnostics = check_log(text, ['PASS B03_MODEL_INPUT_WORDKEYS ', 'IDENTITY_PIPE ', 'WORDKEY_SAVE '])
        metrics = {key: int(value) for key, value in re.findall(r'(\w+)=(\d+)',
            next(line for line in text.splitlines() if 'PASS B03_MODEL_INPUT_WORDKEYS ' in line))}
        if len(cases) != 34 or metrics.get('cases') != 34 or metrics.get('max_AB_streak') != 128:
            raise ValueError('input-path coverage missing')
        if 'INPUT_PROFILE trusted='+str(int(trusted)) not in text:
            raise ValueError('input profile not verified')
        result.update(status='PASS_TRUSTED_INPUT_SCOREBOARD' if trusted else 'PASS_INPUT_SCOREBOARD_AND_LOCKSTEP', cases=len(cases), metrics=metrics,
                      host_seconds=time.monotonic()-started, diagnostics=diagnostics,
                      source_sha256=frozen.inputs, external_sha256=frozen.external_inputs,
                      tracked_sha256=frozen.tracked, public_outputs_compared=0 if trusted else 46,
                      scope=('Trusted payload parameter/ROI/A/B/DW scoreboards and content bypass; transport/cancel/epoch faults remain tested.' if trusted else 'Original/compact all 46 public outputs compared each non-reset cycle; actual parameter/ROI/A/B/DW scoreboards; native memory service proxy.'))
        write_json(output / 'result.json', result)
        print(json.dumps({k: result[k] for k in ('status', 'cases', 'metrics', 'host_seconds')}), flush=True)
    except Exception as exc:
        result.update(status='FAIL', error=str(exc))
        write_json(output / 'result.json', result)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--trusted', action='store_true')
    parser.add_argument('--source', type=Path, help='Frozen isolated input-path RTL override')
    args = parser.parse_args()
    try:
        run(args.output, args.trusted, args.source)
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)

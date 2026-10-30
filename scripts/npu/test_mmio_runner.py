"""Run the NPU register ABI validation and self-checking AXI-Lite simulation."""
import argparse
import contextlib
from datetime import datetime, timezone
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/video"))
from common import tool
from frozen_inputs import FrozenInputs, sha256


def run(command, log):
    result = subprocess.run([str(item) for item in command], cwd=ROOT,
                            capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=60)
    output = result.stdout + result.stderr
    log.write_text(output, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"{Path(str(command[0])).name} exit {result.returncode}\n{output[-4000:]}")
    return output


def generator_tests(build, root=ROOT):
    spec = importlib.util.spec_from_file_location("npu_gen_regs", root / "scripts/npu/gen_regs.py")
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    config = json.loads((root / "config/npu_regs.json").read_text(encoding="utf-8"))
    generator.validate(config)
    expected = {
        "ID_VERSION": 0, "CAPS": 4, "CONTROL": 8, "STATUS": 12,
        "IRQ_STATUS": 16, "IRQ_ENABLE": 20, "ERROR_CODE": 24,
        "OP_TAG": 28, "FRAME_ID": 32, "TOTAL_CYCLES": 36,
        "COMPUTE_CYCLES": 40, "DMA_WAIT_CYCLES": 44, "GENERATION": 48,
        "INPUT_BASE": 256, "WEIGHT_BASE": 260, "BIAS_BASE": 264,
        "REQUANT_BASE": 268, "OUTPUT_BASE": 272, "INPUT_WH": 276,
        "CHANNELS": 280, "OUTPUT_WH": 284, "KSP": 288, "FORMAT": 292,
    }
    assert {reg["name"]: reg["offset"] for reg in config["registers"]} == expected
    count = 1
    for label, mutate in [
        ("duplicate offset", lambda c: c["registers"][1].update(offset=0)),
        ("unaligned offset", lambda c: c["registers"][1].update(offset=5)),
        ("out of window", lambda c: c["registers"][1].update(offset=4096)),
        ("duplicate name", lambda c: c["registers"][1].update(name="ID_VERSION")),
        ("unknown top key", lambda c: c.update(unrecognized=0)),
        ("bad access", lambda c: c["registers"][0].update(access="RW")),
        ("unknown register key", lambda c: c["registers"][0].update(bogus=0)),
        ("bad field key", lambda c: c["registers"][2]["fields"][0].update(bogus=0)),
        ("bad field range", lambda c: c["registers"][2]["fields"][0].update(width=33)),
        ("overlapping field", lambda c: c["registers"][2]["fields"].append({"name": "BAD", "lsb": 0, "width": 1})),
        ("duplicate field", lambda c: c["registers"][2]["fields"].append({"name": "START", "lsb": 1, "width": 1})),
        ("boolean offset", lambda c: c["registers"][0].update(offset=False)),
        ("reserved reset", lambda c: c["registers"][2].update(reset=2)),
    ]:
        candidate = json.loads(json.dumps(config))
        mutate(candidate)
        try:
            generator.validate(candidate)
        except ValueError:
            count += 1
        else:
            raise AssertionError(f"generator accepted {label}")
    try:
        json.loads('{"base":1,"base":2}', object_pairs_hook=generator.unique_object)
    except ValueError:
        count += 1
    else:
        raise AssertionError("generator accepted duplicate JSON keys")
    # Exercise the actual CLI path: --check must fail for missing/stale files
    # and preserve their bytes, rather than silently regenerating them.
    fixture_root = build / "generator_fixture"
    fixture_root.mkdir()
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured), contextlib.redirect_stderr(captured):
        assert generator.main(["--root", str(fixture_root), "--check"]) == 1
        assert generator.main(["--root", str(fixture_root)]) == 0
        assert generator.main(["--root", str(fixture_root), "--check"]) == 0
        stale = fixture_root / "sw/include/npu_regs.h"
        stale.write_bytes(b"stale\n")
        assert generator.main(["--root", str(fixture_root), "--check"]) == 1
        assert stale.read_bytes() == b"stale\n"
    (build / "generator_cli.log").write_text(captured.getvalue(), encoding="utf-8")
    count += 5
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sim-only", action="store_true")
    args = parser.parse_args()
    build = ROOT / "build/npu/mmio" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    build.mkdir(parents=True)
    latest = ROOT / "build/npu/mmio/latest.json"
    latest.unlink(missing_ok=True)
    metadata = {"result": "RUNNING", "build": str(build)}
    try:
        if not __debug__:
            raise RuntimeError('optimized Python disables generator test checks; PASS is prohibited')
        names = ['rtl/npu/npu_operator_mmio.v', 'tb/npu/tb_npu_operator_mmio.sv',
                 'config/npu_regs.json', 'scripts/npu/gen_regs.py', 'rtl/npu/include/npu_regs.vh',
                 'sw/include/npu_regs.h', 'scripts/npu/test_mmio_runner.py',
                 'scripts/npu/frozen_inputs.py', 'scripts/video/common.py']
        guard = FrozenInputs(ROOT, build / 'inputs', names)
        metadata['inputs'] = guard.inputs
        frozen = build / 'inputs'
        def checked(command, log):
            guard.verify()
            try:
                return run(command, log)
            finally:
                guard.verify()
        if not args.sim_only:
            count = generator_tests(build, frozen)
            (build / "generator_tests.log").write_text(f"REGS_TEST_PASS checks={count}\n", encoding="utf-8")
            checked([sys.executable, frozen / "scripts/npu/gen_regs.py", "--check"], build / "gen_check.log")
        compiler = tool("iverilog")
        runtime = tool("vvp")
        for executable in (compiler, runtime): guard.track(executable)
        metadata['tools'] = {str(path):sha256(path) for path in (compiler, runtime)}
        checked([compiler, "-V"], build / "iverilog_version.log")
        checked([runtime, "-V"], build / "vvp_version.log")
        sources = [frozen / "rtl/npu/npu_operator_mmio.v", frozen / "tb/npu/tb_npu_operator_mmio.sv"]
        executable = build / "tb_mmio.vvp"
        checked([compiler, "-g2012", "-Wall", "-I", frozen / "rtl/npu/include", "-s",
             "tb_npu_operator_mmio", "-o", executable, *sources], build / "compile.log")
        guard.track(executable)
        output = checked([runtime, executable], build / "simulation.log")
        if "MMIO_PASS" not in output:
            raise RuntimeError("simulation did not emit MMIO_PASS")
        guard.verify()
        metadata.update(result='PASS', source_unchanged=True,
                        artifacts_sha256={p.name:sha256(p) for p in build.glob('*.log')})
        latest.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        (build / "result.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        print(output.strip())
        print(f"NPU_MMIO_PASS {build}")
        return 0
    except (OSError, ValueError, RuntimeError, AssertionError, subprocess.TimeoutExpired) as error:
        metadata.update(result='FAIL', error=str(error))
        (build / "result.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        print(f"NPU_MMIO_FAIL {error}\nlogs={build}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

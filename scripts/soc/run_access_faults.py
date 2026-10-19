"""Exercise real CPU access-fault traps using isolated, recorded test fixtures.

The normal runtime correctly rejects these programs. This outer self-check
accepts only the precise expected cause/address/exit from the wire UART log.
No production source or frozen PDS input is changed.
"""
import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("runtime_directory", type=Path)
    args = parser.parse_args()
    baseline = args.runtime_directory.resolve()
    result = json.loads((baseline / "result.json").read_text(encoding="utf-8"))
    assert result["status"] == "PASS" and result["test"] == "runtime" and result["source_unchanged"]
    work = ROOT / "build/soc" / ("access-faults-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
    work.mkdir(parents=True)
    receipt = dict(status="RUNNING", baseline=str(baseline), baseline_result_sha256=sha(baseline / "result.json"),
                   runner_sha256=sha(Path(__file__)), cases=[], production_source_unchanged=False)
    cases = [("unmapped-load", "return *(volatile unsigned int *)0x80000000u;", 5, "80000000"),
             ("rom-store", "*(volatile unsigned int *)0u = 0x5a; return 0;", 7, "00000000"),
             ("unmapped-fetch", "((void (*)(void))0x80000000u)(); return 0;", 1, "80000000"),
             ("sram-boundary", "return *(volatile unsigned int *)0x18000u;", 5, "00018000")]
    try:
        for name, body, cause, address in cases:
            fixture = work / name
            for relative, digest in result["input_hashes"].items():
                src = baseline / "src" / relative
                assert sha(src) == digest, relative
                dst = fixture / relative
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_bytes(src.read_bytes())
            program = fixture / "sw/tests/soc_runtime.c"
            program.write_bytes(("/* Deliberately faulting integration test. */\nint main(void) { " + body + " }\n").encode("utf-8"))
            process = subprocess.run([sys.executable, str(fixture / "scripts/soc/run.py"), "--test", "runtime"], cwd=fixture,
                                     capture_output=True, timeout=120)
            (fixture / "outer.log").write_bytes(process.stdout + process.stderr)
            runs = list((fixture / "build/soc").glob("runtime-*/result.json"))
            assert len(runs) == 1
            child = json.loads(runs[0].read_text(encoding="utf-8"))
            log = (runs[0].parent / "simulation.log").read_text(encoding="utf-8")
            assert process.returncode == 1 and child["status"] == "FAIL" and child["source_unchanged"] and child["external_unchanged"]
            assert child["commands"][-1]["return_code"] == 0
            assert f"CPU_TRAP cause={cause:08x} value={address}" in log
            assert "SOC_PROGRAM_EXIT code=1" in log and "SOC_FIRMWARE_PASS" not in log
            receipt["cases"].append(dict(name=name, status="PASS", expected_cause=cause, expected_address=address,
                rejected_by_normal_runtime=True, program_sha256=sha(program), result=str(runs[0]), result_sha256=sha(runs[0]),
                log=str(runs[0].parent / "simulation.log"), log_sha256=sha(runs[0].parent / "simulation.log")))
            print("SOC_ACCESS_FAULT_PASS", name, flush=True)
        receipt["production_source_unchanged"] = all(sha(ROOT / n) == d for n, d in result["input_hashes"].items())
        assert receipt["production_source_unchanged"]
        receipt["status"] = "PASS"
    except Exception as error:
        receipt["status"] = "FAIL"
        receipt["error"] = repr(error)
    (work / "result.json").write_bytes((json.dumps(receipt, indent=2) + "\n").encode("utf-8"))
    print("SOC_ACCESS_FAULTS", receipt["status"], "result=" + str(work / "result.json"))
    return 0 if receipt["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())

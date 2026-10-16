"""Run the available Video regression suites using native Python/Icarus."""
import argparse
import json
from pathlib import Path
import sys

from common import BUILD, ROOT, fresh_run, input_hashes, run_logged, tool, write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=("config", "timing", "all"), default="all")
    args = parser.parse_args()
    work = fresh_run("regression")
    latest = BUILD / f"latest_{args.suite}.json"
    result = {"status": "running", "suite": args.suite,
              "directory": str(work.relative_to(ROOT)), "passed": [],
              "physical_board": False, "vendor_ddr_training": False}
    write_json(latest, result)  # Invalidate an earlier PASS before doing any work.
    try:
        run_logged([sys.executable, ROOT / "scripts/video/gen_config.py", "--check"],
                   work / "config_check.log")
        manifest_path = ROOT / "fpga/pg2l100h/project/video_timing.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        paths = [ROOT / relative for relative in manifest["sources"] + manifest["tests"]]
        paths += [manifest_path, ROOT / "config/video_cfg.json",
                  ROOT / "rtl/video/include/video_cfg.vh", ROOT / "sw/include/video_cfg.h"]
        paths += list((ROOT / "scripts/video").glob("*.py"))
        paths += list((ROOT / "tb/video").glob("test_*.py"))
        result["inputs"] = input_hashes(set(paths))
        result["python"] = sys.version.split()[0]
        if args.suite in ("config", "all"):
            run_logged([sys.executable, "-m", "unittest", "discover", "-s",
                        ROOT / "tb/video", "-p", "test_*.py", "-v"], work / "python.log")
            result["passed"].append("config")
        if args.suite in ("timing", "all"):
            iverilog, vvp = tool("iverilog"), tool("vvp")
            result["iverilog_version"] = run_logged(
                [iverilog, "-V"], work / "iverilog_version.log").splitlines()[0]
            result["vvp_version"] = run_logged(
                [vvp, "-V"], work / "vvp_version.log").splitlines()[0]
            binary = work / "timing.vvp"
            run_logged([iverilog, "-g2012", "-Wall", "-I",
                        ROOT / "rtl/video/include", "-s", manifest["test_top"],
                        "-o", binary, *[ROOT / name for name in manifest["sources"]],
                        *[ROOT / name for name in manifest["tests"]]], work / "compile.log")
            log = run_logged([vvp, binary], work / "simulation.log")
            if "VIDEO_TIMING_PASS" not in log:
                raise RuntimeError("Missing VIDEO_TIMING_PASS marker")
            result["passed"].append("timing")
        result["status"] = "pass"
    except Exception as error:
        result["status"] = "fail"
        result["error"] = str(error)
        print(str(error), file=sys.stderr)
    write_json(work / "result.json", result)
    write_json(latest, result)
    print(f"VIDEO_REGRESSION_{result['status'].upper()}: {work}")
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

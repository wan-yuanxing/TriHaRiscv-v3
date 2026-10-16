"""Native PDS component synthesis. This target cannot generate a board bitstream."""
import argparse
import json
from pathlib import Path
import re
import shutil
import sys

from common import BUILD, ROOT, fresh_run, input_hashes, run_logged, sha256, tool, write_json


def tcl_path(path):
    text = Path(path).resolve().as_posix()
    if any(char in text for char in "{}\n\r"):
        raise ValueError("Tcl path contains an unsupported brace/newline")
    return "{" + text + "}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("video_timing",), default="video_timing")
    parser.add_argument("--stage", choices=("synth",), default="synth")
    args = parser.parse_args()
    work = fresh_run("pds")
    latest = BUILD / "latest_pds.json"
    result = {"status": "running", "target": args.target, "stage": args.stage,
              "directory": str(work.relative_to(ROOT)), "physical_board": False,
              "timing_closed": False, "vendor_ddr_training": False,
              "scope": "standalone timing/pattern synthesis; no board pins, HDMI or DDR"}
    write_json(latest, result)
    try:
        run_logged([sys.executable, ROOT / "scripts/video/gen_config.py", "--check"],
                   work / "config_check.log")
        manifest_path = ROOT / "fpga/pg2l100h/project/video_timing.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        top = manifest["top"]
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", top):
            raise ValueError("Invalid top module")
        names = manifest["sources"] + manifest["constraints"] + [
            "rtl/video/include/video_cfg.vh", "config/video_cfg.json",
            str(manifest_path.relative_to(ROOT))]
        result["inputs"] = input_hashes([ROOT / name for name in names] +
                                        list((ROOT / "scripts/video").glob("*.py")))
        for name in names:
            destination = work / "src" / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        lines = ["set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676"]
        lines += ["add_design " + tcl_path(work / "src" / name)
                  for name in manifest["sources"]]
        lines += ["add_constraint " + tcl_path(work / "src" / name)
                  for name in manifest["constraints"]]
        lines += [f"compile -system_verilog -top_module {top} -include_path {{" +
                  tcl_path(work / "src/rtl/video/include") + "}", "synthesize -ads"]
        script = work / "build.tcl"
        script.write_text("\n".join(lines) + "\n", encoding="utf-8")
        executable = tool("pds_shell")
        result["pds_version"] = run_logged(
            [executable, "-version"], work / "version.log").strip()
        log = run_logged([executable, "-file", script, "-work_dir", work,
                          "-project_name", "video_timing"], work / "synth.log",
                         cwd=work, timeout=900)
        if any(line.lstrip().startswith(("E:", "C:")) for line in log.splitlines()):
            raise RuntimeError("PDS reported an error/critical warning; inspect synth.log")
        report = work / "synthesize" / (top + ".snr")
        text = report.read_text(encoding="utf-8", errors="replace")
        resources = {}
        for key, label in (("lut", "Total LUTs"), ("registers", "Total Registers"),
                           ("drm", "Total DRM")):
            match = re.search(re.escape(label) + r"\s*[=:]\s*([0-9.]+)", text)
            if not match:
                raise RuntimeError("Missing synthesis resource field: " + label)
            resources[key] = float(match.group(1))
        result.update(status="pass", resources=resources,
                      artifact=str(report.relative_to(ROOT)), artifact_sha256=sha256(report))
    except Exception as error:
        result.update(status="fail", error=str(error))
        print(str(error), file=sys.stderr)
    write_json(work / "result.json", result)
    write_json(latest, result)
    print(f"VIDEO_PDS_{result['status'].upper()}: {work}")
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

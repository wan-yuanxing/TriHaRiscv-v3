"""Run the available Video regression suites using native Python/Icarus."""
import argparse
import json
from pathlib import Path
import sys

from common import BUILD, ROOT, fresh_run, input_hashes, run_logged, tool, write_json
from gen_pll import generate as generate_pll


def simulate(work, name, top, sources, includes=(), defines=(), timeout=120):
    binary = work / (name + ".vvp")
    command = [tool("iverilog"), "-g2012", "-Wall", "-s", top, "-o", binary]
    for directory in includes:
        command += ["-I", directory]
    command += ["-D"+define for define in defines]
    run_logged(command + list(sources), work / (name + "_compile.log"))
    return run_logged([tool("vvp"), binary], work / (name + "_simulation.log"), timeout=timeout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=("config", "timing", "clocks", "tx_init", "tx_init_full", "board", "rx", "all"), default="all")
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
        if args.suite != "timing":
            run_logged([sys.executable, ROOT / "scripts/video/prepare_reference.py", "--reference", "hdmi"],
                       work / "reference_check.log")
        manifest_path = ROOT / "fpga/pg2l100h/project/video_timing.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        paths = [ROOT / relative for relative in manifest["sources"] + manifest["tests"]]
        paths += [manifest_path, ROOT / "config/video_cfg.json",
                  ROOT / "rtl/video/include/video_cfg.vh", ROOT / "sw/include/video_cfg.h"]
        paths += list((ROOT / "scripts/video").glob("*.py"))
        paths += list((ROOT / "tb/video").glob("test_*.py"))
        if args.suite in ("clocks", "board", "tx_init", "tx_init_full", "rx", "all"):
            paths += list((ROOT / "fpga/pg2l100h/rtl").glob("*.sv"))
            paths += list((ROOT / "tb/video").glob("*.sv"))
            paths += list((ROOT / "tb/video/models").glob("*.sv"))
            paths += [ROOT / "fpga/pg2l100h/ip/video_pll.json",
                      ROOT / "fpga/pg2l100h/ip/video_reference_manifest.json"]
        result["inputs"] = input_hashes(set(paths))
        if args.suite in ("rx", "all"):
            result["inputs"].update(input_hashes([
                ROOT / "rtl/video/video_rx.sv", ROOT / "fpga/pg2l100h/project/video_rx.json"]))
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
        if args.suite in ("clocks", "all"):
            _, wrapper = generate_pll(work / "ip/video_pll")
            library = tool("pds_shell").parent.parent / "arch/vendor/pango/verilog/simulation"
            primitives = [library / "GTP_GPLL.v", library / "GTP_CLKBUFG.v"]
            from common import sha256
            result["pll_model_inputs"] = {str(path): sha256(path) for path in [wrapper, *primitives]}
            for name, top, extra, marker in (
                ("pll", "tb_pll", [], "VIDEO_PLL_PASS"),
                ("clock_reset", "tb_clock_reset", [ROOT / "fpga/pg2l100h/rtl/video_clock_reset.sv"],
                 "VIDEO_CLOCK_RESET_PASS")):
                log = simulate(work, name, top, [ROOT / f"tb/video/{top}.sv", wrapper,
                                                *primitives, *extra])
                if marker not in log:
                    raise RuntimeError("Missing " + marker)
            result["passed"].append("clocks")
        vendor = ROOT / "build/video/vendor/hdmi/source/hdmi"
        tx_sources = [ROOT / "fpga/pg2l100h/rtl/hdmi_tx_init.sv",
                      vendor / "ms7210_ctl.v", vendor / "iic_dri.v"]
        if args.suite in ("tx_init", "tx_init_full", "all"):
            log = simulate(work, "tx_init", "tb_hdmi_tx_init",
                           [*tx_sources, ROOT / "tb/video/tb_hdmi_tx_init.sv",
                            ROOT / "tb/video/models/ms7210_i2c_model.sv"],
                           defines=["HDMI_TX_INIT_FULL_WAIT"] if args.suite=="tx_init_full" else [])
            if "HDMI_TX_INIT_PASS" not in log:
                raise RuntimeError("Missing HDMI_TX_INIT_PASS")
            result["passed"].append("tx_init_full" if args.suite=="tx_init_full" else "tx_init")
        if args.suite in ("board", "all"):
            board_path = ROOT / "fpga/pg2l100h/project/video_board_smoke.json"
            board = json.loads(board_path.read_text(encoding="utf-8"))
            from common import sha256
            result["inputs"].update(input_hashes([board_path]))
            result["vendor_inputs"] = {str(path.relative_to(ROOT)): sha256(path)
                                       for path in tx_sources[1:]}
            log = simulate(work, "board", board["test_top"],
                           [*[ROOT / path for path in board["sources"] + board["tests"]],
                            *tx_sources[1:]], [ROOT / "rtl/video/include"])
            if "VIDEO_BOARD_SMOKE_PASS" not in log:
                raise RuntimeError("Missing VIDEO_BOARD_SMOKE_PASS")
            result["passed"].append("board")
        if args.suite in ("rx", "all"):
            rx=json.loads((ROOT / "fpga/pg2l100h/project/video_rx.json").read_text(encoding="utf-8"))
            log=simulate(work,"rx",rx["test_top"],
                         [ROOT / path for path in rx["sources"]+rx["tests"]],
                         [ROOT / "rtl/video/include"],timeout=600)
            if "VIDEO_RX_PASS" not in log:
                raise RuntimeError("Missing VIDEO_RX_PASS")
            result["passed"].append("rx")
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

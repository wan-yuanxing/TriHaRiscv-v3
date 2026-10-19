"""Independently verify frozen board inputs, physical pins and actual final STA."""
import argparse
import json
from pathlib import Path
import re
import sys

from gen_board import ROOT, validate
from run import sha, save


def review(work):
    work = Path(work).resolve()
    result = json.loads((work / "result.json").read_text(encoding="utf-8"))
    assert result["status"] in ("PASS", "TIMING_FAIL") and result["flow_status"] == "PASS"
    assert result["source_unchanged"] and not result["programmed"] and not result["board_validated"]
    for name, digest in result["input_hashes"].items():
        assert sha(ROOT / name) == sha(work / "src" / name) == digest, name
    for name, digest in result["output_hashes"].items():
        assert sha(work / name) == digest, name
    for name, digest in result["evidence_hashes"].items():
        assert sha(Path(name)) == digest, name
    for native in result["native_commands"]:
        assert native["return_code"] == 0 and not native["timed_out"]
        assert sha(Path(native["tool"])) == result["pds_shell_sha256"]
    config = json.loads((work / "src/config/cpu_board.json").read_text(encoding="utf-8"))
    validate(config)
    for kind in ("clocks", "system"):
        directory = Path(result[kind + "_directory"])
        evidence = json.loads((directory / "result.json").read_text(encoding="utf-8"))
        assert evidence["status"] == "PASS" and evidence["test"] == kind and evidence["fault"] == "none"
        assert evidence["source_unchanged"] and evidence["external_unchanged"]
        for name, digest in evidence["input_hashes"].items():
            assert sha(ROOT / name) == sha(directory / "src" / name) == digest, name
        for name, digest in evidence["external_hashes"].items():
            assert sha(Path(name)) == digest, name
        for name in ("rom.hex", "sram.hex", "firmware.elf") if kind == "system" else ("ip/cpu_board_pll.v",):
            assert sha(work / name) == sha(directory / name)
    pll = json.loads((Path(result["clocks_directory"]) / "ip/provenance.json").read_text(encoding="utf-8"))
    assert pll["cpu_hz"] == 100_000_000 and pll["pfd_hz"] == 25_000_000 and pll["vco_hz"] == 800_000_000
    assert sha(work / "ip/cpu_board_pll.v") == pll["wrapper_sha256"]
    log = (work / "pds-board.stdout.log").read_text(encoding="utf-8")
    assert not re.search(r"(?im)^\s*(E:|ERROR[: ]|FATAL[: ])", log)
    for stage in ("compile", "synthesize", "dev_map", "pnr", "report_timing"):
        assert re.search(r"(?m)^Executing : " + stage + r"(?: [^\r\n]*)? successfully\.", log), stage
    fdc = (work / "src/fpga/pg2l100h/constraints/cpu_board.fdc").read_text(encoding="utf-8")
    assert not re.search(r"(?im)^\s*set_(false_path|multicycle_path|clock_groups)", fdc)
    assert "-multiply_by 4 -divide_by 5" in fdc
    assert "set_clock_uncertainty 0.100" in fdc and "set_clock_uncertainty 0.050" in fdc
    assert "set_output_delay 2.000" in fdc and "set_output_delay 0.500" in fdc
    chosen = re.findall(r"The Best Seed is (\d+)\.", log)
    assert len(chosen) <= 1
    selected_seed = int(chosen[0]) if chosen else result["placement_seed"]
    physical_path = work / "place_route/triha_cpu_board_top.prr"
    if chosen:
        recipe = json.loads((work / "src/fpga/pg2l100h/project/cpu_board.json").read_text(encoding="utf-8"))
        assert result["placement_seed"] <= selected_seed < result["placement_seed"] + recipe["placement_trials"]
        physical_path = work / f"place_route/seed_{selected_seed}/triha_cpu_board_top.prr"
    physical = physical_path.read_text(encoding="utf-8")
    reference = (work / "src/fpga/pg2l100h/constraints/video_ddr_bist.fdc").read_text(encoding="utf-8")
    aliases = dict(ref_clk_pi="ref_clk_p", ref_clk_ni="ref_clk_n", rst_ni="rst_in", uart_tx_o="uart_tx",
                   **{f"led_o[{i}]": name for i, name in enumerate(("heart_beat_led", "ddr_init_done", "init_over_rx", "hdmi_int_led"))})
    for port, pin in config["pins"].items():
        old_port = aliases[port]
        for attribute, value in (("PAP_IO_LOC", pin["location"]), ("PAP_IO_STANDARD", pin["standard"]), ("PAP_IO_VCCIO", pin["vccio"])):
            assert f"define_attribute {{p:{old_port}}} {{{attribute}}} {{{value}}}" in reference
        lines = [line for line in physical.splitlines() if line.startswith("|") and line.split("|")[1].strip() == port]
        assert len(lines) == 1, (port, "missing physical pin")
        columns = [column.strip() for column in lines[0].split("|")]
        assert all(pin[key] in columns for key in ("location", "standard", "vccio")), (port, "wrong actual pin/electrical standard")
    report = (work / "report_timing/triha_cpu_board_top.rtr").read_text(encoding="utf-8")
    assert re.search(r"Timing analysis mode\s*:\s*multi corner", report)
    assert re.search(r"(?m)^\s*cpu_clk\s+10\.0000\s+\{0\.0000 5\.0000\}", report)
    rows = []
    for corner in ("Slow", "Fast"):
        for kind in ("Setup", "Hold", "Minimum Pulse Width"):
            sections = re.findall(r"(?ms)^" + re.escape(f"{kind} Summary({corner} Corner):") + r"\r?\n(.*?)(?=^={10,})", report)
            assert len(sections) == 1, (corner, kind)
            pattern = r"(?m)^\s*cpu_clk\s+" + (r"cpu_clk\s+" if kind != "Minimum Pulse Width" else "") + r"(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$"
            matches = re.findall(pattern, sections[0])
            assert len(matches) == 1
            slack, tns, bad, count = matches[0]
            row = dict(corner=corner, check=kind, slack_ns=float(slack), total_negative_slack_ns=float(tns), failing_endpoints=int(bad), endpoints=int(count))
            assert row in result["timing"]["corners"]
            rows.append(row)
    worst = min(row["slack_ns"] for row in rows if row["check"] == "Setup")
    reset_checks = []
    for corner in ("Slow", "Fast"):
        for kind in ("Recovery", "Removal"):
            section = re.search(r"(?ms)^" + re.escape(f"{kind} Summary({corner} Corner):") + r"\r?\n(.*?)(?=^={10,})", report)
            assert section, (corner, kind)
            match = re.search(r"(?m)^\s*cpu_clk\s+cpu_clk\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$", section[1])
            assert match
            reset_checks.append(dict(corner=corner, check=kind, slack_ns=float(match[1]), failing_endpoints=int(match[3])))
    perf = re.findall(r"(?m)^\s*cpu_clk\s+100\.0000 MHz\s+\d+\.\d+ MHz\s+10\.0000\s+\d+\.\d+\s+(-?\d+\.\d+)\s*$", report)
    assert len(perf) == 1 and abs(float(perf[0]) - worst) <= .001
    met = all(row["slack_ns"] >= 0 and row["failing_endpoints"] == 0 and row["endpoints"] > 0 for row in rows)
    met = met and bool(re.search(r"Design Summary\s*:\s*All Constraints Met\.", report))
    if met:
        assert all(row["slack_ns"] >= 0 and row["failing_endpoints"] == 0 for row in reset_checks)
    assert met == result["timing_closed"] == (result["status"] == "PASS")
    assert result["runner_return_code"] == (0 if met else 2)
    if met:
        assert result["bitstream_generated"]
        assert sha(Path(result["bitstream_input_db"])) == result["bitstream_input_db_sha256"]
        bit_log = (work / "pds-bitstream.stdout.log").read_text(encoding="utf-8")
        assert not re.search(r"(?im)^\s*(E:|ERROR[: ]|FATAL[: ])", bit_log)
        assert re.search(r"(?m)^Executing : gen_bit_stream(?: [^\r\n]*)? successfully\.", bit_log)
        for suffix in ("sbit", "smsk"):
            assert (work / ("generate_bitstream/triha_cpu_board_top." + suffix)).stat().st_size > 0
    snr = (work / "synthesize/triha_cpu_board_top.snr").read_text(encoding="utf-8")
    match = re.search(r"(?m)^\|[ +]*u_core\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+([\d.]+)", snr)
    assert match, "missing CPU-only hierarchy resources"
    resources = dict(lut=int(match[1]), ff=int(match[2]), distributed_ram=int(match[3]), apm=int(match[4]), drm36k_equivalent=float(match[5]))
    assert resources["drm36k_equivalent"] == 0 and resources["apm"] == 4
    return dict(status="PASS", timing_closed=met, scope="Independently verified board post-route; no physical execution",
                review_tool_sha256=sha(Path(__file__)),
                route_directory=str(work), route_result_sha256=sha(work / "result.json"),
                selected_seed=selected_seed, selected_physical_report_sha256=sha(physical_path),
                corners=rows, reset_checks=reset_checks, worst_setup_ns=worst, cpu_hierarchy_resources=resources,
                actual_pins=config["pins"], pll=pll, programmed=False, board_validated=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = review(args.directory)
        if args.output:
            save(args.output, result)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (OSError, ValueError, AssertionError, KeyError) as error:
        print("CPU_BOARD_REVIEW_FAIL:", repr(error), file=sys.stderr)
        raise SystemExit(1)

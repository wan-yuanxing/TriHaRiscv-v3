"""Independently re-read the terminal system route and its frozen evidence."""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def review(work, native_sram=None):
    result = json.loads((work / "result.json").read_text(encoding="utf-8"))
    assert result["status"] in ("PASS", "TIMING_FAIL") and result["flow_status"] == "PASS"
    assert result["source_unchanged"]
    assert result["native_commands"][-1]["return_code"] == 0
    assert not result["native_commands"][-1]["timed_out"]
    for name, digest in result["input_hashes"].items():
        assert sha(work / "src" / name) == sha(ROOT / name) == digest, name
    for name, digest in result["output_hashes"].items():
        assert sha(work / name) == digest, name
    for name, digest in result["firmware_hashes"].items():
        assert sha(Path(name)) == digest, name
    assert sha(Path(result["native_commands"][-1]["tool"])) == result["pds_shell_sha256"]
    assert sha(work / "rom.hex") == sha(Path(result["firmware_directory"]) / "rom.hex")
    assert sha(work / "sram.hex") == sha(Path(result["firmware_directory"]) / "sram.hex")
    fdc = (work / "src/fpga/pg2l100h/constraints/cpu_minimal_soc.fdc").read_text(encoding="utf-8")
    assert not re.search(r"(?im)^\s*set_(false_path|multicycle_path|clock_groups)", fdc)
    assert "-period 10.000" in fdc and "set_clock_uncertainty 0.100" in fdc and "set_clock_uncertainty 0.050" in fdc
    report = (work / "report_timing/triha_minimal_soc.rtr").read_text(encoding="utf-8")
    assert "Timing analysis mode          : multi corner" in report or re.search(r"Timing analysis mode\s*:\s*multi corner", report)
    rows = []
    for corner in ("Slow", "Fast"):
        for kind in ("Setup", "Hold", "Minimum Pulse Width"):
            section = re.search(r"(?ms)^" + re.escape(f"{kind} Summary({corner} Corner):") + r"\r?\n(.*?)(?=^={10,})", report)
            assert section, (corner, kind)
            pattern = r"(?m)^\s*cpu_clk\s+" + (r"cpu_clk\s+" if kind != "Minimum Pulse Width" else "") + r"(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$"
            match = re.search(pattern, section[1])
            assert match
            row = dict(corner=corner, check=kind, slack_ns=float(match[1]), total_negative_slack_ns=float(match[2]), failing_endpoints=int(match[3]), endpoints=int(match[4]))
            assert row in result["timing"]["corners"]
            rows.append(row)
    worst = min(row["slack_ns"] for row in rows if row["check"] == "Setup")
    performance = re.search(r"(?m)^\s*cpu_clk\s+100\.0000 MHz\s+\d+\.\d+ MHz\s+10\.0000\s+\d+\.\d+\s+(-?\d+\.\d+)\s*$", report)
    assert performance and abs(float(performance[1]) - worst) <= .001
    passed = all(r["slack_ns"] >= 0 and r["failing_endpoints"] == 0 and r["endpoints"] > 0 for r in rows)
    assert passed == result["timing_closed"] == (result["status"] == "PASS")
    assert result["runner_return_code"] == (0 if passed else 2)
    log = (work / "pds-route.stdout.log").read_text(encoding="utf-8")
    for stage in ("compile", "synthesize", "dev_map", "pnr", "report_timing"):
        assert re.search(r"(?m)^Executing : " + stage + r"(?: [^\r\n]*)? successfully\.", log)
    snr = (work / "synthesize/triha_minimal_soc.snr").read_text(encoding="utf-8")
    resource_rows = {}
    for name in ("u_core", "u_memory"):
        match = re.search(r"(?m)^\| \+ " + name + r"\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+(?:\.\d+)?)", snr)
        assert match
        resource_rows[name] = dict(lut=int(match[1]), ff=int(match[2]), distributed_ram=int(match[3]), apm=int(match[4]), drm36k_equivalent=float(match[5]))
    mapping = (work / "synthesize/apm_drm_lutram_utilization.log").read_text(encoding="utf-8")
    assert "READ_BEFORE_WRITE" in mapping and "GTP_DRM36K_E1" in mapping and resource_rows["u_core"]["drm36k_equivalent"] == 0
    starts = re.findall(r"(?m)^Startpoint\s*:\s*(.*)$", report)
    ends = re.findall(r"(?m)^Endpoint\s*:\s*(.*)$", report)
    physical = (work / "place_route/triha_minimal_soc.prr").read_text(encoding="utf-8")
    io_register_ports = []
    for line in physical.splitlines():
        if "LVCMOS33" in line:
            columns = [cell.strip() for cell in line.split("|")][1:]
            if columns[-1] == "OREGIS":
                io_register_ports.append(columns[0])
    region_applied = "PAP_REGION" in (work / "device_map/triha_minimal_soc.dmr").read_text(encoding="utf-8")
    native_evidence = None
    if native_sram:
        native_result = json.loads((native_sram / "result.json").read_text(encoding="utf-8"))
        assert native_result["status"] == "PASS" and native_result["source_unchanged"] and native_result["corruption_rejected"]
        assert native_result["checks"] == 12296
        assert native_result["input_hashes"]["rtl/soc/triha_sram.v"] == result["input_hashes"]["rtl/soc/triha_sram.v"]
        assert native_result["image_sha256"] == sha(work / "sram.hex")
        for name, digest in native_result["output_hashes"].items():
            assert sha(native_sram / name) == digest, name
        for name, digest in native_result["external_hashes"].items():
            assert sha(Path(name)) == digest, name
        native_evidence = dict(result=str(native_sram / "result.json"), sha256=sha(native_sram / "result.json"),
                               scope="Standalone SRAM synthesis netlist with the same RTL and image; not full system gate simulation")
    return dict(status=result["status"], result=str(work / "result.json"), result_sha256=sha(work / "result.json"),
                reviewer_sha256=sha(Path(__file__)), all_recorded_hashes_verified=True, constraints_100mhz_no_exceptions=True,
                actual_native_return_code=0, runner_return_code=result["runner_return_code"], timing=rows,
                performance_slack_ns=float(performance[1]), mapped_system_resources=result["mapped_system_resources"],
                synthesis_hierarchy_resources=resource_rows, native_ram_mapping_checked=True,
                native_ram_component_functional_simulation=native_evidence is not None, native_ram_component_evidence=native_evidence,
                full_system_gate_simulation=False,
                physical_io_register_ports=io_register_ports, physical_io_register_count=len(io_register_ports),
                mapped_ff_scope="CLM FF reported by dev_map; IO registers listed separately; not an architectural state count",
                cpu_region_constraint_expanded_in_native_report=region_applied,
                worst_reported_startpoint=starts[0] if starts else None, worst_reported_endpoint=ends[0] if ends else None,
                timing_report=str(work / "report_timing/triha_minimal_soc.rtr"),
                log=str(work / "pds-route.stdout.log"), board_validated=False, official_coremark_score=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--native-sram-directory", type=Path)
    args = parser.parse_args()
    try:
        receipt = review(args.directory.resolve(), args.native_sram_directory.resolve() if args.native_sram_directory else None)
        if args.output:
            args.output.write_bytes((json.dumps(receipt, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
        sys.exit(0 if receipt["status"] == "PASS" else 2)
    except Exception as error:
        print("SOC_ROUTE_REVIEW_FAIL", repr(error))
        sys.exit(1)

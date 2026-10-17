"""Standalone preview-display regression; artifacts stay in ignored build/video."""
from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path
import shutil
import subprocess
import sys
import uuid


ROOT = Path(__file__).resolve().parents[2]
BUILD_ROOT = ROOT / "build/video/preview_display"
SOURCES = [ROOT / "rtl/video/preview_display.sv", ROOT / "tb/video/tb_preview_display.sv"]


def main() -> int:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    BUILD = BUILD_ROOT / f"run_{stamp}_{uuid.uuid4().hex[:8]}"
    BUILD.mkdir(parents=True, exist_ok=False)
    proof_path = BUILD / "proof.json"
    inputs = [*SOURCES, Path(__file__).resolve()]
    input_bytes = {path: path.read_bytes() for path in inputs}
    input_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(data).hexdigest() for path, data in input_bytes.items()}
    # Compile immutable copies so every tool consumes the exact hashed input.
    for path, data in input_bytes.items():
        snapshot = BUILD / "inputs" / path.relative_to(ROOT)
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        snapshot.write_bytes(data)
    manifest = {"status": "RUNNING", "started_utc": stamp, "sources_sha256": input_hashes}
    (BUILD / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    def check_inputs() -> None:
        current = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        if current != input_hashes:
            (BUILD / "input_drift.json").write_text(json.dumps({"before": input_hashes, "after": current}, indent=2) + "\n", encoding="utf-8")
            raise RuntimeError(f"Input hash drift during preview regression: {BUILD}")

    iverilog = os.environ.get("TRIHA_IVERILOG") or shutil.which("iverilog")
    vvp = os.environ.get("TRIHA_VVP") or shutil.which("vvp")
    if not iverilog or not vvp:
        raise RuntimeError("iverilog/vvp unavailable")
    cases = []

    def run(name: str, args: list[str], require_pass: bool = False) -> str:
        check_inputs()
        try:
            result = subprocess.run(args, cwd=ROOT, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=180)
        except subprocess.TimeoutExpired as exc:
            (BUILD / f"{name}.log").write_text(f"TIMEOUT after 180 seconds: {args}\n{exc.stdout or ''}\n{exc.stderr or ''}", encoding="utf-8")
            raise RuntimeError(f"{name} exceeded 180-second subprocess bound; evidence: {BUILD}") from exc
        output = result.stdout + result.stderr
        (BUILD / f"{name}.log").write_text(output, encoding="utf-8")
        check_inputs()
        if result.returncode or "warning:" in output.lower() or (require_pass and "PASS preview_display" not in output):
            raise RuntimeError(f"{name} failed ({result.returncode}):\n{output}")
        cases.append({"name": name, "command": args, "returncode": result.returncode, "log": str(BUILD / f"{name}.log")})
        if require_pass:
            print(output.splitlines()[0], flush=True)
        return output

    compiled_sources = [BUILD / "inputs" / path.relative_to(ROOT) for path in SOURCES]
    run("compile_small", [iverilog, "-g2012", "-Wall", "-s", "tb_preview_display", "-o", str(BUILD / "small.vvp"), *map(str, compiled_sources)])
    for mode in range(27):
        run(f"small_case_{mode:02}", [vvp, str(BUILD / "small.vvp"), f"+CASE={mode}"], True)
    for index, args in enumerate((["+CORE_HALF=3", "+PIXEL_HALF=10.5"], ["+CORE_HALF=5", "+PIXEL_HALF=16.5"])):
        run(f"clock_ratio_{index}", [vvp, str(BUILD / "small.vvp"), *args], True)
    run("compile_invalid_window", [iverilog, "-g2012", "-Wall", "-s", "tb_preview_display", "-Ptb_preview_display.INVALID_WINDOW=1", "-o", str(BUILD / "invalid_window.vvp"), *map(str, compiled_sources)])
    run("invalid_window", [vvp, str(BUILD / "invalid_window.vvp")], True)
    run("compile_full", [iverilog, "-g2012", "-Wall", "-s", "tb_preview_display", "-Ptb_preview_display.FULL=1", "-o", str(BUILD / "full.vvp"), *map(str, compiled_sources)])
    run("full_800x600", [vvp, str(BUILD / "full.vvp")], True)
    bundle_map = [
        {"source": "mailbox_base[31:0]", "destination": "pending_base[31:0]", "toggle": "record_toggle -> record_sync1 -> record_sync2"},
        {"source": "mailbox_stride[31:0]", "destination": "pending_stride[31:0]", "toggle": "record_toggle -> record_sync1 -> record_sync2"},
        {"source": "mailbox_frame[31:0]", "destination": "pending_frame[31:0]", "toggle": "record_toggle -> record_sync1 -> record_sync2"},
        {"source": "mailbox_slot[1:0]", "destination": "pending_slot[1:0]", "toggle": "record_toggle -> record_sync1 -> record_sync2"},
        {"source": "req_base[0/1][31:0]", "destination": "dma_base_latched[31:0]", "toggle": "request_toggle[0/1] -> request_sync1 -> request_sync2"},
        {"source": "req_stride[0/1][31:0]", "destination": "dma_stride_latched[31:0]", "toggle": "request_toggle[0/1] -> request_sync1 -> request_sync2"},
        {"source": "req_row[0/1][10:0]", "destination": "dma_row_latched[10:0]", "toggle": "request_toggle[0/1] -> request_sync1 -> request_sync2"},
        {"source": "bank_success[1:0]", "destination": "bank_ready[1:0]", "toggle": "done_toggle[1:0] -> done_sync1 -> done_sync2"},
        {"source": "commit_pixel_id[31:0]", "destination": "commit_frame_id[31:0],frame_id[31:0]", "toggle": "commit_toggle -> commit_sync1 -> commit_sync2"},
        {"source": "commit_pixel_slot[1:0]", "destination": "commit_slot[1:0]", "toggle": "commit_toggle -> commit_sync1 -> commit_sync2"},
        {"source": "release_pixel_id[31:0]", "destination": "release_frame_id[31:0]", "toggle": "release_toggle -> release_sync1 -> release_sync2"},
        {"source": "release_pixel_slot[1:0]", "destination": "release_slot[1:0]", "toggle": "release_toggle -> release_sync1 -> release_sync2"},
    ]
    proof = {
        "status": "PASS",
        "sources_sha256": input_hashes,
        "run_directory": str(BUILD),
        "started_utc": stamp,
        "tools": {"iverilog": subprocess.run([iverilog, "-V"], text=True, capture_output=True, timeout=30).stdout.splitlines()[0], "vvp": str(vvp)},
        "cases": cases,
        "oracle": "Independent byte-memory formula(address), AXI advertised-beat checks, output pixel/timing oracle; no hierarchical DUT references.",
        "subprocess_timeout_seconds": 180,
        "cdc_bundles": bundle_map,
        "cdc_bundle_constraint": "set_max_delay -datapath_only 6ns source Q -> destination D; exempt only scalar first synchronizer D, never whole clock groups.",
        "cdc_hold": {
            "mailbox": "acceptance through core commit-event ready handshake; mailbox can change only on next accepted record",
            "requests": "issue through synchronized done, then until both window consumers retire; next request acknowledges done",
            "success": "done toggle publication through next synchronized request",
            "events": "publication through core valid/ready handshake and two-stage return ack; no new event until ack returns",
            "ram": "core writes only its granted bank; pixel reads only completed matching row/frame/epoch; recycle two pixel edges after final raw pixel",
        },
        "cdc_scalars": [
            "request_toggle -> request_sync1 -> request_sync2", "done_toggle -> done_sync1 -> done_sync2",
            "record_toggle -> record_sync1 -> record_sync2", "commit_toggle -> commit_sync1 -> commit_sync2",
            "release_toggle -> release_sync1 -> release_sync2", "commit_ack -> commit_ack_sync1 -> commit_ack_sync2",
            "release_ack -> release_ack_sync1 -> release_ack_sync2", "scan_toggle -> scan_sync1 -> scan_sync2",
            "underflow_toggle -> underflow_sync1 -> underflow_sync2", "error -> fault_sync1 -> fault_sync2",
        ],
        "counter_domain": "All public counters and frame_id are core registers. completed_scans/underflows increment once per synchronized pixel event. commits/frame_id update from held commit bundle. read_lines increments at validated final AXI beat.",
        "limits": "Component simulation only; requires coordinated resets, separately constrained physical implementation and external ddr_ready core-domain synchronization. Errors require coordinated reset. WINDOW_Y >= 1; preview width <=1024, height <=2048, window end <=2048. DDR descriptor span [80000000,88000000).",
    }
    check_inputs()
    proof_path.write_text(json.dumps(proof, indent=2) + "\n", encoding="utf-8")
    print(f"PASS proof: {proof_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError) as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(1)

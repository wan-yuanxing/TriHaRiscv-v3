"""Native PDS component/board builds, with separate internal and I/O timing status."""
import argparse
import json
from pathlib import Path
import re
import shutil
import sys

from common import BUILD, ROOT, fresh_run, input_hashes, run_logged, sha256, tool, write_json
from gen_pll import generate as generate_pll
from gen_ddr import generate as generate_ddr


def tcl_path(path):
    text = Path(path).resolve().as_posix()
    if any(char in text for char in "{}\n\r"):
        raise ValueError("Tcl path contains an unsupported brace/newline")
    return "{" + text + "}"


def review_messages(log, verified_fdc=""):
    pins = dict(re.findall(r"define_attribute \{p:([^}]+)\} \{PAP_IO_LOC\} \{([^}]+)\}", verified_fdc))
    reviewed, rejected = [], []
    for line in log.splitlines():
        if not line.lstrip().startswith(("E:", "C:")):
            continue
        match = re.fullmatch(
            r"C: ConstraintEditor-2002: \[.*\] \| Port (\S+) has been placed at location (\S+), whose type is share pin\.", line)
        if match and pins.get(match[1]) == match[2]:
            reviewed.append(line)
        else:
            rejected.append(line)
    return reviewed, rejected


def verify_mode_key_reference(reference, fdc):
    """Allow only the KEY1 mapping cross-checked against the official manual."""
    expected = {'PAP_IO_DIRECTION': 'INPUT', 'PAP_IO_LOC': 'C23',
                'PAP_IO_VCCIO': '3.3', 'PAP_IO_STANDARD': 'LVCMOS33', 'PAP_IO_NONE': 'TRUE'}
    if (reference.get('port') != 'mode_button_n' or reference.get('board_label') != 'KEY1'
            or reference.get('pin') != 'C23' or reference.get('active_low') is not True
            or reference.get('attributes') != expected):
        raise ValueError('MODE key reference differs from verified KEY1/C23 mapping')
    attributes = re.findall(r'define_attribute \{p:mode_button_n\} \{([^}]+)\} \{([^}]+)\}', fdc)
    if len(attributes) != len(expected) or dict(attributes) != expected:
        raise ValueError('MODE key FDC differs from verified KEY1 electrical attributes')
    return 'define_attribute {p:mode_button_n} {PAP_IO_LOC} {C23}\n'


def combined_route_options(seed_start=4, seed_count=6, mode=None):
    if (type(seed_start) is not int or type(seed_count) is not int
            or seed_start<1 or not 1<=seed_count<=64 or seed_start+seed_count-1>2147483647
            or mode not in (None, 'normal', 'performance')):
        raise ValueError('Invalid placement seed range or mode')
    options = (f' -gplace_seed {seed_start} -gplace_times {seed_count} -seed_step 1'
               ' -saved_outcome 1 -parallel 1')
    return options+((' -mode '+mode) if mode is not None else '')


def verify_build_inputs(work, result):
    """Bind the source bytes, copied compile inputs and generated vendor inputs."""
    for name, expected in result['inputs'].items():
        if sha256(ROOT/name) != expected:
            raise ValueError('Build input changed since hashing: '+name)
    for name, expected in result.get('snapshot_inputs', {}).items():
        if sha256(work/'src'/name) != expected:
            raise ValueError('Build source snapshot differs from hashed input: '+name)
    for name, expected in result.get('vendor_inputs', {}).items():
        if sha256(work/name) != expected:
            raise ValueError('Generated vendor input changed during build: '+name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("video_timing", "video_rx", "video_board_smoke", "video_rx_board", "video_ddr_bist", "video_axi_capture", "video_hdmi_capture", "video_preview_board", "video_detect_scale", "video_input_pad", "video_c8_pack", "video_detect_bilinear", "video_nchw_dma", "video_three_capture", "video_capture_rearm", "video_three_board", "video_capture_mmio", "video_capture_v2", "video_shared_ddr", "cpu_native_axil", "video_raw_display", "video_raw_board", "video_mode_board", "video_button_debounce", "video_mode_control", "video_overlay", "video_mode_cdc", "video_avatar_cache", "video_mode_output", "video_display_slot_owner", "video_display_mmio"), default="video_timing")
    parser.add_argument("--stage", choices=("synth", "route", "bitstream"), default="synth")
    parser.add_argument('--seed-start', type=int, default=4)
    parser.add_argument('--seed-count', type=int, default=6)
    parser.add_argument('--pnr-mode', choices=('normal', 'performance'))
    args = parser.parse_args()
    try:
        placement_options = combined_route_options(args.seed_start, args.seed_count, args.pnr_mode)
    except ValueError as error:
        parser.error(str(error))
    hdmi = args.target in ("video_board_smoke", "video_rx_board", "video_hdmi_capture", "video_preview_board", "video_three_board", "video_raw_board", "video_mode_board")
    ddr = args.target in ("video_ddr_bist", "video_axi_capture", "video_hdmi_capture", "video_preview_board", "video_three_board", "video_raw_board", "video_mode_board")
    board = hdmi or ddr
    if not board and args.stage != "synth":
        parser.error("Component targets have no board pins; only synth is supported")
    work = fresh_run("pds")
    latest = BUILD / "latest_pds.json"
    target_latest = BUILD / f"latest_pds_{args.target}.json"
    result = {"status": "running", "target": args.target, "stage": args.stage,
              "directory": str(work.relative_to(ROOT)), "physical_board": False,
              "timing_closed": False, "vendor_ddr_training": False,
              "internal_timing_met": False, "external_io_timing_verified": False,
              "scope": ("TX-only board color bars; no RX/DDR; external I/O AC requirements unverified"
                        if board else "standalone component synthesis; no board pins or DDR")}
    write_json(latest, result)
    write_json(target_latest, result)
    try:
        run_logged([sys.executable, ROOT / "scripts/video/gen_config.py", "--check"],
                   work / "config_check.log")
        manifest_path = ROOT / f"fpga/pg2l100h/project/{args.target}.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        result["scope"] = manifest["scope"]
        top = manifest["top"]
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", top):
            raise ValueError("Invalid top module")
        names = manifest["sources"] + manifest["constraints"] + [
            "rtl/video/include/video_cfg.vh", "config/video_cfg.json",
            manifest_path.relative_to(ROOT).as_posix()]
        if args.target=='video_capture_mmio':
            run_logged([sys.executable,ROOT/'scripts/video/gen_regs.py','--check'],work/'regs_check.log')
            names += ['config/video_regs.json','rtl/video/include/video_regs.vh',
                      'sw/include/video_regs.h','scripts/video/gen_regs.py']
        if args.target=='video_capture_v2':
            run_logged([sys.executable,ROOT/'scripts/video/gen_capture_v2.py','--check'],work/'capture_v2_abi_check.log')
            names += ['config/video_capture_v2.json','rtl/video/include/video_capture_v2.vh',
                      'sw/include/video_capture_v2.h','scripts/video/gen_capture_v2.py']
        if args.target=='video_display_mmio':
            run_logged([sys.executable,ROOT/'scripts/video/gen_display_abi.py','--check'],work/'display_abi_check.log')
            names += ['config/video_display.json','rtl/video/include/video_display.vh',
                      'sw/include/video_display_abi.h','scripts/video/gen_display_abi.py']
        if args.target in ("video_rx_board", "video_hdmi_capture", "video_preview_board", "video_three_board", "video_raw_board", "video_mode_board"):
            run_logged([sys.executable, ROOT / "scripts/video/gen_edid.py", "--check"], work/"edid_check.log")
            names += ["rtl/video/include/video_edid.vh", "config/video_edid.hex", "scripts/video/gen_edid.py"]
        if args.target == 'video_mode_board':
            names += [manifest['pin_reference']]
        if ddr:
            names += [manifest['ddr_ip'], 'scripts/video/gen_ddr.py',
                      'fpga/pg2l100h/ip/video_reference_manifest.json']
        result["inputs"] = input_hashes([ROOT / name for name in names] +
            [ROOT / "scripts/video" / name for name in
             ("build_pds.py", "common.py", "gen_config.py", "gen_pll.py")])
        result['snapshot_inputs'] = {}
        for name in names:
            destination = work / "src" / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
            if sha256(destination) != result['inputs'][name]:
                raise ValueError('Build source snapshot differs from hashed input: '+name)
            result['snapshot_inputs'][name] = result['inputs'][name]
        vendor_sources = []
        if hdmi:
            _, wrapper = generate_pll(work / "ip/video_pll")
            vendor_sources.append(wrapper)
            reference = json.loads((ROOT / "fpga/pg2l100h/ip/video_reference_manifest.json").read_text(encoding="utf-8"))
            expected = {item["path"]: item["sha256"] for item in reference["references"]["hdmi"]["files"]}
            for relative in manifest["vendor_sources"]:
                source = ROOT / "build/video/vendor/hdmi" / relative
                if sha256(source) != expected[relative]:
                    raise ValueError("Vendor source hash mismatch: " + relative)
                destination = work / "vendor" / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
                vendor_sources.append(destination)
            result["vendor_inputs"] = {str(path.relative_to(work)): sha256(path)
                                       for path in vendor_sources}
            result["inputs"].update(input_hashes([
                ROOT / "fpga/pg2l100h/ip/video_pll.json",
                ROOT / "fpga/pg2l100h/ip/video_reference_manifest.json"]))
        if ddr:
            # The IDF loads the exact 74 generated/protected sources once.
            # Its generated generic pin FDC is never added to this project.
            idf, provenance = generate_ddr(work / 'ip/ddr')
            vendor_sources.append(idf)
            result['ddr_ip_provenance'] = provenance
            result.setdefault('vendor_inputs',{}).update({str(idf.relative_to(work)): sha256(idf)})
        lines = ["set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676"]
        lines += ["add_design " + tcl_path(work / "src" / name)
                  for name in manifest["sources"]]
        lines += ["add_design " + tcl_path(path) for path in vendor_sources]
        lines += ["add_constraint " + tcl_path(work / "src" / name)
                  for name in manifest["constraints"]]
        lines += [f"compile -system_verilog -top_module {top} -include_path {{" +
                  tcl_path(work / "src/rtl/video/include") + "}", "synthesize -ads"]
        if args.stage in ("route", "bitstream"):
            route="pnr -optimize_multi_corner_timing -fix_hold_violation"
            if ddr:
                route += " -slack_prior_in_global_router TRUE"
            if args.target in ("video_hdmi_capture", "video_preview_board", "video_three_board", "video_raw_board", "video_mode_board"):
                # The combined HDMI/DDR target is route-limited. Try six
                # deterministic placements serially (default 4..9); the final
                # report still has to meet every constraint before packaging.
                route += placement_options
                result['pnr_configuration'] = {'seed_start': args.seed_start, 'seed_count': args.seed_count,
                                               'mode': args.pnr_mode or 'normal'}
            lines += ["dev_map",route,"report_timing"]
        if args.stage == "bitstream":
            lines += ["gen_bit_stream -scbv {High Voltage}"]
        script = work / "build.tcl"
        script.write_text("\n".join(lines) + "\n", encoding="utf-8")
        verify_build_inputs(work, result)
        executable = tool("pds_shell")
        if args.target in ('cpu_native_axil', 'video_raw_display'):
            result['pds_executable'] = str(executable)
            result['pds_executable_sha256'] = sha256(executable)
        result["pds_version"] = run_logged(
            [executable, "-version"], work / "version.log").strip()
        verify_build_inputs(work, result)
        log = run_logged([executable, "-file", script, "-work_dir", work,
                          "-project_name", args.target], work / "synth.log",
                         cwd=work, timeout=3600 if args.target in ("video_hdmi_capture", "video_preview_board", "video_three_board", "video_raw_board", "video_mode_board") else 1800 if ddr else 900)
        reference_fdc = ""
        if board:
            reference = json.loads((ROOT / 'fpga/pg2l100h/ip/video_reference_manifest.json').read_text(encoding='utf-8'))
            expected = {item['path']: item['sha256'] for item in reference['references']['hdmi']['files']}
            reference_path = ROOT / "build/video/vendor/hdmi/HDMI_IN_DDR3_HDMI_OUT_top.fdc"
            if sha256(reference_path) != expected["HDMI_IN_DDR3_HDMI_OUT_top.fdc"]:
                raise ValueError("Reference pin table hash mismatch")
            reference_fdc = reference_path.read_text(encoding="utf-8")
        if args.target == 'video_mode_board':
            key = json.loads((work/'src'/manifest['pin_reference']).read_text(encoding='utf-8'))
            for field in ('manual', 'vendor_example_fdc'):
                if sha256(key[field]['path']) != key[field]['sha256']:
                    raise ValueError('MODE key official source hash mismatch: '+field)
            fdc = (work/'src/fpga/pg2l100h/constraints/video_mode_board.fdc').read_text(encoding='utf-8')
            reference_fdc += '\n'+verify_mode_key_reference(key, fdc)
            result['mode_key_official_sources_verified'] = True
        reviewed, rejected = review_messages(log, reference_fdc)
        write_json(work / "message_review.json", {"reviewed_reference_pin_notices": reviewed,
                                                  "rejected": rejected})
        if rejected:
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
        if args.stage in ("route", "bitstream"):
            timing = work / "report_timing" / (top + ".rtr")
            timing_text = timing.read_text(encoding="utf-8", errors="replace")
            if "All Constraints Met" not in timing_text:
                raise RuntimeError("Routed internal timing constraints not met; inspect timing report")
            result["internal_timing_met"] = True
            result["timing_report"] = str(timing.relative_to(ROOT))
        if args.stage == "bitstream":
            bitstream = work / "generate_bitstream" / (top + ".sbit")
            result["artifact"] = str(bitstream.relative_to(ROOT))
            result["artifact_sha256"] = sha256(bitstream)
            verify_mask = bitstream.with_suffix(".smsk")
            result["verify_mask"] = str(verify_mask.relative_to(ROOT))
            result["verify_mask_sha256"] = sha256(verify_mask)
        verify_build_inputs(work, result)
        if args.target in ('cpu_native_axil', 'video_raw_display') and sha256(executable) != result['pds_executable_sha256']:
            raise ValueError('PDS executable changed during build')
        result['input_snapshot_verified_before_and_after_build'] = True
    except Exception as error:
        result.update(status="fail", error=str(error))
        print(str(error), file=sys.stderr)
    write_json(work / "result.json", result)
    write_json(latest, result)
    write_json(target_latest, result)
    print(f"VIDEO_PDS_{result['status'].upper()}: {work}")
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

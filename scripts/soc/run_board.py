"""Native ModelSim board clocks and full CPU firmware checks; never programs hardware."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import shutil
import time
from datetime import datetime, timezone

from gen_board import ROOT, CONFIG, generate as check_config
from board_pll import PDS, generate as generate_pll
from run import SIM, sha, save, elf_sram, hex_image


def initialized_address(symbols):
    matches = re.findall(r"(?m)^([0-9a-f]+)\s+[0-9a-f]+\s+\w\s+initialized\r?$", symbols)
    if len(matches) != 1:
        raise ValueError("cannot uniquely locate initialized data for fault injection")
    return int(matches[0], 16)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test", choices=("clocks", "system", "coremark"), required=True)
    parser.add_argument("--fault", choices=("none", "memory", "crc"), default="none")
    parser.add_argument('--cpu-area-directory', type=Path,
                        help='Frozen native board map evidence supplying CPU-only LUT count')
    args = parser.parse_args()
    if args.fault == 'crc' and args.test != 'coremark' or args.fault == 'memory' and args.test != 'system':
        parser.error('memory fault belongs to system; crc fault belongs to coremark')
    work = ROOT / "build/soc" / ("board-" + args.test + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
    work.mkdir(parents=True)
    print("CPU_BOARD_RUN", work, flush=True)
    result = dict(status="RUNNING", test=args.test, fault=args.fault, directory=str(work),
                  input_hashes={}, external_hashes={}, output_hashes={}, commands=[],
                  source_unchanged=False, external_unchanged=False, programmed=False,
                  scope="RTL simulation; actual vendor PLL model for clocks, digital PLL substitute for system")
    start = time.monotonic()
    save(work / "result.json", result)

    def native(executable, arguments, label, timeout=120):
        executable = Path(executable)
        result["external_hashes"][str(executable)] = sha(executable)
        command = [str(executable), *[str(a) for a in arguments]]
        record = dict(command=command, return_code=None, timed_out=False)
        result["commands"].append(record)
        process = subprocess.Popen(command, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            record["timed_out"] = True
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
            output, _ = process.communicate()
        record["return_code"] = process.returncode
        (work / (label + ".log")).write_bytes(output)
        if process.returncode or record["timed_out"]:
            raise RuntimeError(f"{label} returned {process.returncode}; timeout={record['timed_out']}")
        return output.decode("utf-8", errors="replace")

    try:
        cpu_luts = 0
        if args.cpu_area_directory is not None:
            if args.test != 'coremark':
                raise ValueError('CPU area metadata belongs to CoreMark')
            from cpu_area import load
            area = load(args.cpu_area_directory)
            cpu_luts = area['cpu_core_luts']
            result['cpu_area'] = area
            result['external_hashes'].update(area['bound_hashes'])
            result['cpu_core_luts'] = cpu_luts
        config = json.loads(CONFIG.read_text(encoding="utf-8"))
        check_config(config, check=True)
        inputs = ["config/cpu_board.json", "scripts/soc/run_board.py", "scripts/soc/board_pll.py",
                  "scripts/soc/gen_board.py", "scripts/soc/run.py", "scripts/soc/gen_config.py",
                  "fpga/pg2l100h/constraints/cpu_board.fdc", "fpga/pg2l100h/ip/video_reference_manifest.json",
                  "fpga/pg2l100h/rtl/triha_cpu_clock_reset.v", "scripts/cpu/run_modelsim.do"]
        rtl = ["fpga/pg2l100h/rtl/triha_cpu_clock_reset.v"]
        tb = {"clocks": "tb/soc/tb_cpu_board_clock.v", "system": "tb/soc/tb_cpu_board.v",
              "coremark": "tb/soc/tb_cpu_coremark.v"}[args.test]
        inputs += [tb]
        if args.test != "clocks":
            core = json.loads((ROOT / "fpga/pg2l100h/project/cpu_core.json").read_text(encoding="utf-8"))
            soc = json.loads((ROOT / "fpga/pg2l100h/project/cpu_minimal_soc_compact.json").read_text(encoding="utf-8"))
            rtl += core["sources"] + soc["sources"] + ["fpga/pg2l100h/rtl/triha_cpu_board_top.v", "tb/soc/cpu_board_pll_model.v"]
            inputs += rtl + core["headers"] + soc["headers"] + ["fpga/pg2l100h/project/cpu_core.json",
                "fpga/pg2l100h/project/cpu_minimal_soc_compact.json", "config/cpu_primitives.json",
                "config/soc_map.json", "config/cpu_toolchain.json", "sw/runtime/crt0.S",
                "sw/runtime/triha_runtime.c", "sw/runtime/triha_runtime.h", "sw/runtime/soc_map.h",
                "sw/runtime/triha_sram.ld", "sw/tests/cpu_board.c", "rtl/cpu/vendor/UPSTREAM.json", "rtl/cpu/ADAPTATIONS.json"]
            for row in json.loads((ROOT / "rtl/cpu/ADAPTATIONS.json").read_text(encoding="utf-8"))["adaptations"]:
                for key in ("base", "derived"):
                    if sha(ROOT / row[key]) != row[key + "_sha256"]:
                        raise ValueError("CPU adaptation drift")
                    inputs.append(row[key])
            for name, digest in json.loads((ROOT / "rtl/cpu/vendor/UPSTREAM.json").read_text(encoding="utf-8"))["files"].items():
                if sha(ROOT / "rtl/cpu/vendor" / name) != digest:
                    raise ValueError("CPU vendor drift")
                inputs.append("rtl/cpu/vendor/" + name)
            if args.test == 'coremark':
                inputs += ['scripts/soc/coremark_board.py', 'scripts/soc/cpu_area.py', 'sw/benchmarks/coremark/port/core_portme.c',
                           'sw/benchmarks/coremark/port/core_portme.h', 'sw/benchmarks/coremark/UPSTREAM.json']
                for name, digest in json.loads((ROOT / 'sw/benchmarks/coremark/UPSTREAM.json').read_text(encoding='utf-8'))['files'].items():
                    source = 'sw/benchmarks/coremark/src/' + name
                    if sha(ROOT / source) != digest:
                        raise ValueError('CoreMark upstream drift')
                    inputs.append(source)
        for name in sorted(set(inputs)):
            path = ROOT / name
            result["input_hashes"][name] = sha(path)
            snapshot = work / "src" / name
            snapshot.parent.mkdir(parents=True, exist_ok=True)
            snapshot.write_bytes(path.read_bytes())
            if sha(snapshot) != result["input_hashes"][name]:
                raise ValueError("snapshot drift")
        primitives = [PDS / "arch/vendor/pango/verilog/simulation" / name for name in ("GTP_INBUFDS.v", "GTP_CLKBUFG.v")]
        extra = []
        if args.test == "clocks":
            extra = [generate_pll(work / "ip", native)]
            primitives += [PDS / "arch/vendor/pango/verilog/simulation/GTP_GPLL.v"]
        else:
            memory = json.loads((work / "src/config/soc_map.json").read_text(encoding="utf-8"))
            import struct
            rom = bytearray((b"\x73\x00\x10\x00") * (memory["rom_bytes"] // 4))
            rom[:8] = struct.pack("<II", 0x000102b7, 0x00028067)
            hex_image(work / "rom.hex", rom)
            gcc = Path(json.loads((ROOT / "config/cpu_toolchain.json").read_text(encoding="utf-8"))["compiler"])
            native(gcc, ["--version"], "gcc-version")
            flags = ["-march=rv32im_zicsr", "-mabi=ilp32", "-std=gnu99", "-O3", "-mcmodel=medany", "-mno-relax",
                     "-msmall-data-limit=0", "-ffreestanding", "-fno-builtin", "-ffunction-sections", "-fdata-sections",
                     "-Wall", "-Wextra", "-Werror", "-DTRIHA_SOC_MMIO=1", "-I", work / "src/sw/runtime",
                     "-nostdlib", "-T", work / "src/sw/runtime/triha_sram.ld", "-Wl,--gc-sections,--build-id=none",
                     "-Wl,-Map=" + str(work / "firmware.map"), "-o", work / "firmware.elf"]
            if args.test == 'coremark':
                from coremark_board import build
                build(work, work, native, 5, preflight=True, fault=args.fault, cpu_luts=cpu_luts)
                build(work, work / 'deployment', native, 5000, fault=args.fault, cpu_luts=cpu_luts)
                result.update(release_iterations=5000, preflight_iterations=5, full_run_simulated=False,
                              firmware_profile='coremark', board_score_validated=False,
                              scope='5-iteration board RTL preflight; 5000-iteration deployment built from same sources; full physical run pending')
            else:
                native(gcc, flags + [work / "src" / n for n in ("sw/runtime/crt0.S", "sw/runtime/triha_runtime.c", "sw/tests/cpu_board.c")] + ["-lgcc"], "firmware-build")
            libgcc = native(gcc, ["-march=rv32im_zicsr", "-mabi=ilp32", "-print-libgcc-file-name"], "libgcc").strip()
            result["external_hashes"][libgcc] = sha(libgcc)
            image = elf_sram((work / "firmware.elf").read_bytes(), memory)
            if args.fault == "memory":
                symbols = native(gcc.with_name("riscv-none-elf-nm.exe"), ["-S", work / "firmware.elf"], "firmware-symbols")
                address = initialized_address(symbols)
                offset = address - memory["sram_base"]
                if not 0 <= offset < len(image):
                    raise ValueError("initialized data outside SRAM")
                image[offset] ^= 1
                result["injected_fault"] = dict(sram_address=address, xor_byte=1)
            hex_image(work / "sram.hex", image)
            for row in json.loads((ROOT / "config/cpu_primitives.json").read_text(encoding="utf-8"))["simulation_models"]:
                if sha(row["path"]) != row["sha256"]:
                    raise ValueError("primitive drift")
                primitives.append(Path(row["path"]))
        for path in primitives:
            result["external_hashes"][str(path)] = sha(path)
        native(SIM / "vsim.exe", ["-version"], "modelsim-version")
        native(SIM / "vmap.exe", ["-c"], "vmap")
        native(SIM / "vlib.exe", ["work"], "vlib")
        native(SIM / "vlog.exe", ["+incdir+" + str(work / "src/rtl/cpu/vendor/src/core"),
                                  "+incdir+" + str(work / "src/rtl/soc/include")] +
               [work / "src" / name for name in rtl + [tb]] + extra + primitives, "rtl-build")
        top = {"clocks": "tb_cpu_board_clock", "system": "tb_cpu_board", "coremark": "tb_cpu_coremark"}[args.test]
        log = native(SIM / "vsim.exe", ["-c", "-onfinish", "exit", "-t", "1ps", "-voptargs=+acc", "work." + top,
                                      "-do", work / "src/scripts/cpu/run_modelsim.do"], "simulation", 1200 if args.test == 'coremark' else 420)
        marker = {"clocks": "CPU_BOARD_CLOCK_PASS", "system": "CPU_BOARD_SYSTEM_PASS boots=2",
                  "coremark": "CPU_COREMARK_SIM_PASS"}[args.test]
        if marker not in log or re.search(r"CPU_BOARD_\w*FAIL|CPU_TRAP|\*\* (Error|Fatal)", log):
            raise RuntimeError("board self-check failed; see simulation.log")
        if args.test == 'coremark':
            from coremark_board import review_output
            builds = 0
            for record in result['commands']:
                if not any(str(a).endswith('firmware.elf') for a in record['command']):
                    continue
                builds += 1
                if '-O2' not in record['command'] or any(a in record['command'] for a in ('-O3', '-Ofast', '-flto')):
                    raise RuntimeError('CoreMark must use O2 without LTO')
            if builds != 2:
                raise RuntimeError('need both actual CoreMark firmware builds')
            if 'CPU_COREMARK_CONFIG btb=512 bht=512 ras=4 gshare=0 single_issue=1 indexed_btb=1' not in log:
                raise RuntimeError('missing actual predictor profile check')
            result['predictor'] = dict(btb=512, bht=512, ras=4, gshare=False, algorithm='PC-indexed 2-bit BHT with direct-mapped native-RAM BTB')
            result['optimization'] = '-O2'
            result['preflight_measurement'] = review_output(log, allow_short=True, expected_luts=cpu_luts or None)
            if result['preflight_measurement']['iterations'] != 5:
                raise RuntimeError('unexpected preflight iteration count')
            measured = re.search(r'CPU_COREMARK_SIM_PASS cycles=(\d+) reads=2', log)
            if not measured or int(measured[1]) != result['preflight_measurement']['cycles']:
                raise RuntimeError('hardware observer and software timing differ')
            result['short_simulation_passed'] = True
            (work / 'preflight').mkdir()
            for name in ('firmware.elf', 'firmware.map', 'sram.hex'):
                shutil.copyfile(work / name, work / 'preflight' / name)
                shutil.copyfile(work / 'deployment' / name, work / name)
            result['deployment_firmware_sha256'] = sha(work / 'firmware.elf')
            result['deployment_sram_sha256'] = sha(work / 'sram.hex')
        result["status"] = "PASS"
    except Exception as error:
        result.update(status="FAIL", error=str(error))
    finally:
        result["source_unchanged"] = all(sha(ROOT / n) == h for n, h in result["input_hashes"].items())
        result["external_unchanged"] = all(sha(n) == h for n, h in result["external_hashes"].items())
        if not result["source_unchanged"] or not result["external_unchanged"]:
            result.update(status="FAIL", error="board inputs changed")
        result["output_hashes"] = {p.relative_to(work).as_posix(): sha(p) for p in work.rglob("*") if p.is_file() and p != work / "result.json"}
        result["elapsed_seconds"] = round(time.monotonic() - start, 3)
        result["runner_return_code"] = 0 if result["status"] == "PASS" else 1
        save(work / "result.json", result)
    print("CPU_BOARD", result["status"], "result=" + str(work / "result.json"))
    if "error" in result:
        print(result["error"])
    return result["runner_return_code"]


if __name__ == "__main__":
    raise SystemExit(main())

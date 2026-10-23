"""Windows-native minimal-system simulation and evidence capture."""
import argparse
import hashlib
import json
import re
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'soc'))
from gen_config import ROOT, generate
from prepare_dual_candidate import sha as candidate_sha
from run_cache import source_origin

SIM = Path("D:/modeltech64_2020.4/win64")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, obj):
    path.write_bytes((json.dumps(obj, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))


def hex_image(path, data):
    assert len(data) % 8 == 0
    path.write_bytes(("\n".join(f"{int.from_bytes(data[i:i+8], 'little'):016x}" for i in range(0, len(data), 8)) + "\n").encode("ascii"))


def elf_sram(elf, memory):
    assert elf[:7] == b"\x7fELF\x01\x01\x01" and struct.unpack_from("<H", elf, 18)[0] == 243
    assert struct.unpack_from("<I", elf, 24)[0] == memory["sram_base"]
    offset = struct.unpack_from("<I", elf, 28)[0]
    size, count = struct.unpack_from("<HH", elf, 42)
    assert size >= 32 and offset + size * count <= len(elf)
    image = bytearray([0xa5] * memory["sram_bytes"])
    loaded = 0
    for n in range(count):
        kind, start, vaddr, paddr, filesz, memsz = struct.unpack_from("<6I", elf, offset + n * size)
        if kind != 1:
            continue
        local = paddr - memory["sram_base"]
        assert vaddr == paddr and 0 <= local and filesz <= memsz and local + memsz <= len(image)
        assert start + filesz <= len(elf)
        image[local:local + filesz] = elf[start:start + filesz]
        loaded += 1
    assert loaded
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", choices=["memory", "runtime", "coremark"], required=True)
    parser.add_argument("--fault", choices=["none", "read", "crc", "timeout"], default="none")
    parser.add_argument('--cpu-snapshot',type=Path,required=True)
    parser.add_argument('--profile',action='store_true',help='Passive cycle partition and ordered trace observer')
    args = parser.parse_args()
    if args.test=='memory': parser.error('Use original runner for memory-only tests')
    if args.profile and (args.test!='coremark' or args.fault!='none'):
        parser.error('Passive profile supports only coremark with fault none')
    work = ROOT / "build/cpu/dual-sram" / (args.test + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
    work.mkdir(parents=True)
    print(f"SOC_RUN directory={work}", flush=True)
    result = dict(status="RUNNING", directory=str(work), test=args.test, fault=args.fault,
                  input_hashes={}, origin_hashes={}, input_origins={}, external_hashes={}, commands=[], output_hashes={}, source_unchanged=False,
                  scope="RTL simulation; no board execution or official CoreMark score")
    start_time = time.monotonic()
    save(work / "result.json", result)

    def native(executable, arguments, label, timeout=120):
        command = [str(executable), *[a.as_posix() if isinstance(a, Path) else str(a) for a in arguments]]
        result["external_hashes"][str(executable)] = sha(executable)
        record = dict(command=command, return_code=None)
        result["commands"].append(record)
        process = subprocess.Popen(command, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
            output, _ = process.communicate()
            (work / (label + ".log")).write_bytes(output)
            raise RuntimeError(f"{label} timeout")
        (work / (label + ".log")).write_bytes(output)
        record["return_code"] = process.returncode
        if process.returncode:
            raise RuntimeError(f"{label} returned {process.returncode}; see {work / (label + '.log')}")
        return output.decode("utf-8", errors="replace")

    try:
        generate(check=True)
        manifest=json.loads((ROOT/'docs/verification/cpu/dualissue_pairing_sources.json').read_text(encoding='utf-8'))
        for name,record in manifest['sources'].items():
            if candidate_sha(args.cpu_snapshot/Path(name).name)!=record['candidate_sha256']:
                raise ValueError('Candidate drift: '+name)
        core = json.loads((ROOT / "fpga/pg2l100h/project/cpu_core.json").read_text(encoding="utf-8"))
        rtl = ["rtl/soc/triha_sram.v", "rtl/soc/triha_boot_rom.v", "rtl/soc/triha_uart_tx.v", "rtl/soc/triha_soc_memory.v"]
        tb = "tb/soc/tb_soc_memory.v" if args.test == "memory" else "tb/cpu/tb_dual_sram.v"
        if args.test != "memory":
            rtl += core["sources"] + ["rtl/soc/triha_minimal_soc.v"]
        if args.profile:
            rtl += [tb]
            tb = 'tb/cpu/tb_dual_sram_profile.v'
        inputs = rtl + [tb, "config/soc_map.json", "rtl/soc/include/soc_map.vh", "scripts/cpu/run_dual_sram.py", "scripts/soc/gen_config.py",
                        "scripts/cpu/run_modelsim.do", "rtl/cpu/ADAPTATIONS.json", "rtl/cpu/vendor/UPSTREAM.json",
                        "fpga/pg2l100h/project/cpu_core.json", "config/cpu_primitives.json"] + core["headers"]
        if args.test != "memory":
            inputs += ["sw/runtime/triha_runtime.c", "sw/runtime/triha_runtime.h", "sw/runtime/crt0.S", "sw/runtime/soc_map.h", "sw/runtime/triha_sram.ld", "sw/tests/soc_runtime.c", "config/cpu_toolchain.json"]
            if args.test == "coremark":
                inputs += ["sw/benchmarks/coremark/port/core_portme.c", "sw/benchmarks/coremark/port/core_portme.h", "sw/benchmarks/coremark/UPSTREAM.json"]
                manifest = json.loads((ROOT / "sw/benchmarks/coremark/UPSTREAM.json").read_text(encoding="utf-8"))
                for name, digest in manifest["files"].items():
                    path = "sw/benchmarks/coremark/src/" + name
                    assert sha(ROOT / path) == digest, path
                    inputs.append(path)
        upstream = json.loads((ROOT / "rtl/cpu/vendor/UPSTREAM.json").read_text(encoding="utf-8"))
        for name, digest in upstream["files"].items():
            path = "rtl/cpu/vendor/" + name
            assert sha(ROOT / path) == digest, path
            inputs.append(path)
        adaptations = json.loads((ROOT / "rtl/cpu/ADAPTATIONS.json").read_text(encoding="utf-8"))
        for row in adaptations["adaptations"]:
            for key in ("base", "derived"):
                assert sha(ROOT / row[key]) == row[key + "_sha256"]
                inputs.append(row[key])
        for name in sorted(set(inputs)):
            source = source_origin(ROOT,name,args.cpu_snapshot)
            result['input_origins'][name]=str(source)
            result['origin_hashes'][name]=sha(source)
            target = work / "src" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            data=source.read_bytes()
            if name=='rtl/soc/triha_minimal_soc.v':
                if data.count(b'.DUAL_ISSUE(0)')!=1:raise ValueError('SoC mode binding changed')
                data=data.replace(b'.DUAL_ISSUE(0)',b'.DUAL_ISSUE(1)')
            target.write_bytes(data)
            result['input_hashes'][name]=sha(target)
        mem = json.loads((ROOT / "config/soc_map.json").read_text(encoding="utf-8"))
        rom = bytearray((b"\x73\x00\x10\x00") * (mem["rom_bytes"] // 4))
        rom[:8] = struct.pack("<II", 0x000102b7, 0x00028067)  # lui t0,0x10; jalr zero,t0,0
        hex_image(work / "rom.hex", rom)
        image = bytearray([0xa5] * mem["sram_bytes"])
        if args.test != "memory":
            toolchain = json.loads((ROOT / "config/cpu_toolchain.json").read_text(encoding="utf-8"))
            gcc = Path(toolchain["compiler"])
            native(gcc, ["--version"], "gcc-version")
            flags = ["-march=rv32im_zicsr", "-mabi=ilp32", "-std=gnu99", "-O3", "-mcmodel=medany", "-mno-relax", "-msmall-data-limit=0", "-ffreestanding", "-fno-builtin", "-ffunction-sections", "-fdata-sections", "-Wall", "-Wextra", "-Werror=implicit-function-declaration", "-DTRIHA_SOC_MMIO=1"]
            if args.test == 'coremark':
                flags[flags.index('-O3')] = '-O2'
            sources = [work / "src/sw/runtime/crt0.S", work / "src/sw/runtime/triha_runtime.c"]
            if args.test == "runtime":
                sources += [work / "src/sw/tests/soc_runtime.c"]
            else:
                port = work / "src/sw/benchmarks/coremark/port"
                bench = work / "src/sw/benchmarks/coremark/src"
                (work / "core_build_config.h").write_text('#define TRIHA_COMPILER_FLAGS "' + " ".join(flags) + '"\n', encoding="utf-8")
                formatter = (bench / "barebones/ee_printf.c").read_text(encoding="utf-8")
                pattern = r"(?s)void uart_send_char\(char c\) \{.*?\n\}\s*(?=int ee_printf)"
                assert len(re.findall(pattern, formatter)) == 1
                formatter = re.sub(pattern, "void uart_send_char(char c);\n\n", formatter).replace("#ifdef HAS_FLOAT", "#if HAS_FLOAT").replace("va_start(args, fmt);", "triha_coremark_note(fmt);\n  va_start(args, fmt);")
                (work / "ee_printf.c").write_bytes(formatter.encode("utf-8"))
                main_text = (bench / "core_main.c").read_text(encoding="utf-8")
                if args.fault == "crc":
                    assert "(ee_u16)0xe714" in main_text
                    main_text = main_text.replace("(ee_u16)0xe714", "(ee_u16)0xe715")
                (work / "core_main.c").write_bytes(main_text.encode("utf-8"))
                flags += ["-DITERATIONS=5", "-DTOTAL_DATA_SIZE=2000", "-DCORE_DEBUG=0", "-DPERFORMANCE_RUN=1", "-DVALIDATION_RUN=0", "-I", port, "-I", bench, "-I", work]
                sources += [work / "core_main.c", work / "ee_printf.c", port / "core_portme.c"]
                sources += [bench / n for n in ("core_list_join.c", "core_matrix.c", "core_state.c", "core_util.c")]
            elf = work / "firmware.elf"
            native(gcc, flags + ["-I", work / "src/sw/runtime", "-nostdlib", "-T", work / "src/sw/runtime/triha_sram.ld", "-Wl,--gc-sections,--build-id=none", "-Wl,-Map=" + str(work / "firmware.map"), "-o", elf] + sources + ["-lgcc"], "firmware-build")
            library = native(gcc, ["-march=rv32im_zicsr", "-mabi=ilp32", "-print-libgcc-file-name"], "libgcc").strip()
            result["external_hashes"][library] = sha(library)
            image = elf_sram(elf.read_bytes(), mem)
        hex_image(work / "sram.hex", image)
        (work / "sram.bin").write_bytes(image)
        native(SIM / "vsim.exe", ["-version"], "modelsim-version")
        native(SIM / "vmap.exe", ["-c"], "vmap")
        native(SIM / "vlib.exe", ["work"], "vlib")
        primitive_sources = []
        if args.test != "memory":
            primitives = json.loads((ROOT / "config/cpu_primitives.json").read_text(encoding="utf-8"))
            for row in primitives["simulation_models"]:
                assert sha(row["path"]) == row["sha256"]
                result["external_hashes"][row["path"]] = row["sha256"]
                primitive_sources.append(row["path"])
        native(SIM / "vlog.exe", ["+incdir+" + str(work / "src/rtl/soc/include"), "+incdir+" + str(work / "src/rtl/cpu/vendor/src/core")] + [work / "src" / n for n in rtl + [tb]] + primitive_sources, "rtl-build")
        top = "tb_dual_sram_profile" if args.profile else "tb_dual_sram"
        arguments = ["-c", "-onfinish", "exit", "-t", "1ps", "-voptargs=+acc", "work." + top]
        if args.fault == "read":
            arguments += ["+FAULT_READ=1"]
        if args.fault == "timeout":
            arguments += ["-gMAX_CYCLES=8"]
        output = native(SIM / "vsim.exe", arguments + ["-do", work / "src/scripts/cpu/run_modelsim.do"], "simulation", 300)
        if re.search(r"SOC_\w*FAIL|CPU_TRAP|\*\* (Error|Fatal)", output):
            raise RuntimeError("Self-check reported failure")
        if args.test == "memory":
            assert re.search(r"SOC_MEMORY_PASS checks=\d+", output)
        else:
            assert re.search(r'SOC_DUAL_CONFIG actual=1 pairs=[1-9][0-9]*',output)
            assert "SOC_PROGRAM_EXIT code=0" in output and "SOC_FIRMWARE_PASS" in output
            if args.test == "runtime":
                assert "SOC_RUNTIME_PASS" in output
            else:
                expected = ["e9f5", "e714", "1fd7", "8e3a"]
                patterns = [r"seedcrc\s*:\s*0x([0-9a-f]+)", r"\[0\]crclist\s*:\s*0x([0-9a-f]+)", r"\[0\]crcmatrix\s*:\s*0x([0-9a-f]+)", r"\[0\]crcstate\s*:\s*0x([0-9a-f]+)"]
                assert [re.search(p, output).group(1).zfill(4) for p in patterns] == expected
                ticks = int(re.search(r"Total ticks\s*:\s*(\d+)", output).group(1))
                measure = re.search(r"SOC_MEASURE cycles=(\d+) wb_completed=(\d+) reads=2", output)
                assert measure and ticks == int(measure[1]) and ticks > 0
                assert "CPU_COREMARK_STATUS errors=0 short=1" in output
                result["measurement"] = dict(cycles=ticks, wb_completed=int(measure[2]), observed_ipc=int(measure[2]) / ticks,
                    coremark_per_mhz_short_estimate=5000000 / ticks, crc=expected, official_score=False)
        if args.profile:
            matches=re.findall(r'SRAM_PROFILE_PASS (.*)',output)
            if len(matches)!=1 or 'SRAM_PROFILE_FAIL' in output:
                raise ValueError('Missing or failed SRAM profile')
            result['profile']={k:int(v) for k,v in (field.split('=') for field in matches[0].strip().split())}
            if result['profile']['cycles']!=result['measurement']['cycles'] or result['profile']['wb']!=result['measurement']['wb_completed']:
                raise ValueError('Profile window differs from software/WB')
        result['profile_enabled']=args.profile
        result["status"] = "PASS"
    except Exception as error:
        result["status"] = "FAIL"
        result["error"] = str(error)
    finally:
        result["source_unchanged"] = all(sha(result["input_origins"][n]) == d for n, d in result["origin_hashes"].items())
        result["external_unchanged"] = all(sha(n) == d for n, d in result["external_hashes"].items())
        if not result["source_unchanged"] or not result["external_unchanged"]:
            result["status"] = "FAIL"
            result["error"] = "Inputs changed"
        for path in work.rglob("*"):
            if path.is_file() and path != work / "result.json":
                result["output_hashes"][path.relative_to(work).as_posix()] = sha(path)
        result["elapsed_seconds"] = round(time.monotonic() - start_time, 3)
        result["runner_return_code"] = 0 if result["status"] == "PASS" else 1
        save(work / "result.json", result)
    print(f"SOC_{args.test.upper()} {result['status']} result={work / 'result.json'}")
    if "error" in result:
        print(result["error"])
    return result["runner_return_code"]


if __name__ == "__main__":
    sys.exit(main())

"""Package an independently verified CPU board image; never programs the board."""
import argparse
import json
from pathlib import Path
import shutil

from review_board import review
from gen_board import ROOT
from run import sha, save


def package(work):
    checked = review(work)
    if not checked["timing_closed"]:
        raise ValueError("100MHz board timing has not passed")
    bit = work / "generate_bitstream/triha_cpu_board_top.sbit"
    output = ROOT / "build/soc/releases" / ("cpu_board_" + sha(bit)[:12])
    output.mkdir(parents=True, exist_ok=False)
    sources = [bit, bit.with_suffix(".smsk"), work / "rom.hex", work / "sram.hex", work / "firmware.elf",
               work / "result.json", work / "report_timing/triha_cpu_board_top.rtr"]
    for source in sources:
        shutil.copyfile(source, output / source.name)
    terminal = json.loads((work / "result.json").read_text(encoding="utf-8"))
    shutil.copyfile(Path(terminal["system_directory"]) / "firmware.map", output / "firmware.map")
    save(output / "review.json", checked)
    readme = """# TriHa CPU board image

Target PG2L100H/FBG676/-6. CPU six-stage single-issue, local ROM/SRAM, no DDR or Video.
N3/N2 = 125MHz differential reference; PLL = exact 100MHz. KEY0 C22 active low.
UART C24 = 115200/8N1. LED signals 0 heartbeat, 1 reset released, 2 software PASS, 3 software FAIL.
The 8KiB scratch self-test reports CPU_BOARD_PASS checked_bytes=8192, then CPU_ALIVE every ~1s.
KEY0 reboots and reruns the self-test. These are expected observations, not board results.

Internal post-route timing passed both corners. This package has NOT been programmed or board-tested.
Only after user authorization, scan ID 00602899, program volatile configuration and verify the matching smsk.
Do not write Flash. Programming replaces the currently configured Video image until restored or power-cycled.
Keep the existing Video release and its matching smsk as the recovery image; no new Video image is included here.
Physical PLL frequency, UART reception, sustained execution and physical KEY0 are separate acceptance steps.
The ELF/map and initial images use the same firmware validated in ModelSim; no simulator-only loading path.
"""
    (output / "README.md").write_text(readme, encoding="utf-8", newline="\n")
    manifest = dict(status="PASS", target="cpu_board", route_directory=str(work),
                    timing_closed=True, programmed=False, board_validated=False,
                    bitstream_sha256=sha(bit), verify_mask_sha256=sha(bit.with_suffix(".smsk")),
                    files={path.name: sha(path) for path in output.iterdir() if path.is_file()})
    save(output / "manifest.json", manifest)
    for name, digest in manifest["files"].items():
        if sha(output / name) != digest:
            raise ValueError("package copy hash mismatch")
    save(ROOT / "build/soc/latest_board_package.json", dict(directory=str(output), manifest_sha256=sha(output / "manifest.json"), **manifest))
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    print("CPU_BOARD_PACKAGE", package(args.directory.resolve()))

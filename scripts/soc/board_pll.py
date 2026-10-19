"""Build a 125->100MHz PLL using the pinned IDF and installed PDS generator."""
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

from gen_board import ROOT, CONFIG, validate
from run import sha, save

PDS = Path("D:/pango/PDS_2022.2-SP6.4")


def review_wrapper(config, text):
    pfd, vco, cpu = validate(config)
    pll = config["pll"]
    expected = {"CLKIN_FREQ": config["reference_hz"] / 1_000_000,
                "STATIC_RATIOI": pll["input_divider"], "STATIC_RATIOM": pll["multiplier"],
                "STATIC_RATIOF": pll["feedback_divider"], "STATIC_RATIO0": pll["output_divider"]}
    for key, value in expected.items():
        match = re.search(r"\b" + key + r"\s*=\s*([\d.]+)", text)
        if not match or float(match[1]) != value:
            raise ValueError("actual generated PLL mismatch: " + key)
    def number(value):
        return int(value) if value.denominator == 1 else float(value)
    return dict(actual_parameters=expected, pfd_hz=number(pfd), vco_hz=number(vco), cpu_hz=number(cpu))


def create_idf(config, source, output):
    validate(config)
    tree = ET.parse(source)
    name = config["pll"]["instance"]
    tree.find("header/instance").text = name
    pll = config["pll"]
    values = {"CLKIN_FREQ": "125.00000000", "CLKIN_FREQ_basicPage": "125.00000000",
              "CLKIN_FREQ_advancedPage": "125.00000000",
              "CLKOUT0_REQ_FREQ_basicPage": "100.00000000",
              "STATIC_RATIOI": pll["input_divider"], "STATIC_RATIOM": pll["multiplier"],
              "STATIC_RATIO7": pll["feedback_divider"], "STATIC_RATIO0": pll["output_divider"],
              "STATIC_DUTY7": pll["feedback_divider"], "STATIC_DUTY0": pll["output_divider"],
              "CLKOUT0_BUFG_EN": "true", "CLKOUT0_NOBUF_EN": "false"}
    for index in range(8):
        for suffix in ("", "_basicPage", "_advancedPage"):
            values[f"CLKOUT{index}_EN{suffix}"] = "true" if index == 0 else "false"
    seen = set()
    for item in tree.findall("param_list/param"):
        key = item.findtext("name")
        if key in values:
            item.find("value").text = str(values[key])
            seen.add(key)
    if seen != set(values):
        raise ValueError("source IDF missing required PLL fields")
    for item in tree.findall("file_list/*/file"):
        item.set("pathname", item.get("pathname").replace("pll", name))
    output.parent.mkdir(parents=True, exist_ok=True)
    tree.write(output, encoding="utf-8", xml_declaration=True)


def generate(work, native):
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    manifest_path = ROOT / "fpga/pg2l100h/ip/video_reference_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    entry = manifest["references"]["hdmi"]
    selected = next(row for row in entry["files"] if row["path"] == "ipcore/pll/pll.idf")
    archive = Path("D:/FPGA/盘古100Pro+开发板（MES2L676-100HP）配套资料") / entry["archive"]
    if sha(archive) != entry["sha256"]:
        raise ValueError("board reference archive hash mismatch")
    extraction = subprocess.run(["tar.exe", "-xOf", str(archive), selected["member"]],
                                capture_output=True, timeout=60)
    if extraction.returncode:
        raise RuntimeError("cannot extract pinned PLL reference")
    work.mkdir(parents=True, exist_ok=True)
    source = work / "source.idf"
    source.write_bytes(extraction.stdout)
    if sha(source) != selected["sha256"]:
        raise ValueError("pinned PLL source hash mismatch")
    idf = work / "cpu_board_pll.idf"
    create_idf(config, source, idf)
    log = native(PDS / "bin/ip_generate.exe", ["-i", idf, "-disable-syn"], "pll-generate", 120)
    errors = re.findall(r"Done:\s*(\d+) error\(s\)", log)
    if errors != ["0"]:
        raise RuntimeError("PLL generator did not report exact zero errors")
    wrapper = work / "cpu_board_pll.v"
    text = wrapper.read_text(encoding="utf-8")
    actual = review_wrapper(config, text)
    evidence = dict(status="PASS", configuration_sha256=sha(CONFIG),
                    reference_manifest_sha256=sha(manifest_path), source_idf_sha256=sha(source),
                    archive_sha256=entry["sha256"],
                    generated_idf_sha256=sha(idf), wrapper_sha256=sha(wrapper),
                    **actual,
                    scope="Generated IP, not physical clock or board validation")
    save(work / "provenance.json", evidence)
    return wrapper

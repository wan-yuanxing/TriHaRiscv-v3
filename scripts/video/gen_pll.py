"""Generate the dual-output 40/10 MHz PLL from a verified vendor IDF."""
import argparse
from fractions import Fraction
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

from common import BUILD, ROOT, run_logged, sha256, tool, write_json


def create_idf(config, output):
    if (config["schema_version"] != 1 or config["instance"] != "video_pll"
            or config["reference_hz"] != 27_000_000 or config["pixel_hz"] != 40_000_000
            or config["config_hz"] != 10_000_000):
        raise ValueError("unsupported fixed board PLL recipe")
    fin = Fraction(config["reference_hz"], config["input_divider"])
    vco = fin * config["feedback_multiplier"] * config["feedback_divider"]
    if (vco != config["vco_hz"] or vco / config["pixel_divider"] != config["pixel_hz"]
            or vco / config["config_divider"] != config["config_hz"]):
        raise ValueError("actual PLL frequencies do not match requested clocks")
    if not (10_000_000 <= fin <= 450_000_000 and 600_000_000 <= vco <= 1_200_000_000):
        raise ValueError("PLL PFD/VCO outside the Logos2 GPLL documented range")
    for key in ("input_divider", "feedback_multiplier", "feedback_divider",
                "pixel_divider", "config_divider"):
        if type(config[key]) is not int or not 1 <= config[key] <= 128:
            raise ValueError("invalid integer PLL divider: " + key)
    source = ROOT / config["source"]
    manifest = json.loads((ROOT / "fpga/pg2l100h/ip/video_reference_manifest.json").read_text(encoding="utf-8"))
    expected = next(item["sha256"] for item in manifest["references"]["hdmi"]["files"]
                    if item["path"] == "ipcore/pll/pll.idf")
    if sha256(source) != expected:
        raise ValueError("source PLL IDF hash mismatch; restage verified reference")
    tree = ET.parse(source)
    tree.find("header/instance").text = config["instance"]
    updates = {"STATIC_RATIOI": config["input_divider"],
               "STATIC_RATIOM": config["feedback_multiplier"],
               "STATIC_RATIO7": config["feedback_divider"],
               "STATIC_RATIO0": config["pixel_divider"],
               "STATIC_RATIO1": config["config_divider"],
               "STATIC_DUTY7": config["feedback_divider"],
               "STATIC_DUTY0": config["pixel_divider"],
               "STATIC_DUTY1": config["config_divider"],
               "CLKOUT0_REQ_FREQ_basicPage": "40.00000000",
               "CLKOUT1_REQ_FREQ_basicPage": "10.00000000"}
    for index in (0, 1):
        for suffix in ("", "_basicPage", "_advancedPage"):
            updates[f"CLKOUT{index}_EN{suffix}"] = "true"
        updates[f"CLKOUT{index}_BUFG_EN"] = "true"
        updates[f"CLKOUT{index}_NOBUF_EN"] = "false"
    seen = set()
    for param in tree.findall("./param_list/param"):
        name = param.findtext("name")
        if name in updates:
            param.find("value").text = str(updates[name])
            seen.add(name)
    if seen != set(updates):
        raise ValueError("PLL reference is missing expected fields: " + str(set(updates) - seen))
    for file in tree.findall("./file_list/*/file"):
        file.set("pathname", file.get("pathname").replace("pll", config["instance"]))
    pins=tree.find("pin_list")
    if not any(pin.findtext("name")=="clkout1" for pin in pins.findall("pin")):
        pin=ET.SubElement(pins,"pin")
        for tag,value in (("name","clkout1"),("text","clkout1"),("dir","output"),("pos","right")):
            ET.SubElement(pin,tag).text=value
    output.parent.mkdir(parents=True, exist_ok=True)
    tree.write(output, encoding="utf-8", xml_declaration=True)


def generate(output):
    output.mkdir(parents=True, exist_ok=True)
    write_json(output / "provenance.json", {"status": "running", "physical_board": False})
    try:
        return _generate(output)
    except Exception as error:
        write_json(output / "provenance.json", {"status": "fail", "error": str(error),
                                                "physical_board": False})
        raise


def _generate(output):
    config_path = ROOT / "fpga/pg2l100h/ip/video_pll.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    idf = output / "video_pll.idf"
    create_idf(config, idf)
    wrapper = output / "video_pll.v"
    if wrapper.exists():
        wrapper.unlink()
    executable = tool("pds_shell").with_name("ip_generate.exe")
    log = run_logged([executable, "-i", idf, "-disable-syn"],
                     output / "generate.log", cwd=output)
    summaries = re.findall(r"\bDone:\s*(\d+) error\(s\),\s*\d+ warning\(s\)", log)
    if not summaries or any(int(count) != 0 for count in summaries):
        raise RuntimeError("PLL generator did not report zero errors")
    text = wrapper.read_text(encoding="utf-8")
    # UI frequencies alone do not alter the generator's actual primitive params.
    for name, value in {"STATIC_RATIOI": 1, "STATIC_RATIOM": 5,
                        "STATIC_RATIOF": 8, "STATIC_RATIO0": 27, "STATIC_RATIO1": 108}.items():
        match = re.search(r"\b" + name + r"\s*=\s*([0-9.]+)", text)
        if not match or float(match.group(1)) != value:
            raise RuntimeError("Generated PLL divider mismatch: " + name)
    write_json(output / "provenance.json", {
        "status": "pass",
        "recipe_sha256": sha256(config_path), "source_sha256": sha256(ROOT / config["source"]),
        "generated_wrapper_sha256": sha256(wrapper), "pixel_hz": config["pixel_hz"],
        "config_hz": config["config_hz"], "vco_hz": config["vco_hz"],
        "physical_board": False})
    return idf, wrapper


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=BUILD / "ip/video_pll")
    args = parser.parse_args()
    try:
        _, wrapper = generate(args.output.resolve())
        print("VIDEO_PLL_GENERATE_PASS:", wrapper)
        return 0
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print("VIDEO_PLL_GENERATE_FAIL:", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

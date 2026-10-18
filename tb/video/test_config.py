"""Contract tests for the fixed v0.6 video configuration generator."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "scripts/video/gen_config.py"
CONFIG = ROOT / "config/video_cfg.json"


class VideoConfigTests(unittest.TestCase):
    def invoke(self, root, config=CONFIG, check=False):
        command = [sys.executable, str(GENERATOR), "--root", str(root),
                   "--config", str(config)]
        if check:
            command.append("--check")
        return subprocess.run(command, capture_output=True, text=True, timeout=20)

    def test_generates_matching_hardware_and_software_constants_in_space_path(self):
        with tempfile.TemporaryDirectory(prefix="video config test ") as directory:
            root = Path(directory)
            result = self.invoke(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            rtl = (root / "rtl/video/include/video_cfg.vh").read_text()
            c = (root / "sw/include/video_cfg.h").read_text()
            for key, value in {"H_TOTAL": 1056, "V_TOTAL": 628,
                               "PIXEL_HZ": 40000000,
                               "PREVIEW_BYTES": 360000,
                               "INPUT_BYTES": 307200, "INPUT_PLANE_BYTES": 102400,
                               "INPUT_PAD_TOP": 40, "INPUT_PAD_BOTTOM": 40,
                               "INPUT_WIDTH": 320, "INPUT_ACTIVE_HEIGHT": 240,
                               "INPUT_HEIGHT": 320, "INPUT_ROW_STRIDE": 320,
                               "INPUT_SLOT_BYTES": 327680,
                               "INPUT_SLOT_A": 0x82800000,
                               "INPUT_SLOT_B": 0x82850000,
                               "INPUT_SLOT_C": 0x828A0000,
                               "FRAME_SLOT_A": 0x82000000,
                               "FRAME_SLOT_B": 0x82200000,
                               "FRAME_SLOT_C": 0x82400000,
                               "FRAME_SLOT_BYTES": 0x200000,
                               "FRAME_PREVIEW_OFFSET": 0x160000,
                               "FRAME_RAW_STRIDE": 2400,
                               "FRAME_PREVIEW_STRIDE": 1200}.items():
                self.assertIn(f"`define VIDEO_{key} {value}\n", rtl)
                self.assertIn(f"#define VIDEO_{key} {value}u\n", c)
            self.assertEqual(self.invoke(root, check=True).returncode, 0)

    def test_check_rejects_drift_without_rewriting_generated_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.invoke(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            header = root / "sw/include/video_cfg.h"
            header.write_text("stale content\n")
            result = self.invoke(root, check=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stale", result.stderr.lower())
            self.assertEqual(header.read_text(), "stale content\n")

    def test_rejects_unsupported_mode_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = json.loads(CONFIG.read_text())
            config["mode"]["pixel_hz"] = 148500000
            source = root / "bad.json"
            source.write_text(json.dumps(config))
            result = self.invoke(root, source)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("fixed v0.6", result.stderr)
            self.assertFalse((root / "rtl").exists())

    def test_rejects_changed_layout_or_boolean_integer(self):
        for section, key, value in [("preview", "right_x", 401),
                                    ("detector", "storage_channels", 8),
                                    ("detector", "pad_top", 0),
                                    ("detector", "layout", "NHWC"),
                                    ("input_slots", "slot_bytes", 262144),
                                    ("frame_slots", "slot_bytes", 0x100000),
                                    ("frame_slots", "preview_offset", 0),
                                    ("mode", "v_front", True)]:
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                config = json.loads(CONFIG.read_text())
                config[section][key] = value
                source = root / "bad.json"
                source.write_text(json.dumps(config))
                result = self.invoke(root, source)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("fixed v0.6", result.stderr)
                self.assertFalse((root / "rtl").exists())


if __name__ == "__main__":
    unittest.main()

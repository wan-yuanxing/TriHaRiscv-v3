"""Independent EDID decoding checks for the fixed DMT 09h receive profile."""
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
HEX = ROOT / "config/video_edid.hex"
GENERATOR = ROOT / "scripts/video/gen_edid.py"
INCLUDE = ROOT / "rtl/video/include/video_edid.vh"


class FixedEdidTests(unittest.TestCase):
    def read_edid(self):
        self.assertTrue(HEX.is_file(), "fixed EDID image has not been generated")
        return bytes(int(token, 16) for token in HEX.read_text(encoding="utf-8").split())

    def test_checksum_header_and_unused_extension(self):
        image = self.read_edid()
        self.assertEqual(len(image), 256)
        self.assertEqual(image[:8], bytes.fromhex("00 ff ff ff ff ff ff 00"))
        self.assertEqual(image[18:20], bytes((1, 3)))
        self.assertEqual(image[126], 0, "no extension is advertised")
        self.assertEqual(sum(image[:128]) % 256, 0)
        self.assertEqual(image[128:], bytes(128), "clear stale vendor extension RAM")

    def test_only_800_by_600_is_advertised(self):
        image = self.read_edid()
        # EDID established timing byte 35 bit 0 is 800x600 @60 Hz.
        self.assertEqual(image[35:38], bytes((1, 0, 0)))
        self.assertEqual(image[38:54], bytes((1, 1)) * 8)
        for offset in (72, 90, 108):
            self.assertEqual(image[offset:offset+2], bytes(2), "only one detailed timing")
            self.assertIn(image[offset+3], (0xfc, 0xfe, 0xff, 0x10))
        self.assertTrue(image[24] & 2, "first detailed timing must be preferred")

    def test_detailed_timing_decodes_as_vesa_dmt_09h(self):
        dtd = self.read_edid()[54:72]
        clock_hz = int.from_bytes(dtd[:2], "little") * 10_000
        hactive = dtd[2] | ((dtd[4] & 0xf0) << 4)
        hblank = dtd[3] | ((dtd[4] & 0x0f) << 8)
        vactive = dtd[5] | ((dtd[7] & 0xf0) << 4)
        vblank = dtd[6] | ((dtd[7] & 0x0f) << 8)
        hfront = dtd[8] | ((dtd[11] & 0xc0) << 2)
        hsync = dtd[9] | ((dtd[11] & 0x30) << 4)
        vfront = (dtd[10] >> 4) | ((dtd[11] & 0x0c) << 2)
        vsync = (dtd[10] & 0xf) | ((dtd[11] & 3) << 4)
        self.assertLessEqual(abs(clock_hz / 40_000_000 - 1), 0.005)
        self.assertEqual((hactive, hfront, hsync, hblank-hfront-hsync), (800, 40, 128, 88))
        self.assertEqual((vactive, vfront, vsync, vblank-vfront-vsync), (600, 1, 4, 23))
        self.assertEqual(dtd[17], 0x1e, "progressive digital separate sync, positive H/V")
        self.assertAlmostEqual(clock_hz / ((hactive+hblank)*(vactive+vblank)), 60.3165412, places=5)

    def test_generated_files_are_current_and_do_not_depend_on_cwd(self):
        self.assertTrue(GENERATOR.is_file(), "EDID generator is missing")
        self.assertTrue(INCLUDE.is_file(), "synthesis-safe EDID function is missing")
        result = subprocess.run([sys.executable, str(GENERATOR), "--check"], cwd=ROOT.parent,
                                capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

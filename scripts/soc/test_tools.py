"""Reject invalid images and address-definition drift before HDL execution."""
import json
import struct
import tempfile
import unittest
from pathlib import Path

import gen_config
from run import elf_sram


class ImageTests(unittest.TestCase):
    def setUp(self):
        self.memory = {"sram_base": 0x10000, "sram_bytes": 32768}
        self.elf = bytearray(88)
        self.elf[:7] = b"\x7fELF\x01\x01\x01"
        struct.pack_into("<H", self.elf, 18, 243)
        struct.pack_into("<II", self.elf, 24, 0x10000, 52)
        struct.pack_into("<HH", self.elf, 42, 32, 1)
        struct.pack_into("<6I", self.elf, 52, 1, 84, 0x10000, 0x10000, 4, 8)
        self.elf[84:] = b"\x12\x34\x56\x78"

    def test_load_file_bytes_but_leave_bss_poisoned(self):
        image = elf_sram(self.elf, self.memory)
        self.assertEqual(image[:8], b"\x12\x34\x56\x78\xa5\xa5\xa5\xa5")
        self.assertEqual(len(image), 32768)

    def test_old_tcm_entry_rejected(self):
        struct.pack_into("<I", self.elf, 24, 0x80000000)
        with self.assertRaises(AssertionError):
            elf_sram(self.elf, self.memory)

    def test_out_of_range_segment_rejected(self):
        struct.pack_into("<II", self.elf, 60, 0x17ffc, 0x17ffc)
        with self.assertRaises(AssertionError):
            elf_sram(self.elf, self.memory)

    def test_missing_file_bytes_rejected(self):
        with self.assertRaises(AssertionError):
            elf_sram(self.elf[:-1], self.memory)

    def test_configuration_drift_rejected(self):
        original = gen_config.ROOT
        with tempfile.TemporaryDirectory() as directory:
            try:
                gen_config.ROOT = Path(directory)
                (gen_config.ROOT / "config").mkdir()
                content = json.loads((original / "config/soc_map.json").read_text(encoding="utf-8"))
                (gen_config.ROOT / "config/soc_map.json").write_text(json.dumps(content), encoding="utf-8")
                gen_config.generate()
                gen_config.generate(check=True)
                (gen_config.ROOT / "rtl/soc/include/soc_map.vh").write_text("bad", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "drift"):
                    gen_config.generate(check=True)
            finally:
                gen_config.ROOT = original

    def test_overlapping_mmio_and_sram_rejected(self):
        original = gen_config.ROOT
        with tempfile.TemporaryDirectory() as directory:
            try:
                gen_config.ROOT = Path(directory)
                (gen_config.ROOT / "config").mkdir()
                content = json.loads((original / "config/soc_map.json").read_text(encoding="utf-8"))
                content["uart_base"] = content["sram_base"]
                (gen_config.ROOT / "config/soc_map.json").write_text(json.dumps(content), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "overlap"):
                    gen_config.generate()
            finally:
                gen_config.ROOT = original


if __name__ == "__main__":
    unittest.main()

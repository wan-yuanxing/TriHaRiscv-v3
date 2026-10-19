"""Read-only physical UART acceptance must reject missing/error/stalled evidence."""
import importlib.util
from pathlib import Path
import unittest


class SerialContracts(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).with_name("board_serial.py")
        self.assertTrue(path.is_file(), "CPU board serial reader is missing")
        spec = importlib.util.spec_from_file_location("cpu_board_serial", path)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.valid = (b"CPU_BOARD_PASS checked_bytes=8192\n"
                      b"CPU_ALIVE seq=00000000 cycle=000c6f53\n"
                      b"CPU_ALIVE seq=00000001 cycle=06090153\n")

    def test_complete_pass_and_progress(self):
        self.assertEqual(self.module.review_uart(self.valid)["alive_records"], 2)

    def test_boot_banner_required(self):
        with self.assertRaisesRegex(ValueError, "banner"):
            self.module.review_uart(self.valid.split(b"\n", 1)[1])

    def test_real_software_error_rejected(self):
        with self.assertRaisesRegex(ValueError, "CPU_BOARD_FAIL"):
            self.module.review_uart(self.valid + b"CPU_BOARD_FAIL code=00000001\n")

    def test_stalled_cycle_rejected(self):
        with self.assertRaisesRegex(ValueError, "cycle"):
            self.module.review_uart(self.valid.replace(b"06090153", b"000c6f53"))

    def test_missing_sequence_rejected(self):
        with self.assertRaisesRegex(ValueError, "sequence"):
            self.module.review_uart(self.valid.replace(b"seq=00000001", b"seq=00000003"))

    def test_restart_requires_explicit_reboot_mode(self):
        with self.assertRaisesRegex(ValueError, "restart"):
            self.module.review_uart(self.valid + self.valid)
        self.assertEqual(self.module.review_uart(self.valid + self.valid, expect_reboot=True)["boots"], 2)


if __name__ == "__main__":
    unittest.main()

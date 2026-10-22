"""Only a complete post-loader epoch can supply a physical CoreMark score."""
import unittest
import capture_ddr_coremark


class EpochTests(unittest.TestCase):
    def test_programming_can_supersede_an_incomplete_initial_boot(self):
        data = b'CPU_DDR_COREMARK_BOOT\npartial\nCPU_DDR_COREMARK_BOOT\nCPU_DDR_COREMARK_PAYLOAD_PASS\nscore\n'
        text, count = capture_ddr_coremark.last_epoch(data)
        self.assertEqual(count, 2)
        self.assertNotIn('partial', text)

    def test_actual_error_is_not_hidden_by_a_later_epoch(self):
        for prefix in (b'CPU_TRAP cause=7\n', b'CPU_COREMARK_STATUS errors=1 short=0\n'):
            with self.subTest(prefix=prefix), self.assertRaises(ValueError):
                capture_ddr_coremark.last_epoch(prefix + b'CPU_DDR_COREMARK_BOOT\n')

    def test_missing_loader_is_rejected(self):
        with self.assertRaises(ValueError):
            capture_ddr_coremark.last_epoch(b'CPU_COREMARK_BOARD_PASS iterations=5000\n')


if __name__ == '__main__':
    unittest.main()

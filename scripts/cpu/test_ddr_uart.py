"""Physical DDR acceptance needs complete software boots, not programming alone."""
import unittest
import review_ddr_uart


BOOT = b'CPU_DDR_BOOT\nCPU_DDR_PASS private=8192 shared=8192 fence_i=1\n'


class DdrUartTests(unittest.TestCase):
    def test_two_complete_boots(self):
        result = review_ddr_uart.review_uart(BOOT * 2, expect_reboot=True)
        self.assertEqual(result['complete_boots'], 2)

    def test_missing_pass_or_reboot_cannot_be_admitted(self):
        for text in (BOOT, BOOT + b'CPU_DDR_BOOT\n', BOOT.splitlines()[1] + b'\n'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                review_ddr_uart.review_uart(text, expect_reboot=True)

    def test_actual_trap_or_error_is_not_hidden_by_pass(self):
        for line in (b'CPU_TRAP cause=00000007 value=80010000\n', b'CPU_DDR_FAIL init\n'):
            with self.subTest(line=line), self.assertRaises(ValueError):
                review_ddr_uart.review_uart(BOOT * 2 + line, expect_reboot=True)

    def test_wrong_size_and_unexpected_text_fail(self):
        for text in (BOOT.replace(b'8192', b'4096'), BOOT + b'garbled\xff\n'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                review_ddr_uart.review_uart(text)


if __name__ == '__main__':
    unittest.main()

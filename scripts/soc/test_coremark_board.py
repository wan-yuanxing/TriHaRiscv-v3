"""Reject misleading board scores before accepting actual UART measurements."""
import unittest
from decimal import Decimal

import coremark_board


class BoardScore(unittest.TestCase):
    def test_compiler_report_fits_the_original_formatter(self):
        self.assertTrue(hasattr(coremark_board, 'compiler_description'), 'bounded compiler report is missing')
        flags = ['-march=rv32im_zicsr', '-mabi=ilp32', '-std=gnu99', '-O3', '-mcmodel=medany',
                 '-mno-relax', '-msmall-data-limit=0', '-ffreestanding', '-fno-builtin',
                 '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra', '-Werror=implicit-function-declaration',
                 '-DTRIHA_COREMARK_BOARD=1', '-DTRIHA_COREMARK_PREFLIGHT=0', '-DITERATIONS=5000',
                 '-DTOTAL_DATA_SIZE=2000', '-DCORE_DEBUG=0', '-DPERFORMANCE_RUN=1', '-DVALIDATION_RUN=0']
        report = coremark_board.compiler_description(flags)
        self.assertLess(len('Compiler flags   : ' + report + '\n') + 1, 256)
        self.assertIn('-march=rv32im_zicsr', report)
        self.assertIn('-O3', report)
        self.assertIn('-ffreestanding', report)
        self.assertNotIn('-D', report)

    def setUp(self):
        self.text = """CPU_COREMARK_START iterations=5000 clock_hz=100000000
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
Correct operation validated. See readme.txt for run and reporting rules.
CPU_COREMARK_STATUS errors=0 short=0
CPU_COREMARK_TIME seconds=16.858310 cycles_hi=0 cycles_lo=1685831000 clock_hz=100000000
CoreMark       : 296.589634
CoreMark/MHz   : 2.965896
CPU_COREMARK_BOARD_PASS iterations=5000
"""

    def test_requires_implemented_uart_review(self):
        self.assertTrue(hasattr(coremark_board, 'review_output'), 'board UART score reviewer is missing')

    def review(self, text=None, short=False):
        self.assertTrue(hasattr(coremark_board, 'review_output'), 'board UART score reviewer is missing')
        return coremark_board.review_output(self.text if text is None else text, allow_short=short)

    def test_precise_score_uses_cycles_and_not_integer_seconds(self):
        result = self.review()
        self.assertEqual(result['cycles'], 1685831000)
        self.assertAlmostEqual(result['coremark_per_mhz'], float(Decimal(5000000000) / Decimal(1685831000)))
        self.assertTrue(result['duration_valid'])

    def test_coremark_per_lut_uses_measured_cpu_luts(self):
        text = self.text.replace('CPU_COREMARK_BOARD_PASS',
                                 'CPU core LUTs  : 6000\nCoreMark/LUTs  : 0.049431\nCPU_COREMARK_BOARD_PASS')
        result = self.review(text)
        self.assertEqual(result.get('cpu_core_luts'), 6000, 'CPU-only LUT denominator must be reported')
        self.assertAlmostEqual(result['coremark_per_lut'], result['coremark'] / 6000)

    def test_coremark_per_lut_rejects_wrong_or_zero_denominator(self):
        for count, score in ((0, '0.049431'), (6000, '0.050000')):
            text = self.text.replace('CPU_COREMARK_BOARD_PASS',
                f'CPU core LUTs  : {count}\nCoreMark/LUTs  : {score}\nCPU_COREMARK_BOARD_PASS')
            with self.subTest(count=count), self.assertRaises(ValueError):
                self.review(text)

    def test_rejects_bad_crc(self):
        with self.assertRaisesRegex(ValueError, 'CRC'):
            self.review(self.text.replace('0xe714', '0xe715'))

    def test_rejects_error_or_trap(self):
        for text in (self.text.replace('errors=0', 'errors=1'), self.text + 'CPU_TRAP cause=2\n'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.review(text)

    def test_short_simulation_cannot_be_physical_pass(self):
        text = self.text.replace('5000', '5').replace('16.858310', '0.016858').replace('1685831000', '1685831')
        text = text.replace('short=0', 'short=1').replace('CPU_COREMARK_BOARD_PASS', 'CPU_COREMARK_PREFLIGHT_PASS')
        with self.assertRaises(ValueError):
            self.review(text)
        self.assertFalse(self.review(text, short=True)['duration_valid'])

    def test_rejects_wrong_score_and_incomplete_result(self):
        for text in (self.text.replace('296.589634', '312.500000'), self.text.replace('CPU_COREMARK_BOARD_PASS', 'INCOMPLETE')):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.review(text)


if __name__ == '__main__':
    unittest.main()

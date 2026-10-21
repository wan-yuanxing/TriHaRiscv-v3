"""Reject incomplete/misleading multiclock timing and board validation evidence."""
import unittest
from review_ddr_board import parse_timing, matched_pins


def report():
    text = '''Timing analysis mode : multi corner
 cpu_clk 10.0000 {0.0000 5.0000} Generated (ref_clk) 4000 1 {PLL/CLKOUT}
 cpu_clk 100.0000 MHz 102.0000 MHz 10.0000 9.8040 0.196
Design Summary : All Constraints Met.
'''
    for corner in ['Slow', 'Fast']:
        for kind in ['Setup', 'Hold', 'Recovery', 'Removal', 'Minimum Pulse Width']:
            text += kind+' Summary('+corner+' Corner):\n'+'*'*100+'\nHeader\n'+'-'*100+'\n'
            if kind == 'Minimum Pulse Width':
                text += ' cpu_clk 3.655 0.000 0 4000\n ddrphy_sysclk 2.501 0.000 0 3000\n'
            else:
                text += ' cpu_clk cpu_clk '+('0.196' if kind == 'Setup' else '0.100')+' 0.000 0 10000\n'
                text += ' ddrphy_sysclk ddrphy_sysclk 0.200 0.000 0 9000\n'
            text += '='*100+'\n'
    return text


class TimingTests(unittest.TestCase):
    def test_all_clock_rows_in_both_corners(self):
        result = parse_timing(report())
        self.assertTrue(result['summary_met'])
        self.assertEqual(len(result['rows']), 20)
        self.assertFalse(result['physical_admitted'])

    def test_other_clock_violation_cannot_hide_behind_cpu_pass(self):
        text = report().replace('ddrphy_sysclk ddrphy_sysclk 0.200 0.000 0 9000',
            'ddrphy_sysclk ddrphy_sysclk -0.002 -0.004 2 9000', 1)
        self.assertFalse(parse_timing(text)['summary_met'])

    def test_missing_corner_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_timing(report().replace('Hold Summary(Fast Corner):', 'omitted:'))

    def test_performance_slack_must_agree(self):
        text = report().replace('9.8040 0.196', '9.8040 0.300')
        self.assertFalse(parse_timing(text)['summary_met'])

    def test_empty_endpoint_set_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_timing(report().replace('0.196 0.000 0 10000', '0.196 0.000 0 0', 1))

    def test_duplicated_summary_is_rejected(self):
        text = report()
        with self.assertRaises(ValueError):
            parse_timing(text+text)


class ConstraintMatchTests(unittest.TestCase):
    def fixture(self):
        return """I: The pattern 'pointer-expression' in command 'get_pins -regexp pointer-expression' match 3 objects below:
I: pin u_cdc/wr_gray[0]/Q
I: pin u_cdc/wr_gray[1]/Q
I: pin u_cdc/wr_gray[2]/Q
"""

    def test_actual_reported_pins_are_preserved(self):
        pins = matched_pins(self.fixture())['pointer-expression']
        self.assertEqual(pins, ['u_cdc/wr_gray[0]/Q','u_cdc/wr_gray[1]/Q','u_cdc/wr_gray[2]/Q'])

    def test_missing_actual_match_is_rejected(self):
        with self.assertRaises(ValueError):
            matched_pins(self.fixture().replace('I: pin u_cdc/wr_gray[2]/Q\n', ''))

    def test_inconsistent_repeated_match_is_rejected(self):
        with self.assertRaises(ValueError):
            matched_pins(self.fixture()+self.fixture().replace('wr_gray[2]', 'rd_gray[2]'))


if __name__ == '__main__':
    unittest.main()

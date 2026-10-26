"""A mapping gate must reject incomplete reports and absent FIFO evidence."""
from pathlib import Path
import tempfile
import unittest

from check_fifo_controlsets import inspect


class ControlsetEvidenceTests(unittest.TestCase):
    def test_attributed_flops_are_counted_without_comment_tokens(self):
        self.report.write_text('Number of unique control sets : 1\n'
                               '  CLK(clk), CE(u_fifo.enable) : 2\n'
                               'Number of DFF:CE Signals : 1\n'
                               'Number of DFF:CLK Signals : 1\n'
                               'Number of DFF:CP Signals : 1\n'
                               'Number of DFF:RS Signals : 1\n', encoding='utf-8')
        netlist = self.report.parent / 'syn.vm'
        netlist.write_text('module triha_fetch_fifo();\n'
                          '  GTP_DFF_CE a (.Q(q0));\n'
                          '(* PAP_PRESERVE="TRUE" *) GTP_DFF_CE b (.Q(q1));\n'
                          '// GTP_DFF_CE fake (.Q(q2));\n'
                          'endmodule\n', encoding='utf-8')
        self.assertEqual(inspect(self.report, 1, netlist)['fifo_ff_total'], 2)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.report = Path(self.temp.name) / 'controlsets.txt'

    def test_header_only_is_not_mapping_evidence(self):
        self.report.write_text('Number of unique control sets : 597\n', encoding='utf-8')
        with self.assertRaises(ValueError):
            inspect(self.report, 192)

    def test_truncated_control_signal_sections_are_rejected(self):
        self.report.write_text('Number of unique control sets : 1\n'
                               '  CLK(clk), CE(other.enable) : 32\n', encoding='utf-8')
        with self.assertRaises(ValueError):
            inspect(self.report, 192)

    def test_complete_but_unbound_report_is_rejected(self):
        self.report.write_text('Number of unique control sets : 1\n'
                               '  CLK(clk), CE(other.enable) : 32\n'
                               'Number of DFF:CE Signals : 1\n'
                               'Number of DFF:CLK Signals : 1\n'
                               'Number of DFF:CP Signals : 1\n'
                               'Number of DFF:RS Signals : 1\n', encoding='utf-8')
        with self.assertRaises(ValueError):
            inspect(self.report, 192)


if __name__ == '__main__':
    unittest.main()

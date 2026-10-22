"""Board pins and CDC exceptions must preserve the accepted clock/IO contract."""
import re
from pathlib import Path
import unittest
from gen_ddr_board import generated

ROOT = Path(__file__).resolve().parents[2]


class BoardConfigTests(unittest.TestCase):
    def test_all_ddr_pin_attributes_are_preserved(self):
        actual = generated()['fpga/pg2l100h/constraints/cpu_ddr_board.fdc']
        base = (ROOT/'fpga/pg2l100h/constraints/video_ddr_bist.fdc').read_text(encoding='utf-8')
        pattern = r'(?m)^define_attribute \{p:(mem_[^}]+)\} \{([^}]+)\} \{([^}]+)\}$'
        self.assertEqual(re.findall(pattern, actual), re.findall(pattern, base))
        self.assertEqual(sum(attr == 'PAP_IO_LOC' for name,attr,value in re.findall(pattern, actual)), 71)

    def test_cpu_clock_and_original_io_budgets_are_explicit(self):
        text = generated()['fpga/pg2l100h/constraints/cpu_ddr_board.fdc']
        self.assertIn('create_generated_clock -name cpu_clk', text)
        self.assertIn('-multiply_by 4 -divide_by 5', text)
        self.assertIn('set_input_delay 2.000', text)
        self.assertIn('set_input_delay 0.500', text)
        self.assertIn('set_output_delay 2.000', text)
        resets = [s for s in text.splitlines() if s.startswith('set_false_path -from [get_ports {rst_ni}]')]
        self.assertEqual(resets, ['set_false_path -from [get_ports {rst_ni}] -to [get_pins {u_supervisor.free_release_q*/C}]'])

    def test_gray_constraints_cover_both_directions_of_all_queues(self):
        text = generated()['fpga/pg2l100h/constraints/cpu_ddr_board.fdc']
        self.assertEqual(text.count('set_max_skew 2.000'), 10)
        self.assertEqual(text.count('set_max_delay 8.000 -datapath_only'), 10)
        for channel in ['aw','w','b','ar','r']:
            self.assertIn('u_'+channel+'_fifo/wr_gray', text)
            self.assertIn('u_'+channel+'_fifo/rd_gray', text)
        self.assertNotIn('telemetry.', text)
        self.assertNotIn('bist.', text)

    def test_gray_launch_selection_cannot_include_synchronizer_flops(self):
        text = generated()['fpga/pg2l100h/constraints/cpu_ddr_board.fdc']
        for line in text.splitlines():
            if line.startswith('set_max_delay'):
                self.assertIn('-from [get_pins -regexp -hsc / {', line)
                selection = line.split('-from [get_pins -regexp -hsc / {')[1].split('}]')[0]
                for cell, pin in [('wr_gray[2:0]','Q[0]'),('wr_gray[0]','Q')]:
                    name = 'u_system/u_cdc/u_aw_fifo/'+cell+'/'+pin
                    if 'u_aw_fifo/wr_gray' in selection:
                        self.assertIsNotNone(re.fullmatch(selection, name))
                self.assertIsNone(re.fullmatch(selection, 'u_system/u_cdc/u_aw_fifo/wr_gray_rd_sync1[0]/Q'))

    def test_reference_clock_reset_release_is_timed_against_ddr(self):
        text = generated()['fpga/pg2l100h/constraints/cpu_ddr_board.fdc']
        self.assertNotIn('set_clock_groups -name ref_clk -asynchronous', text)
        self.assertIn('reference_release_q*/C', text)


if __name__ == '__main__':
    unittest.main()

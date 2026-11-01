"""Bounded preparation checks; no PDS, serial access or hardware mutation."""
import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]


class Preparation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path=ROOT/'scripts/cpu/prepare_dual_board.py'
        if not path.exists():
            cls.helper=None
            return
        spec=importlib.util.spec_from_file_location('dual_board_prepare',path)
        cls.helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.helper)

    def test_preparation_exists(self):
        self.assertIsNotNone(self.helper,'dual board preparation is missing')

    def test_mode_gate(self):
        self.assertIsNotNone(self.helper,'dual board preparation is missing')
        with self.assertRaises(ValueError):self.helper.require_dual_soc('triha_core #(.DUAL_ISSUE(0)) u_core();')
        self.helper.require_dual_soc('triha_core #(.DUAL_ISSUE(1)) u_core();')

    def test_dual_testbench_checks_real_pairing_and_both_wb_lanes(self):
        self.assertIsNotNone(self.helper,'dual board preparation is missing')
        source=(ROOT/'tb/soc/tb_cpu_coremark.v').read_text(encoding='utf-8')
        output=self.helper.dual_testbench(source)
        self.assertIn('SUPPORT_DUAL_ISSUE != 1',output)
        self.assertIn('CPU_BOARD_DUAL_PAIR_PASS',output)
        self.assertIn('if (paired == 0)',output)
        self.assertIn('if (`PROFILE_ISSUE.pipe1_valid_wb_w)',output)
        self.assertNotIn('timeout/dual lane',output)
        self.assertEqual((ROOT/'tb/soc/tb_cpu_coremark.v').read_text(encoding='utf-8'),source)

    def test_malformed_template_rejected(self):
        self.assertIsNotNone(self.helper,'dual board preparation is missing')
        with self.assertRaises(ValueError):self.helper.dual_testbench('module empty; endmodule')

    def test_hash_gate(self):
        self.assertIsNotNone(self.helper,'dual board preparation is missing')
        with self.assertRaises(ValueError):self.helper.require_digest(b'bad source','0'*64,'CPU source')

    def test_registered_status_leds_rejects_unrecognized_template(self):
        with self.assertRaises(ValueError):self.helper.registered_status_leds('module empty; endmodule')


if __name__=='__main__':unittest.main()

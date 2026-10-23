import json
import tempfile
import unittest
from pathlib import Path
import prepare_dual_physical as m

class PhysicalGateTests(unittest.TestCase):
    def test_rejects_unfinished_or_changed_simulation(self):
        for row in [dict(status='RUNNING'),dict(status='PASS',source_unchanged=False)]:
            with self.assertRaises(ValueError):m.check_simulation(row)

    def test_rejects_missing_actual_dual_evidence(self):
        row=dict(status='PASS',source_unchanged=True,external_unchanged=True,runner_return_code=0,test='coremark',fault='none')
        with self.assertRaises(ValueError):m.check_simulation(row)

    def test_tcl_keeps_multicorner_hold_and_no_programming(self):
        core=dict(family='Logos2',device='PG2L100H',speedgrade='-6',package='FBG676')
        text=m.tcl(Path('D:/test'),core,['rtl/a.v'],'clock.fdc')
        self.assertIn('-fix_hold_violation',text)
        self.assertIn('-optimize_multi_corner_timing',text)
        self.assertIn('report_timing',text)
        self.assertNotIn('program_device',text)
        self.assertNotIn('generate_bitstream',text)

if __name__=='__main__':unittest.main()

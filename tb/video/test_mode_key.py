"""New board pin notices require the exact reviewed electrical mapping."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/video'))
import build_pds


class ModeKeyTests(unittest.TestCase):
    def setUp(self):
        self.reference=json.loads((ROOT/'fpga/pg2l100h/ip/video_mode_key_manifest.json').read_text(encoding='utf-8'))
        self.fdc=(ROOT/'fpga/pg2l100h/constraints/video_mode_board.fdc').read_text(encoding='utf-8')

    def test_verified_key_pin_notice_only(self):
        mapping=build_pds.verify_mode_key_reference(self.reference,self.fdc)
        notice='C: ConstraintEditor-2002: [board] | Port mode_button_n has been placed at location C23, whose type is share pin.'
        self.assertEqual(build_pds.review_messages(notice,mapping),([notice],[]))
        self.assertTrue(build_pds.review_messages(notice.replace('C23','C22'),mapping)[1])

    def test_wrong_reference_pin_polarity_or_voltage_rejected(self):
        for field,value in (('pin','C22'),('active_low',False),('port','rst_in')):
            bad=copy.deepcopy(self.reference);bad[field]=value
            with self.assertRaises(ValueError):build_pds.verify_mode_key_reference(bad,self.fdc)
        bad=copy.deepcopy(self.reference);bad['attributes']['PAP_IO_VCCIO']='1.8'
        with self.assertRaises(ValueError):build_pds.verify_mode_key_reference(bad,self.fdc)

    def test_missing_changed_or_duplicate_constraint_rejected(self):
        for bad in (self.fdc.replace('{C23}','{C22}'),self.fdc.replace('{LVCMOS33}','{LVCMOS18}'),
                    self.fdc.replace('define_attribute {p:mode_button_n} {PAP_IO_NONE} {TRUE}',''),
                    self.fdc+'\ndefine_attribute {p:mode_button_n} {PAP_IO_LOC} {C23}\n'):
            with self.assertRaises(ValueError):build_pds.verify_mode_key_reference(self.reference,bad)


if __name__=='__main__':unittest.main()

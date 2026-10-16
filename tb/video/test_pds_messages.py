import sys
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/video'))
import build_pds


class PdsMessageTests(unittest.TestCase):
    def test_only_exact_verified_board_pin_notice_is_accepted(self):
        self.assertTrue(hasattr(build_pds,'review_messages'), 'PDS diagnostic review missing')
        fdc='define_attribute {p:r_out[7]} {PAP_IO_LOC} {P16}\n'
        notice='C: ConstraintEditor-2002: [path] | Port r_out[7] has been placed at location P16, whose type is share pin.'
        reviewed,rejected=build_pds.review_messages(notice,fdc)
        self.assertEqual(reviewed,[notice])
        self.assertEqual(rejected,[])
        _,rejected=build_pds.review_messages(notice.replace('P16','P17'),fdc)
        self.assertTrue(rejected)

    def test_unknown_critical_and_error_are_rejected(self):
        self.assertTrue(hasattr(build_pds,'review_messages'), 'PDS diagnostic review missing')
        _,rejected=build_pds.review_messages('C: STA-3017: hold failure\nE: synthesis failed','')
        self.assertEqual(len(rejected),2)


if __name__=='__main__': unittest.main()

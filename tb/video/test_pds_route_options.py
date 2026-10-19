"""Reproducible placement choices must not alter timing constraints."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/video'))
import build_pds


class RouteOptionsTests(unittest.TestCase):
    def test_default_preserves_existing_six_seed_arguments(self):
        self.assertEqual(build_pds.combined_route_options(),
                         ' -gplace_seed 4 -gplace_times 6 -seed_step 1 -saved_outcome 1 -parallel 1')

    def test_single_candidate_performance_trial(self):
        self.assertEqual(build_pds.combined_route_options(8,1,'performance'),
                         ' -gplace_seed 8 -gplace_times 1 -seed_step 1 -saved_outcome 1 -parallel 1 -mode performance')

    def test_invalid_values_never_reach_tcl(self):
        for args in ((True,1,None),(4,False,None),(-1,6,None),(0,1,None),(1,0,None),
                     (2147483646,6,None),('4',6,None),(4,1,'performance; error unsafe')):
            with self.subTest(args=args),self.assertRaises(ValueError):build_pds.combined_route_options(*args)


if __name__=='__main__':unittest.main()

"""Regression for PDS replacing earlier RCFs and rejecting unfixed endpoints."""
from pathlib import Path
import tempfile
import unittest

from common import ROOT
from reroute_face import merge_route_constraints, route_constraint_error


class RouteConstraintsTest(unittest.TestCase):
    def test_vendor_and_application_routes_share_one_rcf(self):
        vendor = ROOT/'fpga/pg2l100h/constraints/triha_face_phy.rcf'
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            priority = work/'priority.rcf'
            priority.write_text('def_route -prior_net {application/bvalid}\n')
            fixed = work/'fixed.rcf'
            fixed.write_text('def_route {ddr/address} {Q2:CLMA_327_162;AD:CLMS_327_163;}\n')
            output = work/'routing.rcf'
            merge_route_constraints([vendor, priority, fixed], output)
            commands = [line for line in output.read_text().splitlines() if not line.startswith('#')]
            self.assertEqual(len(commands), 4)
            for bit in (0, 1):
                self.assertIn('def_route -prior_net {g_full.impl/I_ips_ddr_top/u_ddrphy_top/ddrphy_ioclk_gate ['+str(bit)+']}', commands)
            self.assertIn('def_route -prior_net {application/bvalid}', commands)
            self.assertIn('def_route {ddr/address} {Q2:CLMA_327_162;AD:CLMS_327_163;}', commands)

    def test_pds_rcf_replacement_is_fatal(self):
        line = 'W: RouteConstraintEditor-4001: Only one .rcf file can be added, old .rcf file is cleared.'
        self.assertEqual(route_constraint_error(line), line)

    def test_pds_endpoint_rejection_is_fatal(self):
        for line in ('C: RouteConstraintEditor-2004: The Instance is unConstraint in pcf',
                     'C: RouteConstraintEditor-2006: This constraint has error.'):
            with self.subTest(line=line):
                self.assertEqual(route_constraint_error(line), line)

    def test_successful_route_command_is_not_rejected(self):
        self.assertIsNone(route_constraint_error('Executing : def_route -prior_net {ddr/clock} successfully.'))


if __name__ == '__main__':
    unittest.main()

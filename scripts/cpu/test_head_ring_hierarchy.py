"""A port rename must not hide late-control support across hierarchy."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest


FIXTURE = r'''module triha_fetch_fifo(input clk_i,input pop0_i,input pop1_i,input imported,input data_i);
wire q;
GTP_DFF_E \ring_q[0][0] (.CLK(clk_i),.CE(imported),.D(data_i),.Q(q));
endmodule
module triha_minimal_soc(input clk_i,input pop0,input pop1,input push,input data_i);
wire moved;
GTP_LUT1 gate (.I0(push),.Z(moved));
triha_fetch_fifo fifo (.clk_i(clk_i),.pop0_i(pop0),.pop1_i(pop1),.imported(moved),.data_i(data_i));
endmodule
'''


class HierarchyGateTests(unittest.TestCase):
    def run_fixture(self, source):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'netlist.vm').write_text(source, encoding='utf-8')
            process = subprocess.run([sys.executable, str(Path(__file__).with_name('trace_head_ring_hierarchy.py')),
                                      str(root / 'netlist.vm'), str(root / 'result.json')], capture_output=True)
            result = json.loads((root / 'result.json').read_text()) if (root / 'result.json').exists() else None
            return process.returncode, result

    def test_independent_imported_port(self):
        code, row = self.run_fixture(FIXTURE)
        self.assertEqual(code, 0)
        self.assertEqual(row['backend_pins'], 2)

    def test_hidden_pop_through_parent_gate(self):
        code, row = self.run_fixture(FIXTURE.replace('.I0(push)', '.I0(pop0)'))
        self.assertNotEqual(code, 0)
        self.assertEqual(row['status'], 'FAIL')
        self.assertTrue(row['late_hits'])

    def test_unknown_primitive_is_blocking(self):
        code, row = self.run_fixture(FIXTURE.replace('GTP_LUT1', 'GTP_UNKNOWN'))
        self.assertNotEqual(code, 0)
        self.assertEqual(row['status'], 'UNKNOWN')

    def test_no_backend_is_blocking(self):
        code, _ = self.run_fixture(FIXTURE.replace('ring_q', 'head0_q'))
        self.assertNotEqual(code, 0)

    def dual_output_fixture(self, output='Z5', init="64'h3cf03cf0e0e0e0e0"):
        return FIXTURE.replace('GTP_LUT1 gate (.I0(push),.Z(moved));',
            f'GTP_LUT6D #(.INIT({init})) gate '
            f'(.I0(push),.I1(data_i),.I2(push),.I3(pop0),.I4(pop1),.I5(push),.{output}(moved));')

    def test_dual_output_lower_table_excludes_pop(self):
        code, row = self.run_fixture(self.dual_output_fixture())
        self.assertEqual(code, 0)
        self.assertEqual(row['status'], 'PASS')

    def test_dual_output_upper_table_keeps_pop(self):
        code, row = self.run_fixture(self.dual_output_fixture(output='Z'))
        self.assertNotEqual(code, 0)
        self.assertEqual(row['status'], 'FAIL')

    def test_dual_output_corrupt_lower_table_detects_pop(self):
        code, row = self.run_fixture(self.dual_output_fixture(init="64'h3cf03cf0e0e0e1e0"))
        self.assertNotEqual(code, 0)
        self.assertEqual(row['status'], 'FAIL')

    def test_dual_output_unknown_init_stays_conservative(self):
        code, row = self.run_fixture(self.dual_output_fixture(init="64'hxxxxxxxxxxxxxxxx"))
        self.assertNotEqual(code, 0)
        self.assertTrue(row['late_hits'])

    def test_dual_output_missing_init_stays_conservative(self):
        source = self.dual_output_fixture().replace("#(.INIT(64'h3cf03cf0e0e0e0e0)) ", '')
        code, row = self.run_fixture(source)
        self.assertNotEqual(code, 0)
        self.assertTrue(row['late_hits'])


if __name__ == '__main__':
    unittest.main()

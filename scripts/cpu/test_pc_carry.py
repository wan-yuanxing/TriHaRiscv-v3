"""Reject late arithmetic control and incomplete structural evidence."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CHECKER = Path(__file__).with_name('check_pc_carry.py')


class PcCarryContracts(unittest.TestCase):
    def run_checker(self, late=False, missing_driver=False, missing_request=False):
        with tempfile.TemporaryDirectory() as name:
            folder = Path(name)
            control = 'pc_i[1]' if missing_request else 'branch_taken_r'
            carry_input = control if late else 'pc_i[1]'
            body = 'module test_exec;\ninput [31:0] pc_i;\n'
            if not missing_request:
                body += 'input branch_taken_r;\n'
            body += ('GTP_LUT6CARRY carry (.I0(pc_i[0]),.I1(' + carry_input + '),.COUT(sum));\n'
                     'GTP_LUT3 select_pc (.I0(sum),.I1(' + control + '),.Z(next_pc));\n')
            for i in range(32):
                body += f'GTP_DFFQ \\pc_x_q[{i}]  (.D({"unknown" if missing_driver else "next_pc"}),.Q(q{i}));\n'
            netlist, output = folder / 'test.vm', folder / 'result.json'
            netlist.write_text(body + 'endmodule\n', encoding='utf-8')
            result = subprocess.run([sys.executable, str(CHECKER), str(netlist), '--output', str(output),
                                     '--module', 'test_exec', '--requests', 'branch_taken_r'],
                                    capture_output=True, text=True)
            return result, json.loads(output.read_text()) if output.exists() else None

    def test_selection_after_arithmetic_passes(self):
        result, evidence = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(evidence['pc_roots'], 32)
        self.assertEqual(evidence['pc_carry_outputs_checked'], 1)
        self.assertEqual(evidence['violations'], [])

    def test_late_request_inside_carry_is_rejected(self):
        result, evidence = self.run_checker(late=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(evidence['violations']), 1)

    def test_unknown_driver_cannot_be_accepted(self):
        result, evidence = self.run_checker(missing_driver=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unrecognized PC cone', result.stderr)
        self.assertIsNone(evidence)

    def test_missing_requested_signal_cannot_pass_vacuously(self):
        result, evidence = self.run_checker(missing_request=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Late request signal missing', result.stderr)
        self.assertIsNone(evidence)


if __name__ == '__main__':
    unittest.main()

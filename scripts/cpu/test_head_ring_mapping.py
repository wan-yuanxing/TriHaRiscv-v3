import unittest
from check_head_ring_mapping import analyze


class HeadRingMappingTests(unittest.TestCase):
    def fixture(self, control='push_i', primitive='GTP_LUT2'):
        return '''module triha_fetch_fifo(input clk_i, input push_i, input pop0_i, input pop1_i, input data_i);
        GTP_LUT2 gate (.I0(CONTROL),.I1(data_i),.Z(en));
        (* PAP_PRESERVE="TRUE" *) GTP_DFF_E \\ring_q[0][0] (.CLK(clk_i),.CE(en),.D(data_i),.Q(q));
        endmodule'''.replace('CONTROL', control).replace('GTP_LUT2', primitive)

    def test_enqueue_only_passes(self):
        row = analyze(self.fixture())
        self.assertEqual(row['status'], 'PASS')
        self.assertEqual(row['backend_ff_count'], 1)

    def test_late_control_is_rejected(self):
        self.assertEqual(analyze(self.fixture('pop1_i'))['status'], 'FAIL')

    def test_unknown_driver_is_not_a_pass(self):
        with self.assertRaises(ValueError):
            analyze(self.fixture('undriven'))

    def test_unknown_primitive_is_not_a_pass(self):
        with self.assertRaises(ValueError):
            analyze(self.fixture(primitive='GTP_UNSUPPORTED'))

    def test_absent_backend_is_not_a_pass(self):
        with self.assertRaises(ValueError):
            analyze(self.fixture().replace('ring_q', 'head0_q'))


if __name__ == '__main__':
    unittest.main()

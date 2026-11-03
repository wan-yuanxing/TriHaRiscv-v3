"""Reject logical changes disguised as physical Gray routing buffers."""
import copy
import hashlib
from pathlib import Path
import tempfile
import unittest

from face_gray_netlist import GrayNetlist, load_evidence, V_BUF_MODEL_SHA256


START = 'ingress/fifo/wr_gray[8]/opit_0_inv'
END = 'ingress/fifo/wr_gray_rd_sync1[8]/opit_0_inv'
SOURCE = r'''V_FFASYN /* ingress/fifo/wr_gray[8]/opit_0_inv/FF0/FF */ #(
 .GRS_EN("TRUE"), .INIT(1'b0)) \CLMA_75_1080/FF0/FF (
 .Q (\ingress/fifo/wr_gray [8] ), .CE (1'b1), .CK (src_clk), .D (next_gray), .SR (rst));
'''
DEST = r'''V_FFASYN /* ingress/fifo/wr_gray_rd_sync1[8]/opit_0_inv/FF0/FF */ #(
 .GRS_EN("TRUE"), .INIT(1'b0)) \CLMS_75_1063/FF0/FF (
 .Q (sync_gray), .CE (1'b1), .CK (dst_clk), .D (ntR12216), .SR (rst));
'''
BUFFER = r'''V_BUF \CLMS_75_1081/ntM3 (
 .Z (ntR12216), .I (\ingress/fifo/wr_gray [8] ));
'''
BLOCK = ' CLMS_75_1081/CR3 td 0.125 0.464 r CLKROUTE_107/CR\n'
NETLIST = SOURCE+DEST+BUFFER


class IdentityProofTest(unittest.TestCase):
    def prove(self, text=NETLIST, block=BLOCK, levels=1):
        return GrayNetlist(text).prove(block, START, END, levels)

    def test_buffer_keeps_the_same_gray_bit(self):
        self.assertEqual(self.prove(), dict(identity_buffers=1, sites=['CLMS_75_1081']))

    def test_inverter_is_not_an_identity_buffer(self):
        with self.assertRaisesRegex(ValueError, 'unproven logic'):
            self.prove(NETLIST.replace('V_BUF ', 'V_INV '))

    def test_wrong_source_bit_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'wrong-bit'):
            self.prove(SOURCE+DEST+BUFFER.replace('wr_gray [8]', 'wr_gray [7]'))

    def test_extra_gate_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'unproven logic'):
            self.prove(NETLIST.replace('.I (\\ingress/fifo/wr_gray [8] )', '.I (gated_gray)'))

    def test_duplicate_endpoint_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'unique native register'):
            self.prove(NETLIST+SOURCE)

    def test_buffer_loop_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'unproven logic'):
            self.prove(SOURCE+DEST+BUFFER.replace('\\ingress/fifo/wr_gray [8] ', 'ntR12216'))

    def test_wrong_physical_site_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'physical chain differ'):
            self.prove(block=BLOCK.replace('CLMS_75_1081', 'CLMS_75_1087'))

    def test_unaccounted_logic_level_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'physical chain differ'):
            self.prove(levels=2)

    def test_functional_gate_in_sta_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'physical chain differ'):
            self.prove(block=BLOCK.replace('CLKROUTE_107/CR', 'gate/L6'))

    def test_evidence_is_bound_to_route_files_and_reviewed_model(self):
        model = Path('D:/pango/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/bsim/V_BUF.v')
        with tempfile.TemporaryDirectory() as directory:
            netlist = Path(directory)/'sim.v'
            netlist.write_text(NETLIST, encoding='utf-8')
            record = dict(routed_db_sha256='route_digest',
                          model=dict(path=str(model), sha256=V_BUF_MODEL_SHA256),
                          netlist=dict(path=str(netlist), sha256=hashlib.sha256(netlist.read_bytes()).hexdigest()))
            load_evidence(record, 'route_digest').prove(BLOCK, START, END, 1)
            with self.assertRaisesRegex(ValueError, 'different route'):
                load_evidence(record, 'another_route')
            altered = copy.deepcopy(record)
            altered['model']['sha256'] = '0'*64
            with self.assertRaisesRegex(ValueError, 'evidence changed'):
                load_evidence(altered, 'route_digest')
            other_model = Path(directory)/'V_BUF.v'
            other_model.write_text('module V_BUF(output Z,input I); assign Z=~I; endmodule\n')
            altered['model'] = dict(path=str(other_model), sha256=hashlib.sha256(other_model.read_bytes()).hexdigest())
            with self.assertRaisesRegex(ValueError, 'Unreviewed V_BUF'):
                load_evidence(altered, 'route_digest')
            netlist.write_text(NETLIST.replace('V_BUF ', 'V_INV '), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'evidence changed'):
                load_evidence(record, 'route_digest')


if __name__ == '__main__':
    unittest.main()

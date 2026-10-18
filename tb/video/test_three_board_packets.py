"""Three-branch readback qualification is distinct from a numerical NPU proof."""
import copy
from functools import reduce
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'scripts/video'))
from read_board import decode_packets


def packet(kind, values, heartbeat, flags=0x75, phase=0xa5, error=0):
    raw = b'TRV1'+struct.pack('<4B7I', kind, flags, phase, error, *values, heartbeat)
    return raw+bytes([reduce(int.__xor__, raw, 0)])


def records():
    raw = b''
    for beat, scan in ((101, 7), (110, 9)):
        raw += packet(6, [480000, 120000, 0x12345678, 0x12345678, 0x23456789, 0x23456789], beat)
        raw += packet(7, [1, 1, scan, 0, 300*scan+1, 222], beat+1)
        raw += packet(8, [1, 1, 76800, 307200, 307200, 0x6a55c3e1], beat+2)
    return decode_packets(raw)


class ThreePacketTests(unittest.TestCase):
    def qualify(self, rows):
        from read_board import qualify_three_readback
        return qualify_three_readback(rows)

    def test_type8_fields_and_complete_three_type_suffix(self):
        rows = records()
        self.assertEqual(len(rows), 6)
        self.assertEqual(rows[-1]['capture_frame_id'], 1)
        self.assertEqual(rows[-1]['preprocess_version'], 1)
        self.assertEqual(rows[-1]['input_pixels'], 76800)
        self.assertEqual(rows[-1]['input_written_bytes'], 307200)
        self.assertEqual(rows[-1]['input_checked_bytes'], 307200)
        self.assertEqual(rows[-1]['input_ddr_crc'], 0x6a55c3e1)
        self.assertTrue(self.qualify(rows))

    def test_later_fault_restart_of_any_type_invalidates_old_success(self):
        for kind in (6, 7, 8):
            for changes in ({'flags':0x7d, 'error':3}, {'flags':0x73, 'phase':0x30}):
                rows = records()+decode_packets(packet(kind, [0]*6, 125, **changes))
                self.assertFalse(self.qualify(rows), (kind, changes))
                from read_board import qualify_preview_capture, qualify_preview_display
                self.assertFalse(qualify_preview_capture(rows), (kind, changes, 'capture'))
                self.assertFalse(qualify_preview_display(rows), (kind, changes, 'display'))

    def test_missing_stale_mismatched_short_or_unknown_input_rejected(self):
        good = records()
        for kind in (6, 7, 8):
            self.assertFalse(self.qualify([r for r in good if r['type'] != kind]))
        bad_fields = {'capture_frame_id':2, 'preprocess_version':2, 'input_pixels':76799,
                      'input_written_bytes':307199, 'input_checked_bytes':307199,
                      'input_ddr_crc':-1, 'heartbeat':103}
        for key, value in bad_fields.items():
            rows = copy.deepcopy(good)
            rows[-1][key] = value
            self.assertFalse(self.qualify(rows), key)
        rows = copy.deepcopy(good)
        rows[-1]['input_ddr_crc'] ^= 1
        self.assertFalse(self.qualify(rows))
        rows = copy.deepcopy(good)
        rows[0]['source_crc'] ^= 1
        rows[0]['ddr_crc'] ^= 1
        self.assertFalse(self.qualify(rows), 'one-shot raw content changed')
        for field in good[-1]:
            rows = copy.deepcopy(good)
            rows[-1].pop(field)
            self.assertFalse(self.qualify(rows), field)

    def test_zero_crc_and_heartbeat_wrap_are_legal(self):
        rows = records()
        for row in rows:
            if row['type']==8:
                row['input_ddr_crc']=0
        rows[2]['heartbeat']=0xffffffff
        rows[5]['heartbeat']=0
        self.assertTrue(self.qualify(rows))

    def test_bad_checksum_partial_and_noise_cannot_create_input_record(self):
        good = packet(8, [1, 1, 76800, 307200, 307200, 0x12345678], 123)
        bad = bytearray(good)
        bad[17] ^= 1
        self.assertEqual(decode_packets(b'noise'+bad+good[:30]), [])


if __name__=='__main__':
    unittest.main()

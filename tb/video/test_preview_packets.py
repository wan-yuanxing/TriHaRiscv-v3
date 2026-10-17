"""Raw/preview transport and display qualification stay separate."""
from functools import reduce
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts/video'))
from read_board import decode_packets, qualify_preview_capture, qualify_preview_display


def packet(kind, heartbeat=7, **changes):
    fields = dict(flags=0x75, phase=0xa5, error_code=0)
    if kind == 6:
        fields.update(captured_pixels=480000, preview_pixels=120000,
                      source_crc=0x12345678, ddr_crc=0x12345678,
                      preview_crc=0xabcdef01, preview_ddr_crc=0xabcdef01)
    else:
        fields.update(frame_id=1, commits=1, completed_scans=3,
                      underflows=0, read_lines=1200, fifo_peak=121)
    fields['heartbeat'] = heartbeat
    fields.update(changes)
    raw = b'TRV1' + struct.pack('<4B7I', kind, *fields.values())
    return raw + bytes([reduce(int.__xor__, raw)])


class PreviewPacketTests(unittest.TestCase):
    def healthy(self):
        return decode_packets(packet(6, 7) + packet(7, 9) + packet(6, 11) +
                              packet(7, 13, completed_scans=4, read_lines=1500))

    def test_both_planes_and_display_are_independent(self):
        records = self.healthy()
        self.assertTrue(qualify_preview_capture(records))
        self.assertTrue(qualify_preview_display(records))
        self.assertTrue(qualify_preview_capture([r for r in records if r['type'] == 6]))
        self.assertFalse(qualify_preview_display([r for r in records if r['type'] == 6]))
        self.assertFalse(qualify_preview_capture([r for r in records if r['type'] == 7]))

    def test_capture_requires_fresh_exact_counts_and_both_crc_pairs(self):
        changes = [{'flags': 0x75 ^ (1 << bit)} for bit in range(8)]
        changes += [dict(phase=0xa4), dict(error_code=1), dict(captured_pixels=479999),
                    dict(preview_pixels=119999), dict(ddr_crc=0), dict(preview_ddr_crc=0)]
        for change in changes:
            with self.subTest(change=change):
                self.assertFalse(qualify_preview_capture(decode_packets(packet(6, 7, **change) + packet(6, 9, **change))))
        self.assertFalse(qualify_preview_capture(decode_packets(packet(6) * 2)))
        self.assertFalse(qualify_preview_capture([]))
        self.assertTrue(qualify_preview_capture(decode_packets(packet(6, 0xffffffff, source_crc=0, ddr_crc=0) +
                                                             packet(6, 0, source_crc=0, ddr_crc=0))))

    def test_display_requires_same_frame_advancing_scans_and_no_underflow(self):
        healthy = self.healthy()
        for change in [dict(underflows=1), dict(commits=0), dict(completed_scans=0),
                       dict(frame_id=0), dict(fifo_peak=2049), dict(read_lines=1),
                       dict(flags=0x7d), dict(error_code=1), dict(phase=0xa4)]:
            records = [dict(row, **change) if row['type'] == 7 else row for row in healthy]
            self.assertFalse(qualify_preview_display(records), change)
        for field in ('frame_id', 'commits', 'completed_scans', 'read_lines', 'fifo_peak', 'heartbeat'):
            records = [dict(row) for row in healthy]
            records[-1].pop(field)
            self.assertFalse(qualify_preview_display(records), field)
        unchanged = [dict(row, completed_scans=3) if row['type'] == 7 else row for row in healthy]
        self.assertFalse(qualify_preview_display(unchanged))
        switched = [dict(row) for row in healthy]
        switched[-1]['frame_id'] = 2
        self.assertFalse(qualify_preview_display(switched))

    def test_missing_capture_fields_never_qualify(self):
        rows = [row for row in self.healthy() if row['type'] == 6]
        for field in rows[-1]:
            if field != 'flags':
                damaged = [dict(row) for row in rows]
                damaged[-1].pop(field)
                self.assertFalse(qualify_preview_capture(damaged), field)

    def test_corrupt_or_partial_new_packets_are_rejected(self):
        raw = bytearray(packet(6));raw[15] ^= 0x40
        self.assertEqual(decode_packets(bytes(raw) + packet(7)[:20]), [])

    def test_newer_display_fault_or_restart_revokes_old_capture_pass(self):
        for changes in (dict(flags=0x79,phase=0xe0,error_code=3),
                        dict(flags=0x73,phase=0x30,error_code=0)):
            records=self.healthy()+decode_packets(packet(7,15,**changes))
            self.assertFalse(qualify_preview_capture(records))
            self.assertFalse(qualify_preview_display(records))
        # Two new capture samples must follow the restart; a prior epoch's
        # healthy sample cannot supply the second heartbeat for qualification.
        records=self.healthy()+decode_packets(packet(7,1,flags=0x73,phase=0x30)+packet(6,7))
        self.assertFalse(qualify_preview_capture(records))
        records+=decode_packets(packet(6,9))
        self.assertTrue(qualify_preview_capture(records))
        self.assertFalse(qualify_preview_display(records))


if __name__ == '__main__':
    unittest.main()

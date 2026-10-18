"""Wire-format oracles for the independent image observer."""
from functools import reduce
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/video'))
from rx_image_probe import decode_probe_packets, pair_samples


def packet(kind,seq=7,version=1,reserved=0):
    values=([seq,480000,480000,799<<16,599<<16,0xb91c1c,0x15803d] if kind==8 else
            [seq,0x1d4ed8,0xa16207,0x33bac95a,0,0,0])
    data=b'TRV1'+struct.pack('<4B7I',kind,0xf5,version,reserved,*values)
    return data+bytes([reduce(int.__xor__,data)])


class ImageProbePackets(unittest.TestCase):
    def test_startup_history(self):
        data=b'TRV1'+struct.pack('<4B7I',10,0xf5,1,0,200,0x11111111,0x22222222,150,0x33333333,0x33bac95a,0)
        row=decode_probe_packets(data+bytes([reduce(int.__xor__,data)]))[0]
        self.assertEqual(row['crc_frame128'],'11111111')
        self.assertEqual(row['crc_frame129'],'22222222')
        self.assertEqual(row['last_change_frame'],150)
        self.assertEqual(row['crc_before_change'],'33333333')
        self.assertEqual(row['crc32'],'33bac95a')
    def test_paired_sample(self):
        rows=decode_probe_packets(packet(8)+packet(9))
        samples=pair_samples(rows)
        self.assertEqual(len(samples),1)
        self.assertEqual(samples[0]['quadrants'],[0xb91c1c,0x15803d,0x1d4ed8,0xa16207])
        self.assertEqual(samples[0]['x_bounds'],[0,799])
        self.assertEqual(samples[0]['y_bounds'],[0,599])
        self.assertEqual(samples[0]['crc32'],'33bac95a')

    def test_reject_corrupt_truncated_or_wrong_version(self):
        corrupt=bytearray(packet(8));corrupt[12]^=1
        for data in (corrupt,packet(8)[:-1],packet(8,version=2),packet(8,reserved=1)):
            self.assertEqual(decode_probe_packets(data),[])

    def test_no_cross_epoch_pair(self):
        self.assertEqual(pair_samples(decode_probe_packets(packet(8,7)+packet(9,8))),[])
        self.assertEqual(pair_samples(decode_probe_packets(packet(9)+packet(8))),[])

    def test_sequence_reuse_after_reboot_does_not_pair_old_half(self):
        # A normal boot/mode packet between halves invalidates the pair.
        rows=decode_probe_packets(packet(8))
        rows += [{'type':1,'mode_good':False}]
        rows += decode_probe_packets(packet(9))
        self.assertEqual(pair_samples(rows),[])


if __name__=='__main__':unittest.main()

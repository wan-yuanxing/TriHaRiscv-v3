import struct
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/video'))
from read_board import decode_packets, qualify_ddr


class PacketTests(unittest.TestCase):
    def packet(self,flags=0xe5,hz=40_000_000):
        payload=struct.pack('<BBH10HIHH',1,flags,7,800,600,1056,628,128,4,40,88,1,23,hz,21,2)
        raw=b'TRV1'+payload
        check=0
        for byte in raw:check^=byte
        return raw+bytes([check])

    def test_decodes_little_endian_measurements(self):
        result=decode_packets(self.packet())[0]
        self.assertEqual(result['pixel_hz'],40_000_000)
        self.assertEqual(result['h_active'],800)
        self.assertEqual(result['v_back'],23)
        self.assertTrue(result['mode_good'])
        self.assertEqual(result['bad_frames'],2)

    def test_corrupted_or_partial_packets_do_not_manufacture_success(self):
        bad=bytearray(self.packet());bad[16]^=0x80
        raw=b'noise'+self.packet()[:12]+bad+b'garbage'+self.packet(0,0)
        result=decode_packets(raw)
        self.assertEqual(len(result),1)
        self.assertFalse(result[0]['mode_good'])
        self.assertFalse(result[0]['frequency_good'])

    def ddr_packet(self, flags=0x15, count=3_014_685, heartbeat=7):
        raw=b'TRV1'+struct.pack('<4B7I',2,flags,0xff,0,count,0,0,0,0x3ff00000,32768,heartbeat)
        check=0
        for byte in raw:check^=byte
        return raw+bytes([check])

    def test_ddr_requires_fresh_complete_default_window_pass(self):
        records=decode_packets(self.ddr_packet(heartbeat=7)+self.ddr_packet(heartbeat=9))
        self.assertEqual(records[0]['compared_beats'],3_014_685)
        self.assertTrue(qualify_ddr(records))
        self.assertFalse(qualify_ddr(records[:1]))
        self.assertFalse(qualify_ddr(decode_packets(self.ddr_packet()*2)))
        for flags,count in ((0x1d,3_014_685),(0x05,3_014_685),(0x15,3_014_684)):
            self.assertFalse(qualify_ddr(decode_packets(self.ddr_packet(flags,count,7)+self.ddr_packet(flags,count,9))))

    def test_rx_probe_keeps_raw_pixel_durations_separate_from_line_metrics(self):
        raw=b'TRV1'+struct.pack('<BBH7I',3,0x75,0,4224,663168,1056,1056,2,2,600)
        check=0
        for byte in raw:check^=byte
        record=decode_packets(raw+bytes([check]))[0]
        self.assertEqual(record['vs_high_clocks'],4224)
        self.assertEqual(record['vs_period_clocks'],663168)
        self.assertEqual(record['de_rises'],600)

    def axi_dma_packet(self,flags=0x15,count=90000,heartbeat=7,phase=0xa5,base=0x87300000,frame_bytes=1440000):
        raw=b'TRV1'+struct.pack('<4B7I',4,flags,phase,0,count,0,0,base,frame_bytes,90000,heartbeat)
        check=0
        for byte in raw:check^=byte
        return raw+bytes([check])

    def test_axi_dma_has_distinct_qualified_raw_frame_result(self):
        records=decode_packets(self.axi_dma_packet(heartbeat=7)+self.axi_dma_packet(heartbeat=9))
        self.assertEqual(len(records),2)
        from read_board import qualify_axi_dma
        self.assertTrue(qualify_axi_dma(records))
        self.assertEqual(records[0]['test_base_bytes'],0x87300000)
        self.assertEqual(records[0]['frame_bytes'],1440000)
        self.assertFalse(qualify_ddr(records))
        self.assertFalse(qualify_axi_dma(decode_packets(self.ddr_packet(heartbeat=7)+self.ddr_packet(heartbeat=9))))

    def test_axi_dma_rejects_stale_short_error_and_wrong_allocation(self):
        from read_board import qualify_axi_dma
        self.assertFalse(qualify_axi_dma(decode_packets(self.axi_dma_packet()*2)))
        for kwargs in ({'flags':0x1d},{'flags':0x05},{'count':89999},{'phase':0xa4},
                       {'base':0x80000000},{'frame_bytes':1439999}):
            records=decode_packets(self.axi_dma_packet(heartbeat=7,**kwargs)+self.axi_dma_packet(heartbeat=9,**kwargs))
            self.assertFalse(qualify_axi_dma(records))

    def hdmi_capture_packet(self,**changes):
        fields=dict(flags=0x75,phase=0xa5,error_code=0,captured_pixels=480000,
                    checked_bytes=1440000,source_crc=0x8b43291a,ddr_crc=0x8b43291a,
                    frame_tag=1,fifo_peak=123,heartbeat=7)
        fields.update(changes)
        raw=b'TRV1'+struct.pack('<4B7I',5,*fields.values())
        checksum=0
        for byte in raw:checksum^=byte
        return raw+bytes([checksum])

    def test_hdmi_capture_requires_distinct_physical_input_result(self):
        from read_board import qualify_hdmi_capture
        records=decode_packets(self.hdmi_capture_packet(heartbeat=7)+self.hdmi_capture_packet(heartbeat=9))
        self.assertEqual(records[0]['captured_pixels'],480000)
        self.assertEqual(records[0]['source_crc'],0x8b43291a)
        self.assertTrue(records[0]['rx_mode_good'])
        self.assertTrue(qualify_hdmi_capture(records))
        self.assertFalse(qualify_hdmi_capture(records[:1]))
        self.assertFalse(qualify_hdmi_capture(decode_packets(self.axi_dma_packet(heartbeat=7)+self.axi_dma_packet(heartbeat=9))))

    def test_hdmi_capture_rejects_stale_partial_fault_crc_and_missing_fields(self):
        from read_board import qualify_hdmi_capture
        self.assertFalse(qualify_hdmi_capture(decode_packets(self.hdmi_capture_packet()*2)))
        bad=[{'flags':0x75^(1<<bit)} for bit in range(8)]
        bad += [{'phase':0xa4},{'error_code':1},{'captured_pixels':479999},
                {'checked_bytes':1439999},{'ddr_crc':0x8b43291b},{'frame_tag':2},
                {'fifo_peak':2049},{'fifo_peak':0}]
        for changes in bad:
            with self.subTest(changes=changes):
                records=decode_packets(self.hdmi_capture_packet(heartbeat=7,**changes)+self.hdmi_capture_packet(heartbeat=9,**changes))
                self.assertFalse(qualify_hdmi_capture(records))
        records=decode_packets(self.hdmi_capture_packet(heartbeat=7)+self.hdmi_capture_packet(heartbeat=9))
        for field in records[-1]:
            if field!='flags':
                missing=[dict(row) for row in records];missing[-1].pop(field)
                self.assertFalse(qualify_hdmi_capture(missing),field)

    def test_hdmi_capture_accepts_equal_zero_crc_and_maximum_ram_occupancy(self):
        from read_board import qualify_hdmi_capture
        records=decode_packets(self.hdmi_capture_packet(heartbeat=0xffffffff,source_crc=0,ddr_crc=0,fifo_peak=2048)+
                               self.hdmi_capture_packet(heartbeat=0,source_crc=0,ddr_crc=0,fifo_peak=2048))
        self.assertTrue(qualify_hdmi_capture(records))


if __name__=='__main__':unittest.main()

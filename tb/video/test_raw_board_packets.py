"""Raw scanout has an explicit packet kind and 600 rows per scan."""
import copy
from functools import reduce
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/video'))
import read_board

def packet(kind,values,heartbeat,flags=0x75,phase=0xa5,error=0):
    data=b'TRV1'+struct.pack('<4B7I',kind,flags,phase,error,*values,heartbeat)
    return data+bytes([reduce(int.__xor__,data,0)])

def records(display_kind=9,lines=600):
    data=b''
    for beat,scan in ((101,7),(110,9)):
        data+=packet(6,[480000,120000,0x12345678,0x12345678,0x23456789,0x23456789],beat)
        data+=packet(display_kind,[1,1,scan,0,lines*scan+1,222],beat+1)
        data+=packet(8,[1,1,76800,307200,307200,0x6a55c3e1],beat+2)
    return read_board.decode_packets(data)

class RawBoardPackets(unittest.TestCase):
    def test_type9_decoded_as_raw_display(self):
        rows=records()
        self.assertEqual(len(rows),6)
        self.assertEqual(rows[1]['type'],9)
        self.assertEqual(rows[1]['read_lines'],4201)

    def test_healthy_raw_three_branch_readback(self):
        self.assertTrue(read_board.qualify_raw_board(records()))
        self.assertFalse(read_board.qualify_three_readback(records()))
        self.assertFalse(read_board.qualify_preview_display(records()))

    def test_preview_or_incorrect_row_rate_rejected(self):
        self.assertFalse(read_board.qualify_raw_board(records(7)))
        for lines in (300,599,700,1200):
            self.assertFalse(read_board.qualify_raw_board(records(lines=lines)),lines)
        rows=records()
        rows[-2]['read_lines']=600*10+3
        self.assertFalse(read_board.qualify_raw_board(rows),'at most two rows prefetched beyond next scan')

    def test_missing_fields_faults_restarts_and_stale_samples_rejected(self):
        good=records()
        for index,row in enumerate(good):
            for field in row:
                rows=copy.deepcopy(good);rows[index].pop(field)
                self.assertFalse(read_board.qualify_raw_board(rows),(index,field))
        for kind in (6,7,8,9):
            for changes in ({'flags':0x7d,'error':3},{'flags':0x73,'phase':0x30}):
                self.assertFalse(read_board.qualify_raw_board(good+read_board.decode_packets(packet(kind,[0]*6,125,**changes))))
        for kind in (6,8,9):
            self.assertFalse(read_board.qualify_raw_board([row for row in good if row['type']!=kind]))
        for field,value in (('frame_id',2),('commits',2),('underflows',1),('completed_scans',7),('heartbeat',102)):
            rows=copy.deepcopy(good);rows[-2][field]=value
            self.assertFalse(read_board.qualify_raw_board(rows),field)
        rows=copy.deepcopy(good);rows[-1]['input_ddr_crc']^=1
        self.assertFalse(read_board.qualify_raw_board(rows))

    def test_raw_source_identity_must_remain_stable(self):
        rows=records()
        rows[-3]['source_crc']^=1;rows[-3]['ddr_crc']^=1
        self.assertFalse(read_board.qualify_raw_board(rows))

    def test_other_targets_and_heartbeat_rollback_invalidate_history(self):
        good=records()
        for kind in (2,4,5,7):
            self.assertFalse(read_board.qualify_raw_board(good+read_board.decode_packets(packet(kind,[0]*6,125,flags=0x7d,error=3))),kind)
        rows=copy.deepcopy(good)
        for i in range(3):rows[3+i]['heartbeat']=i+1
        self.assertFalse(read_board.qualify_raw_board(rows),'KEY0 heartbeat rollback')
        rows=copy.deepcopy(good)
        for i,row in enumerate(rows):row['heartbeat']=(0xfffffffd+i)&0xffffffff
        self.assertTrue(read_board.qualify_raw_board(rows),'natural heartbeat wrap')

if __name__=='__main__':unittest.main()

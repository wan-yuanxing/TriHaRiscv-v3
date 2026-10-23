"""Live qualification requires ongoing lifecycle progress, not a static PASS."""
import copy
from functools import reduce
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/video'))
import read_board

def packet(kind,values,hb,flags=0x77,error=0):
    data=b'TRV1'+struct.pack('<4B7I',kind,flags,0xa5,error,*values,hb)
    return data+bytes([reduce(int.__xor__,data,0)])

def records():
    data=b''
    for frame,hb in ((20,100),(50,106),(80,112)):
        data+=packet(12,[frame+1,123,200000,100000,30000,250],hb)
        data+=packet(9,[frame,frame,frame*2,0,frame*1200,250],hb+1)
        data+=packet(11,[frame,frame,frame,frame-1,frame*2,0],hb+2)
    return read_board.decode_packets(data)

class LivePackets(unittest.TestCase):
    def test_progress_and_decode(self):
        rows=records()
        self.assertEqual(len(rows),9)
        self.assertEqual(rows[0]['source_crc'],123)
        self.assertEqual(rows[-1]['captures'],80)
        self.assertTrue(read_board.qualify_live_board(rows))

    def test_static_or_invalid_ownership_is_rejected(self):
        for key,value in (('captures',50),('commits',50),('releases',0),('underflows',1),('frame_id',1)):
            rows=copy.deepcopy(records());rows[-1][key]=value
            self.assertFalse(read_board.qualify_live_board(rows),key)
        rows=records()
        for r in rows:
            if r['type']==11:r.update(frame_id=20,captures=20,commits=20,releases=19,completed_scans=40)
        self.assertFalse(read_board.qualify_live_board(rows))

    def test_restart_fault_and_old_target_invalidate_suffix(self):
        good=records()
        for kind,flags,error in ((11,0x73,0),(12,0x7f,3),(9,0x7f,6),(6,0x75,0)):
            self.assertFalse(read_board.qualify_live_board(good+read_board.decode_packets(packet(kind,[0]*6,120,flags,error))))
        rows=copy.deepcopy(good);rows[-1]['heartbeat']=2
        self.assertFalse(read_board.qualify_live_board(rows))

if __name__=='__main__':unittest.main()

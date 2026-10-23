"""A MODE sample must not qualify old or static continuous-video history."""
import copy
from functools import reduce
from pathlib import Path
import struct,sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/video'))
import read_board

def packet(kind,values,hb,flags=0x77,error=0):
    p=b'TRV1'+struct.pack('<4B7I',kind,flags,0xa5,error,*values,hb)
    return p+bytes([reduce(int.__xor__,p,0)])

def records(mode=0):
    data=b''
    for frame,hb in ((20,100),(140,108),(260,116)):
        data+=packet(12,[frame+1,123,480000,360000,307200,178],hb)
        data+=packet(9,[frame,frame,frame*2,0,frame*1200,178],hb+2)
        data+=packet(11,[frame,frame,frame,frame-1,frame*2,0],hb+4)
        data+=packet(10,[0x190|(mode<<2)|mode,3,3,3,4,0],hb+6)
    return read_board.decode_packets(data)

class LiveModePackets(unittest.TestCase):
    def test_all_modes_need_live_progress_and_settled_mode(self):
        for mode in range(3):
            self.assertTrue(read_board.qualify_live_mode_board(records(mode)))
            self.assertFalse(read_board.qualify_live_board(records(mode)))

    def test_fault_reset_pending_and_static_history_rejected(self):
        good=records()
        for changes in ({'mode_state':0x1b0},{'committed_seq':2},{'mode_state':0x195},{'error':True},{'overflow':True}):
            rows=copy.deepcopy(good);rows[-1].update(changes)
            self.assertFalse(read_board.qualify_live_mode_board(rows),changes)
        rows=copy.deepcopy(good)
        for r in rows:
            if r['type']==11:r.update(frame_id=20,captures=20,commits=20,releases=19,completed_scans=40)
        self.assertFalse(read_board.qualify_live_mode_board(rows))
        self.assertFalse(read_board.qualify_live_mode_board(good+[dict(good[-1],heartbeat=1)]))
        rows=copy.deepcopy(good);rows[-1]['heartbeat']=1
        self.assertFalse(read_board.qualify_live_mode_board(rows),'in-place MODE rollback')
        rows=copy.deepcopy(good)
        for r in rows:
            if r['type']==10:r['heartbeat']=1
        self.assertFalse(read_board.qualify_live_mode_board(rows),'stale MODE heartbeats')

    def test_missing_mode_and_late_extra_rotation_rejected(self):
        rows=records()
        self.assertFalse(read_board.qualify_live_mode_board([r for r in rows if r['type']!=10]))
        self.assertFalse(read_board.qualify_live_mode_board(rows+read_board.decode_packets(packet(11,[300,300,300,299,600,0],124))))

if __name__=='__main__':unittest.main()

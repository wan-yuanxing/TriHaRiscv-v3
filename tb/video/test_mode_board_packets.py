"""Four packet kinds must describe one healthy, actually committed MODE epoch."""
import copy
from functools import reduce
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/video'))
import read_board


def packet(kind,values,heartbeat,flags=0x75,phase=0xa5,error=0):
    raw=b'TRV1'+struct.pack('<4B7I',kind,flags,phase,error,*values,heartbeat)
    return raw+bytes([reduce(int.__xor__,raw,0)])


def records():
    raw=b''
    for beat,scan in ((101,7),(111,9)):
        raw+=packet(6,[480000,120000,0x12345678,0x12345678,0x23456789,0x23456789],beat)
        raw+=packet(9,[1,1,scan,0,600*scan+1,222],beat+1)
        raw+=packet(8,[1,1,76800,307200,307200,0x6a55c3e1],beat+2)
        raw+=packet(10,[0x19a,2,2,2,3,0],beat+3)
    return read_board.decode_packets(raw)


class ModeBoardPackets(unittest.TestCase):
    def test_decode_mode_packet(self):
        rows=records()
        self.assertEqual(len(rows),8)
        self.assertEqual(rows[-1]['type'],10)
        self.assertEqual(rows[-1]['mode_state'],0x19a)
        self.assertEqual(rows[-1]['requested_mode'],2)
        self.assertEqual(rows[-1]['active_mode'],2)
        self.assertEqual(rows[-1]['request_seq'],2)
        self.assertEqual(rows[-1]['committed_seq'],2)
        self.assertEqual(rows[-1]['commit_count'],3)

    def test_healthy_committed_mode_four_kind_epoch(self):
        self.assertTrue(read_board.qualify_mode_board(records()))
        self.assertFalse(read_board.qualify_raw_board(records()))
        self.assertFalse(read_board.qualify_preview_display(records()))

    def test_pending_unavailable_material_and_overlay_faults_rejected(self):
        for bit in (5,6,9,10,11,13,14,15,16):
            rows=records();rows[-1]['mode_state']|=1<<bit
            self.assertFalse(read_board.qualify_mode_board(rows),bit)
        for bit in (4,7,8):
            rows=records();rows[-1]['mode_state']&=~(1<<bit)
            self.assertFalse(read_board.qualify_mode_board(rows),bit)
        for value in (0x19b,0x19e,True,-1,1<<32):
            rows=records();rows[-1]['mode_state']=value
            self.assertFalse(read_board.qualify_mode_board(rows),value)

    def test_require_two_complete_stable_observations(self):
        good=records()
        for kind in (6,8,9,10):
            rows=copy.deepcopy(good);rows.pop(next(i for i,r in enumerate(rows) if r['type']==kind))
            self.assertFalse(read_board.qualify_mode_board(rows),kind)
        for field in ('mode_state','request_seq','committed_seq','request_count','commit_count','coalesced_count'):
            rows=records();rows[-1].pop(field)
            self.assertFalse(read_board.qualify_mode_board(rows),field)
            rows=records();rows[-1][field]=True
            self.assertFalse(read_board.qualify_mode_board(rows),(field,'bool'))
            rows=records();rows[-1][field]^=1
            self.assertFalse(read_board.qualify_mode_board(rows),(field,'changed'))
        rows=records();rows[-1]['mode_state']|=1<<12
        self.assertTrue(read_board.qualify_mode_board(rows),'held button alone is not a fault')

    def test_latest_error_or_restart_invalidates_older_success(self):
        good=records()
        for kind in (6,8,9,10,2,7):
            for kwargs in ({'flags':0x7d,'error':3},{'flags':0x73,'phase':0x30}):
                rows=good+read_board.decode_packets(packet(kind,[0]*6,125,**kwargs))
                self.assertFalse(read_board.qualify_mode_board(rows),(kind,kwargs))
        rows=records()
        for i,row in enumerate(rows[4:]):row['heartbeat']=i+1
        self.assertFalse(read_board.qualify_mode_board(rows),'KEY0 restart')

    def test_mode_record_cannot_hide_input_or_raw_fault(self):
        for index,field,value in ((5,'underflows',1),(5,'commits',2),(5,'frame_id',2),
                                  (6,'input_ddr_crc',123),(4,'source_crc',123)):
            rows=records();rows[index][field]=value
            self.assertFalse(read_board.qualify_mode_board(rows),field)

    def test_mode_packet_starts_a_distinct_target_epoch(self):
        from test_three_board_packets import records as old_preview_records
        rows=old_preview_records()
        self.assertTrue(read_board.qualify_three_readback(rows))
        rows+=read_board.decode_packets(packet(10,[0]*6,125,flags=0x73,phase=0x30))
        self.assertFalse(read_board.qualify_three_readback(rows))
        self.assertFalse(read_board.qualify_preview_display(rows))

    def test_raw_only_target_cannot_inherit_old_mode_success(self):
        tail=[dict(r,heartbeat=r['heartbeat']+40) for r in records() if r['type']!=10]
        rows=records()+tail
        self.assertTrue(read_board.qualify_raw_board(rows))
        self.assertFalse(read_board.qualify_mode_board(rows))

    def test_latest_mode_cycle_allows_only_one_ordered_partial_rotation(self):
        tail=[dict(r,heartbeat=r['heartbeat']+40) for r in records()[:3]]
        tail[1].update(completed_scans=11,read_lines=6601)
        for length in range(4):
            self.assertTrue(read_board.qualify_mode_board(records()+tail[:length]),length)
        wrong=[dict(tail[1],heartbeat=141),dict(tail[0],heartbeat=142)]
        self.assertFalse(read_board.qualify_mode_board(records()+wrong))

    def test_natural_counter_wrap_is_not_a_reset(self):
        rows=records()
        for i,row in enumerate(rows):row['heartbeat']=(0xfffffffc+i)&0xffffffff
        for row in rows:
            if row['type']==10:
                row.update(request_seq=0xffffffff,committed_seq=0xffffffff,request_count=0xffffffff,commit_count=0)
        self.assertTrue(read_board.qualify_mode_board(rows))


if __name__=='__main__':unittest.main()

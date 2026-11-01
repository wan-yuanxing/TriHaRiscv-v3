"""Host THB1 wire format and cursor/ACK validation, no serial hardware."""
import struct
import unittest
import zlib
from upload_face_model import make_packet, parse_ack, upload_segments


def ack(segment,offset,status=0):
    return b'THA1'+bytes([status,segment,0,0])+struct.pack('<I',offset)


class Port:
    def __init__(self,replies):self.replies=list(replies);self.writes=[];self.pending=bytearray()
    def write(self,data):
        self.writes.append(data);self.pending.extend(self.replies.pop(0));return len(data)
    def flush(self):pass
    def read(self,n):
        value=self.pending[:n];del self.pending[:n];return bytes(value)


class UploadTests(unittest.TestCase):
    def test_packet(self):
        payload=bytes(range(256));packet=make_packet(2,256,payload)
        self.assertEqual(packet[:16],b'THB1'+struct.pack('<III',2,256,zlib.crc32(payload)))
        self.assertEqual(packet[16:],payload)
        for segment,offset,data in [(6,0,payload),(0,1,payload),(0,0,payload[:255])]:
            with self.assertRaises(ValueError):make_packet(segment,offset,data)

    def test_ack(self):
        self.assertEqual(parse_ack(ack(6,0)),(0,6,0))
        for data in [b'',b'BAD!'+ack(1,0)[4:],ack(1,0)[:6]+b'\x01\x00'+ack(1,0)[8:],ack(7,0)]:
            with self.assertRaises(ValueError):parse_ack(data)

    def test_sequence_and_crc_retry(self):
        segments=[bytes([i])*512 for i in range(6)]
        replies=[]
        for i in range(6):replies.extend([ack(i,256),ack(i+1,0)])
        replies.insert(0,ack(0,0,1))
        port=Port(replies)
        result=upload_segments(port,segments,timeout=.01,retries=2)
        self.assertEqual(result,{'bytes':3072,'packets':12,'retries':1,'ack_segment':6,'ack_offset':0})
        self.assertEqual(port.writes[0],port.writes[1])

    def test_lost_ack_retry(self):
        port=Port([b'']+[ack(i+1,0) for i in range(6)])
        result=upload_segments(port,[bytes(256)]*6,timeout=.001,retries=1)
        self.assertEqual(result['retries'],1)
        self.assertEqual(port.writes[0],port.writes[1])

    def test_bad_cursor_and_fault(self):
        for reply in [ack(1,256),ack(0,0,4),ack(0,0,3),ack(0,0,2)]:
            with self.assertRaises(RuntimeError):
                upload_segments(Port([reply]),[bytes(256)]*6,timeout=.001,retries=0)

    def test_partial_reply_and_stale_ack(self):
        # A duplicate previous ACK may be in flight after a retry. It cannot
        # advance the next packet; the exact expected cursor is still required.
        port=Port([ack(1,0),ack(1,0)+ack(2,0)]+[ack(i+1,0) for i in range(2,6)])
        self.assertEqual(upload_segments(port,[bytes(256)]*6,timeout=.01)['packets'],6)


if __name__=='__main__':unittest.main()

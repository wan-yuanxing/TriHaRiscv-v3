import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'scripts/video'))
from input_format_reference import pad_bgr, pack_c8


class InputFormatReferenceTests(unittest.TestCase):
    def test_order_and_padding(self):
        self.assertEqual(pad_bgr(bytes((1,2,3,254,127,128)),2,1,2),
                         bytes((3,2,1,128,127,254))+bytes(6))

    def test_every_byte_and_nonzero_zero(self):
        for zero in (0,128,55):
            source=bytes(v for b in range(256) for v in (b,255-b,b^128))
            data=source+bytes((zero,))*256*3
            actual=pack_c8(data,256,1,2,zero)
            expected=b''.join(bytes((b,255-b,b^128))+bytes((zero,))*5 for b in range(256))
            expected+=bytes((zero,))*256*8
            self.assertEqual(actual,expected)

    def test_default_shape(self):
        raw=pad_bgr(bytes((0x11,0x22,0x33))*160*120)
        self.assertEqual(len(raw),160*128*3)
        self.assertEqual(raw[:3],bytes((0x33,0x22,0x11)))
        tensor=pack_c8(raw,160,120,128,0)
        self.assertEqual(len(tensor),163840)
        self.assertEqual(tensor[:8],bytes((0x33,0x22,0x11,0,0,0,0,0)))
        self.assertEqual(tensor[160*120*8:],bytes(160*8*8))

    def test_reject_invalid(self):
        for dims in ((0,1,1),(1,0,1),(1,2,1),(2049,1,1),(1,1,2049),(True,1,1)):
            with self.assertRaises(ValueError):pad_bgr(b'',*dims)
        for data in (b'',bytes(2),bytes(4),bytearray(3),None):
            with self.assertRaises(ValueError):pad_bgr(data,1,1,1)
        for zero in (-1,256,True,1.0):
            with self.assertRaises(ValueError):pack_c8(bytes(3),1,1,1,zero)
        with self.assertRaises(ValueError):pack_c8(bytes((1,2,3,0,0,0)),1,1,2,128)
        self.assertEqual(pack_c8(bytes((128,255,127)),1,1,1,55),bytes((128,255,127,55,55,55,55,55)))


if __name__=='__main__':unittest.main()

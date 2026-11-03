"""Ensure replay comparison never ignores configuration or identity changes."""
from pathlib import Path
import unittest
from restore_face_release import compare_pango_bytes


class ReplayComparisonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bit = (Path(__file__).resolve().parents[2] /
                   'releases/face-box-20261103/triha_face_board_top.sbit').read_bytes()

    def test_identical(self):
        self.assertTrue(compare_pango_bytes(self.bit, self.bit)['byte_identical'])

    def test_valid_time_only(self):
        changed = self.bit.replace(b'11/03/26\0', b'11/04/26\0', 1)
        changed = changed.replace(b'19:21:21\0', b'20:22:22\0', 1)
        result = compare_pango_bytes(self.bit, changed)
        self.assertTrue(result['configuration_identical'])
        self.assertFalse(result['byte_identical'])

    def test_invalid_time(self):
        with self.assertRaises(ValueError):
            compare_pango_bytes(self.bit, self.bit.replace(b'19:21:21\0', b'99:22:22\0', 1))

    def test_configuration_change(self):
        changed = bytearray(self.bit)
        changed[-100] ^= 1
        with self.assertRaises(ValueError):
            compare_pango_bytes(self.bit, bytes(changed))

    def test_device_identity_change(self):
        with self.assertRaises(ValueError):
            compare_pango_bytes(self.bit, self.bit.replace(b'PG2L100H', b'PG2L200H', 1))

    def test_truncated(self):
        with self.assertRaises(ValueError):
            compare_pango_bytes(self.bit, self.bit[:-1])


if __name__ == '__main__':
    unittest.main()

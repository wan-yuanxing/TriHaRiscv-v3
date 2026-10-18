"""Fixed-ratio reference checked against independently generated OpenCV 4.11 hashes."""
import hashlib
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts/video'))
from yunet_input_reference import preprocess_rgb800x600


class YuNetInputReferenceTests(unittest.TestCase):
    def test_invalid_input(self):
        for value in (None, '', bytearray(1440000), memoryview(bytes(1440000)),
                      b'', bytes(1439999), bytes(1440001)):
            with self.subTest(value_type=type(value).__name__, length=len(value) if value is not None else None):
                with self.assertRaises(ValueError):
                    preprocess_rgb800x600(value)

    def test_black(self):
        output = preprocess_rgb800x600(bytes(1440000))
        self.assertEqual(output, bytes(307200))
        self.assertEqual(hashlib.sha256(output).hexdigest(),
                         '7818f5542a0404157573be6cffc0e0c8e68ce3c0f5d17d07ccdd9313fb700baf')

    def test_full255_and_padding(self):
        output = preprocess_rgb800x600(bytes([255])*1440000)
        expected_plane = bytes(12800) + bytes([255])*76800 + bytes(12800)
        self.assertEqual(output, expected_plane*3)
        self.assertEqual(hashlib.sha256(output).hexdigest(),
                         '321dc1636cabdb68b9477a4bbe9f4e8e91183d1eccce293270f30dacfac8d6cd')

    def test_BGR_planes_and_unsigned_values(self):
        output = preprocess_rgb800x600(bytes((211, 93, 17))*480000)
        self.assertIsInstance(output, bytes)
        self.assertEqual(len(output), 307200)
        for channel, value in enumerate((17, 93, 211)):
            plane = output[channel*102400:(channel+1)*102400]
            self.assertEqual(plane, bytes(12800) + bytes([value])*76800 + bytes(12800))
        self.assertEqual(hashlib.sha256(output).hexdigest(),
                         '95c97819b1991ae6335d50fa9a643fe486db9dbecbe533978802c8c931103120')

    def test_coordinate_patterns_match_frozen_opencv411(self):
        cases = ((0, '959f1f661aaccc3194e33a9b2916e87d477a6fe752287f004324977016733c09'),
                 (1, 'bbf02f21a96ed72720741a212def1ba27aaa0908cff1aa1024695d44b3e483b7'),
                 (7, 'f614cb89ede163e40624bbf116eefc0ea4540decfb7556f63780732c6f599f07'))
        for seed, expected in cases:
            with self.subTest(seed=seed):
                rgb = bytes((37*x+19*y+83*c+((x*y)>>3)+seed*(7*(x%7)+13*(y%11)+29*c)) % 256
                            for y in range(600) for x in range(800) for c in range(3))
                output = preprocess_rgb800x600(rgb)
                self.assertEqual(hashlib.sha256(output).hexdigest(), expected)

    def test_last_source_corner_contributes(self):
        rgb = bytearray(1440000)
        rgb[-3:] = bytes((240, 128, 16))
        output = preprocess_rgb800x600(bytes(rgb))
        # Last source pixel has 1/4 weight on both axes. All other selected
        # pixels are zero; the final valid destination is row279/column319.
        index = 279*320+319
        for channel, expected in enumerate((1, 8, 15)):
            plane = output[channel*102400:(channel+1)*102400]
            wanted = bytearray(102400)
            wanted[index] = expected
            self.assertEqual(plane, bytes(wanted))


if __name__ == '__main__':
    unittest.main()

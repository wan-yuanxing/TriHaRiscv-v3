"""Independent coordinate/rounding checks for the geometry-only reference."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts/video'))
from detect_reference import downscale_rgb


class DetectReferenceTests(unittest.TestCase):
    def test_every_sum(self):
        for total in range(6376):
            values = [min(255, max(0, total - 255 * n)) for n in range(25)]
            image = bytes(v for n in values for v in (n, 255-n, n))
            actual = downscale_rgb(image, 5, 5)
            # Nearest integer, with odd divisor 25: remainder >=13 rounds up.
            q, r = divmod(total, 25)
            inverse_q, inverse_r = divmod(6375-total, 25)
            self.assertEqual(actual, bytes((q+(r>=13), inverse_q+(inverse_r>=13), q+(r>=13))))

    def test_full_frame_block_placement(self):
        image = bytes(c for y in range(600) for x in range(800)
                      for c in ((x//5)%256, (y//5)%256, (x//5+y//5)%256))
        actual = downscale_rgb(image)
        expected = bytes(c for y in range(120) for x in range(160)
                         for c in (x, y, (x+y)%256))
        self.assertEqual(actual, expected)

    def test_all_source_coordinates_contribute(self):
        for index in range(25):
            image = bytearray(75)
            image[index*3:index*3+3] = bytes((255, 125, 25))
            self.assertEqual(downscale_rgb(bytes(image), 5, 5), bytes((10, 5, 1)))

    def test_reject_geometry_and_payload(self):
        for width, height in ((0,5),(5,0),(4,5),(5,6),(2050,5),(True,5),(5.0,5)):
            with self.assertRaises(ValueError):downscale_rgb(b'',width,height)
        for image in (b'', bytes(74), bytes(76), bytearray(75), None):
            with self.assertRaises(ValueError):downscale_rgb(image,5,5)


if __name__ == '__main__':unittest.main()

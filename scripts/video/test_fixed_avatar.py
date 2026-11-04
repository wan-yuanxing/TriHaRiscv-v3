"""Preview compression may vary; runtime bytes and visible pixels may not."""
import io
from pathlib import Path
import tempfile
import unittest
from PIL import Image
from gen_fixed_avatar import verify_products


class FixedAvatarTests(unittest.TestCase):
    def test_png_encoding_only(self):
        with tempfile.TemporaryDirectory() as d:
            im = Image.new('RGBA', (2, 2), (10, 20, 30, 40))
            expected = io.BytesIO(); im.save(expected, format='PNG', compress_level=9)
            p = Path(d)/'avatar.png'; im.save(p, format='PNG', compress_level=0)
            self.assertNotEqual(p.read_bytes(), expected.getvalue())
            verify_products({p:expected.getvalue()})
            im.putpixel((0, 0), (10, 20, 30, 41)); im.save(p)
            with self.assertRaises(ValueError): verify_products({p:expected.getvalue()})

    def test_runtime_byte_change_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)/'avatar.rgba'; p.write_bytes(b'\x01\x02\x03\xff')
            verify_products({p:b'\x01\x02\x03\xff'})
            with self.assertRaises(ValueError): verify_products({p:b'\x01\x02\x04\xff'})


if __name__ == '__main__': unittest.main()

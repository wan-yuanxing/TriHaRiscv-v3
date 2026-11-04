"""Build a self-contained HDMI input page from the admitted 800x600 RGB fixture."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[2]
W, H = 800, 600
EXPECTED = '72e4f23b5f9d4bf71ccbdec4f2bc0ef1e5f5981481f5d91a5eef5d81e4dfc31e'


def png(rgb):
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data))
    rows = b''.join(b'\0' + rgb[i:i+3*W] for i in range(0, len(rgb), 3*W))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--fixture', type=Path, required=True)
    ap.add_argument('--output', type=Path, default=ROOT/'build/video/face-hdmi-source.html')
    args = ap.parse_args()
    ref = json.loads((args.fixture/'reference.json').read_text(encoding='utf-8'))
    rgb = (args.fixture/'frame_rgb.bin').read_bytes()
    if not (len(rgb) == W*H*3 and hashlib.sha256(rgb).hexdigest() == EXPECTED ==
            ref['files']['frame_rgb.bin'] and ref['status'] == 'PASS_HOST_REFERENCE' and ref['faces'] == 1):
        raise ValueError('Not the admitted 800x600 positive fixture')
    template = Path(__file__).with_name('face_hdmi_source.html').read_text(encoding='utf-8')
    if template.count('@@FRAME_PNG@@') != 1:
        raise ValueError('Missing unique fixture image placeholder')
    html = template.replace('@@FRAME_PNG@@', base64.b64encode(png(rgb)).decode('ascii'))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x', encoding='utf-8', newline='\n') as file:
        file.write(html)
    print('HDMI_INPUT_ONLY', args.output.resolve())


if __name__ == '__main__':
    main()

"""Match active RGB RTL dumps to the frozen OpenCV 4.11 BGR NCHW identities."""
import argparse
import hashlib
from pathlib import Path
import re

GOLDENS = (
    '7818f5542a0404157573be6cffc0e0c8e68ce3c0f5d17d07ccdd9313fb700baf',
    '321dc1636cabdb68b9477a4bbe9f4e8e91183d1eccce293270f30dacfac8d6cd',
    '95c97819b1991ae6335d50fa9a643fe486db9dbecbe533978802c8c931103120',
    '959f1f661aaccc3194e33a9b2916e87d477a6fe752287f004324977016733c09',
    'bbf02f21a96ed72720741a212def1ba27aaa0908cff1aa1024695d44b3e483b7',
    'f614cb89ede163e40624bbf116eefc0ea4540decfb7556f63780732c6f599f07',
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', type=Path, required=True)
    args = parser.parse_args()
    for tag, expected in enumerate(GOLDENS):
        path = Path(str(args.prefix) + f'_{tag}.hex')
        rows = path.read_text(encoding='utf-8').splitlines()
        if len(rows) != 76800 or any(re.fullmatch('[0-9a-fA-F]{6}', row) is None for row in rows):
            raise ValueError(f'Invalid active RGB dump: {path}')
        tensor = bytearray(307200)
        for index, row in enumerate(rows):
            rgb = bytes.fromhex(row)
            y, x = divmod(index, 320)
            for channel in range(3):
                tensor[channel*102400+(y+40)*320+x] = rgb[2-channel]
        actual = hashlib.sha256(tensor).hexdigest()
        if actual != expected:
            raise ValueError(f'OpenCV 4.11 golden mismatch tag={tag}: {actual} != {expected}')
        print(f'DETECT_BILINEAR_GOLDEN_PASS tag={tag} bytes={len(tensor)} sha256={actual}')
    print('DETECT_BILINEAR_DUMP_PASS frames=6 tensor_bytes=1843200')


if __name__ == '__main__':
    main()

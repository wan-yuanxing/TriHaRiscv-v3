"""Check actual hardware-written BGR NCHW bytes, without repacking in software."""
import argparse
import hashlib
from pathlib import Path
import re

from check_bilinear_dump import GOLDENS


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', type=Path, required=True)
    args = parser.parse_args()
    for tag, expected in enumerate(GOLDENS):
        path = Path(str(args.prefix) + f'_{tag}.hex')
        rows = path.read_text(encoding='utf-8').splitlines()
        if len(rows) != 307200 or any(re.fullmatch('[0-9a-fA-F]{2}', row) is None for row in rows):
            raise ValueError(f'Invalid hardware NCHW dump: {path}')
        tensor = bytes(int(row, 16) for row in rows)
        actual = hashlib.sha256(tensor).hexdigest()
        if actual != expected:
            raise ValueError(f'Hardware NCHW golden mismatch tag={tag}: {actual} != {expected}')
        print(f'DETECT_NCHW_GOLDEN_PASS tag={tag} bytes={len(tensor)} sha256={actual}')
    print('DETECT_NCHW_DUMP_PASS frames=6 bytes=1843200')


if __name__ == '__main__':
    main()

"""Check the actual NCHW memory of the same-frame three-branch capture."""
import argparse
import hashlib
from pathlib import Path
import re

from check_bilinear_dump import GOLDENS


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--path', required=True, type=Path)
    args = parser.parse_args()
    rows = args.path.read_text(encoding='utf-8').splitlines()
    if len(rows) != 307200 or any(re.fullmatch('[0-9a-fA-F]{2}', row) is None for row in rows):
        raise ValueError('Invalid three-branch hardware input dump')
    digest = hashlib.sha256(bytes(int(row, 16) for row in rows)).hexdigest()
    if digest != GOLDENS[3]:
        raise ValueError(f'Three-branch OpenCV golden mismatch: {digest}')
    print(f'THREE_CAPTURE_DUMP_PASS bytes=307200 sha256={digest}')


if __name__ == '__main__':
    main()

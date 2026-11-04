"""Verify the four original CoreMark images offline. No hardware operations."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ACCEPTED = {
    '02_coremark_single_sram': '6a7329d7354c05cac9b8e6637337b10d8ace6def5218dd18edf2ddd3b5e8a36f',
    '03_coremark_single_cache': '478149ee9e631ca60590c5d8b8d63c1a245924823613b98f3c59a5530554f561',
    '04_coremark_dual_sram': '4a39323615353feb6baf2a125e9d7fb693a85498c6a45ed25e0963d89dd4eea7',
    '05_coremark_dual_cache': '77da07f738ce309fc937fc2580e8434f3a08765169d8ffb150dfbeb36c319cdd',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def verify():
    inventory = json.loads((ROOT / 'inventory.json').read_text(encoding='utf-8'))['files']
    for name, entry in inventory.items():
        p = (ROOT / name).resolve()
        require(p.is_relative_to(ROOT), 'Path outside package')
        require(p.is_file(), 'Missing file: ' + name)
        require(p.stat().st_size == entry['bytes'], 'Size mismatch: ' + name)
        require(sha(p) == entry['sha256'], 'SHA256 mismatch: ' + name)
    m = json.loads((ROOT / 'manifest.json').read_text(encoding='utf-8'))
    require({i['id'] for i in m['images']} == set(ACCEPTED), 'Wrong image set')
    for i in m['images']:
        bit = ROOT / i['bitstream']['path']
        require(sha(bit) == ACCEPTED[i['id']], 'Original board-tested bitstream differs')
        require(b'Logos2-PG2L100H--6-FBG676\x00' in bit.read_bytes()[:256], 'Wrong device header')
        require(sha(ROOT / i['verify_mask']['path']) == i['verify_mask']['sha256'], 'Wrong verification mask')
        for profile in ['EF4018_W25Q128Q_x1', 'EF7018_W25Q128M_x1']:
            require(sha(ROOT / 'flash' / profile / (i['id'] + '.sfc')) == ACCEPTED[i['id']], 'SFC differs from native conversion')
    result = {'status': 'PASS_FOUR_ORIGINAL_IMAGES_OFFLINE', 'images': 4,
              'files_verified': len(inventory), 'hardware_accessed': False,
              'flash_written': False, 'button_switch_implemented': False}
    print(json.dumps(result, indent=2))
    return m


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', nargs='?', default='verify', choices=['verify', 'list'])
    args = parser.parse_args()
    try:
        m = verify()
        if args.action == 'list':
            for i in m['images']:
                print(i['id'], i['score_per_mhz'], i['bitstream']['path'])
        return 0
    except Exception as error:
        print('FAIL:', error)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())

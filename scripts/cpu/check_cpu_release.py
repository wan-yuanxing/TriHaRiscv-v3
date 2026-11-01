"""Verify canonical release source bytes, including staged Git blobs before push."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true')
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'docs/verification/cpu/cpu_branch_source_manifest_20261101.json').read_text(encoding='utf-8'))
    files = {}
    for group in ('canonical_core_sources', 'canonical_board_route_inputs', 'canonical_coremark_inputs'):
        for name, digest in manifest[group].items():
            if name in files and files[name] != digest:
                raise ValueError('Conflicting source identity: ' + name)
            files[name] = digest
    for name, digest in files.items():
        path = Path(name)
        if path.is_absolute() or '..' in path.parts or ':' in name:
            raise ValueError('Unsafe source path: ' + name)
        data = subprocess.check_output(['git', 'show', ':' + name], cwd=ROOT) if args.staged else (ROOT / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError('Release source hash mismatch: ' + name)
    print('CPU_RELEASE_SOURCE_PASS files=' + str(len(files)) + ' staged=' + str(args.staged))


if __name__ == '__main__':
    main()

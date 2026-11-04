"""Import a reviewed CPU source manifest without overwriting existing edits.

Git is used only during explicit source acquisition. Simulation consumes the
admitted local files and never needs the source checkout or its Git history.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from source_header_cleanup import replay_cleanup

ROOT = Path(__file__).resolve().parents[2]
PRODUCTION_DELTAS = {'rtl/cpu/triha_csr.v', 'rtl/cpu/ADAPTATIONS.json', 'rtl/cpu/triha_core.v'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(root, name):
    if not isinstance(name, str) or not name or '\\' in name or ':' in name:
        raise ValueError('unsafe path: ' + repr(name))
    path = PurePosixPath(name)
    if path.is_absolute() or name != path.as_posix() or any(
            part in ('.', '..') or part.endswith((' ', '.')) or
            re.fullmatch(r'(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?', part, re.I)
            for part in path.parts):
        raise ValueError('unsafe path: ' + name)
    resolved = (root / name).resolve()
    if not resolved.is_relative_to(root.resolve()):
        raise ValueError('unsafe path escapes root: ' + name)
    return resolved


def import_sources(source, destination, manifest, apply=False):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    revision = manifest.get('source_commit', '')
    if manifest.get('schema_version') != 1 or not re.fullmatch('[0-9a-f]{40}', revision):
        raise ValueError('manifest requires schema 1 and immutable source commit')
    files = manifest.get('files', [])
    if not files:
        raise ValueError('manifest has no sources')
    names = set()
    planned = []
    # Complete validation before the first write. A later conflict must not
    # leave an earlier source partially admitted.
    for row in files:
        original = safe_path(source, row['source'])
        target = safe_path(destination, row['destination'])
        identity = str(target).casefold()
        if identity in names:
            raise ValueError('duplicate destination: ' + row['destination'])
        names.add(identity)
        kind = row.get('source_kind', 'git')
        if not re.fullmatch('[0-9a-f]{64}', row.get('sha256', '')):
            raise ValueError('invalid SHA-256: ' + row['source'])
        if kind == 'git':
            data = subprocess.check_output(['git', '-C', str(source), 'cat-file',
                                            'blob', revision + ':' + row['source']])
        elif kind == 'reviewed_working_tree':
            production = (row['source'].casefold().startswith('rtl/') or
                          row['destination'].casefold().startswith('rtl/'))
            if production and (row['source'] not in PRODUCTION_DELTAS or
                               row['source'] != row['destination']):
                raise ValueError('unapproved production delta: ' + row['source'])
            if production:
                base = subprocess.check_output(['git', '-C', str(source), 'cat-file',
                                               'blob', revision + ':' + row['source']])
                if digest(base) != row.get('base_sha256'):
                    raise ValueError('base hash mismatch: ' + row['source'])
            data = original.read_bytes()
        else:
            raise ValueError('unknown source kind: ' + str(kind))
        if 'header_comment_cleanup' in row:
            data = replay_cleanup(data, row['header_comment_cleanup'], row['sha256'])
        if digest(data) != row['sha256']:
            raise ValueError('source hash mismatch: ' + row['source'])
        if target.exists() and (not target.is_file() or target.read_bytes() != data):
            raise ValueError('destination conflict: ' + row['destination'])
        planned.append((target, data, row))
    for target, data, row in planned:
        if apply and not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            # Exclusive creation also protects a file created after preflight.
            with target.open('xb') as stream:
                stream.write(data)
    return {'status': 'PASS', 'applied': apply, 'source_commit': revision,
            'files': [{'source': row['source'], 'destination': row['destination'],
                       'sha256': digest(data)} for target, data, row in planned]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--destination-root', type=Path, default=ROOT)
    parser.add_argument('--manifest', type=Path, default=ROOT / 'config/cpu_admission.json')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    try:
        result = import_sources(args.source_root, args.destination_root,
                                json.loads(args.manifest.read_text(encoding='utf-8-sig')), args.apply)
        print(json.dumps(result, indent=2))
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print('CPU_IMPORT_FAIL ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

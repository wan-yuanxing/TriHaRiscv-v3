"""Verify/install the frozen face BOX release without accessing the board."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RELEASE = ROOT / 'releases/face-box-20261103'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def compare_pango_bytes(reference, regenerated):
    """Allow only parsed date/time fields to vary; compare every other byte."""
    prefix = b'\x00\x09\x0f\xf0\x0f\xf0\x0f\xf0\x0f\xf0\x00PANGO MICROSYSTEMS, INC.\x00\x01'
    if not reference.startswith(prefix) or not regenerated.startswith(prefix):
        raise ValueError('Unrecognized Pango header')
    if len(reference) != len(regenerated):
        raise ValueError('Regenerated file size differs')
    offset = len(prefix)
    normalized = bytearray(regenerated)
    times = {}
    for tag in b'abcdef':
        if offset + 3 > len(reference):
            raise ValueError('Truncated Pango header')
        if reference[offset] != tag or regenerated[offset] != tag:
            raise ValueError('Pango header tag differs')
        size = int.from_bytes(reference[offset+1:offset+3], 'big')
        if size < 1 or reference[offset+1:offset+3] != regenerated[offset+1:offset+3]:
            raise ValueError('Pango header field size differs')
        start, end = offset+3, offset+3+size
        if end > len(reference) or reference[end-1] != 0 or regenerated[end-1] != 0:
            raise ValueError('Invalid Pango header termination')
        if tag in b'cd':
            if size != 9:
                raise ValueError('Unexpected Pango timestamp length')
            before = reference[start:end-1].decode('ascii')
            after = regenerated[start:end-1].decode('ascii')
            fmt = '%m/%d/%y' if tag == ord('c') else '%H:%M:%S'
            datetime.strptime(before, fmt)
            datetime.strptime(after, fmt)
            times[chr(tag)] = dict(reference=before, regenerated=after)
            normalized[start:end] = reference[start:end]
        offset = end
    if bytes(normalized) != reference:
        raise ValueError('Configuration or non-time header bytes differ')
    return dict(byte_identical=reference == regenerated, configuration_identical=True,
                timestamp_fields=times, comparison_sha256=hashlib.sha256(normalized).hexdigest())


def safe_path(root, name, build_only=False):
    p = PurePosixPath(name)
    if (not name or '\\' in name or ':' in name or p.is_absolute()
            or any(x in ('', '.', '..') for x in name.split('/'))
            or (build_only and p.parts[0] != 'build')):
        raise ValueError('Unsafe release path: ' + name)
    target = root.joinpath(*p.parts)
    if not target.resolve().is_relative_to(root.resolve()):
        raise ValueError('Release path escapes destination: ' + name)
    return target


def verify(release, root):
    manifest = json.loads((release / 'manifest.json').read_text(encoding='utf-8'))
    if manifest['schema_version'] != 1:
        raise ValueError('Unsupported release manifest')
    for name, expected in manifest['files'].items():
        path = safe_path(release, name)
        if path.stat().st_size != expected['bytes'] or digest(path) != expected['sha256']:
            raise ValueError('Release file changed: ' + name)
    for name, expected in manifest['source_sha256'].items():
        if digest(safe_path(root, name)) != expected:
            raise ValueError('Source differs from qualified release: ' + name)
    seen = set()
    for archive in manifest['archives']:
        with zipfile.ZipFile(safe_path(release, archive)) as zipped:
            names = zipped.namelist()
            if len(names) != len(set(names)) or seen.intersection(names):
                raise ValueError('Duplicate archive members')
            for name in names:
                expected = manifest['archive_members'][name]
                safe_path(root, name, build_only=True)
                info = zipped.getinfo(name)
                if info.is_dir() or (info.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError('Non-regular archive member: ' + name)
                with zipped.open(name) as stream:
                    actual = hashlib.file_digest(stream, 'sha256').hexdigest()
                if info.file_size != expected['bytes'] or actual != expected['sha256']:
                    raise ValueError('Archive content changed: ' + name)
            seen.update(names)
    if seen != set(manifest['archive_members']):
        raise ValueError('Archive member list differs')
    return manifest


def install(release, root, manifest):
    # Check every existing destination before writing any payload. Different
    # local builds are never silently replaced by this historical release.
    destinations = dict(manifest['archive_members'])
    for name, target in manifest['direct_restore'].items():
        destinations[target] = manifest['files'][name]
    for name, expected in destinations.items():
        path = safe_path(root, name, build_only=True)
        if path.exists() and (not path.is_file() or digest(path) != expected['sha256']):
            raise ValueError('Existing different file; use a clean checkout: ' + name)
    for archive in manifest['archives']:
        with zipfile.ZipFile(release / archive) as zipped:
            for name in zipped.namelist():
                path = safe_path(root, name, build_only=True)
                if not path.exists():
                    path.parent.mkdir(parents=True, exist_ok=True)
                    with zipped.open(name) as source, path.open('xb') as dest:
                        shutil.copyfileobj(source, dest)
    for name, target in manifest['direct_restore'].items():
        path = safe_path(root, target, build_only=True)
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            with (release / name).open('rb') as source, path.open('xb') as dest:
                shutil.copyfileobj(source, dest)
    for name, expected in destinations.items():
        if digest(safe_path(root, name, build_only=True)) != expected['sha256']:
            raise ValueError('Restored file verification failed: ' + name)
    package = dict(status='pass', target='triha_face_board',
                   directory=manifest['package_directory'], physical_board=False,
                   bitstream_sha256=manifest['bitstream_sha256'],
                   verify_mask_sha256=manifest['verify_mask_sha256'])
    pointer = root / 'build/video/latest_package_triha_face_board.json'
    pointer.write_text(json.dumps(package, indent=2) + '\n', encoding='utf-8')
    return len(destinations)


def replay(release, root, manifest, pds):
    """Regenerate and compare all bytes except validated header timestamps."""
    from datetime import datetime, timezone
    from build_pds import review_messages
    from common import tool
    pds = pds.resolve() if pds else tool('pds_shell').resolve()
    if digest(pds) != manifest['pds_shell_sha256']:
        raise ValueError('Native replay requires the qualified PDS 2022.2-SP6.4 executable')
    out = root / 'build/video' / ('release_replay_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    out.mkdir(parents=True, exist_ok=False)
    database = safe_path(root, manifest['routed_database'], build_only=True)
    if digest(database) != manifest['archive_members'][manifest['routed_database']]['sha256']:
        raise ValueError('Routed database differs')
    for name, source in manifest['replay_memory_images'].items():
        shutil.copyfile(safe_path(root, source, build_only=True), out / name)
    path = database.as_posix()
    if any(x in path for x in '{}\r\n'):
        raise ValueError('Unsupported Tcl path')
    script = out / 'replay.tcl'
    script.write_text('set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676\n'
                      + 'gen_bit_stream -force_to_run -input_db_file {' + path
                      + '} -scbv {High Voltage} -create_mask_file TRUE\n', encoding='utf-8')
    with (out / 'replay.log').open('wb') as log:
        process = subprocess.run([str(pds), '-file', str(script), '-work_dir', str(out),
                                  '-project_name', 'triha_face_box'], cwd=out,
                                 stdout=log, stderr=subprocess.STDOUT, timeout=600,
                                 creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    _, rejected = review_messages((out / 'replay.log').read_text(encoding='utf-8', errors='replace'))
    bit = out / 'generate_bitstream/triha_face_board_top.sbit'
    mask = bit.with_suffix('.smsk')
    if process.returncode or rejected:
        raise ValueError('Native replay failed; inspect ' + str(out / 'replay.log'))
    result = dict(bitstream_sha256=digest(bit), verify_mask_sha256=digest(mask),
                  reference_bitstream_sha256=manifest['bitstream_sha256'],
                  reference_verify_mask_sha256=manifest['verify_mask_sha256'])
    try:
        result['bitstream_comparison'] = compare_pango_bytes(
            (release / bit.name).read_bytes(), bit.read_bytes())
        result['mask_comparison'] = compare_pango_bytes(
            (release / mask.name).read_bytes(), mask.read_bytes())
        result['status'] = 'PASS_CONFIGURATION_IDENTICAL'
    except ValueError as error:
        result.update(status='FAIL_CONFIGURATION_DIFFERENCE', error=str(error))
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('NATIVE_REPLAY', result['status'], out, flush=True)
    if result['status'] != 'PASS_CONFIGURATION_IDENTICAL':
        raise ValueError('Regenerated configuration differs from the accepted package')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', type=Path, default=DEFAULT_RELEASE)
    parser.add_argument('--install', action='store_true', help='Restore verified payload under build/')
    parser.add_argument('--replay-bitstream', action='store_true', help='After --install, regenerate and compare native bytes')
    parser.add_argument('--pds', type=Path)
    args = parser.parse_args()
    if args.replay_bitstream and not args.install:
        parser.error('--replay-bitstream requires --install')
    try:
        manifest = verify(args.release.resolve(), ROOT)
        print('FACE_RELEASE_VERIFY_PASS', len(manifest['source_sha256']), 'source files;',
              len(manifest['archive_members']), 'archived files', flush=True)
        if args.install:
            count = install(args.release.resolve(), ROOT, manifest)
            print('FACE_RELEASE_INSTALL_PASS', count, 'files; no board access', flush=True)
        if args.replay_bitstream:
            replay(args.release.resolve(), ROOT, manifest, args.pds)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.TimeoutExpired) as error:
        print('FACE_RELEASE_FAIL:', error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

"""Import exact upstream testbenches and a test-only native bridge closure."""
import argparse
import json
from pathlib import Path
import sys

from import_b03 import ROOT, REVISION, digest, git, need, plan_import, safe_path

DESTINATION = 'tb/npu/upstream/b03'
FILELIST = 'config/npu_b03_test_sources.f'
TESTBENCHES = [
    'Testbench/platform/tb_b03_full_frame_payload.sv',
    'Testbench/platform/b03_full_frame_payload_driver.svh',
    'Testbench/platform/tb_b03_payload_lifetime.sv',
    'Testbench/platform/tb_b03_payload_ack_reset.sv',
]


def plan(repo):
    bridge, blobs = plan_import(repo, REVISION, ['npu_session_mem_bridge_burst'])
    files = list(bridge['files'])
    for name in TESTBENCHES:
        raw = git(repo, 'show', REVISION + ':' + name)
        blobs[name] = raw
        files.append({'path': name, 'sha256': digest(raw), 'bytes': len(raw),
                      'git_blob': git(repo, 'rev-parse', REVISION + ':' + name).decode().strip()})
    files.sort(key=lambda row: row['path'])
    manifest = {'schema': 'triha-b03-test-sources-v1', 'source_commit': REVISION,
                'destination': DESTINATION, 'files': files,
                'scope': 'Test-only CDC/native memory proxy support; excluded from production RTL admission.',
                'control_scope': 'Lifetime/ACK tests inject leaf completions; they do not execute full inference.',
                'source_repository': bridge['source_repository'], 'license_note': bridge['license_note']}
    return manifest, blobs


def filelist(manifest):
    return ''.join(DESTINATION + '/' + row['path'] + '\n' for row in manifest['files']
                   if row['path'].endswith(('.v', '.sv'))).encode('utf-8')


def materialize(project, manifest, blobs):
    project = Path(project).resolve()
    writes = {project / DESTINATION / safe_path(row['path']): blobs[row['path']] for row in manifest['files']}
    writes[project / DESTINATION / 'UPSTREAM.json'] = (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()
    writes[project / FILELIST] = filelist(manifest)
    for path, raw in writes.items():
        need(not path.exists() or path.read_bytes() == raw, 'existing test source differs: ' + str(path))
        need(path.resolve().is_relative_to(project), 'test destination escapes project')
    for path, raw in writes.items():
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('xb') as stream:
                stream.write(raw)
    return verify(project)


def verify(project=ROOT):
    project = Path(project)
    base = project / DESTINATION
    manifest = json.loads((base / 'UPSTREAM.json').read_bytes())
    need(manifest.get('schema') == 'triha-b03-test-sources-v1' and manifest.get('source_commit') == REVISION and
         manifest.get('destination') == DESTINATION, 'test source manifest schema/commit')
    names = [safe_path(row['path']) for row in manifest['files']]
    need(len(names) == 15 and names == sorted(set(names)), 'test source set/count')
    for row in manifest['files']:
        path = base / row['path']
        need(path.is_file() and path.resolve().is_relative_to(base.resolve()), 'missing/nonordinary test source')
        raw = path.read_bytes()
        need(digest(raw) == row['sha256'] and len(raw) == row['bytes'], 'test source SHA mismatch: ' + row['path'])
    actual = {p.relative_to(base).as_posix() for p in base.rglob('*') if p.suffix in ('.v', '.sv', '.svh', '.vh')}
    need(actual == set(names), 'test source inventory mismatch')
    need((project / FILELIST).read_bytes() == filelist(manifest), 'test explicit filelist mismatch')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-repo', type=Path, default=ROOT.parent / 'npu_zgtc')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    try:
        result = verify() if args.check else materialize(ROOT, *plan(args.source_repo))
        print(json.dumps({'status': 'PASS_TEST_SOURCE_ADMISSION', 'files': len(result['files']),
                          'source_commit': result['source_commit'], 'RTL_executed': False}))
        return 0
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

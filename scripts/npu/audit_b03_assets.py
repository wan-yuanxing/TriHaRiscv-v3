"""Audit B03 bytes against the immutable upstream package; never a hardware gate."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

REVISION = '558280b30219acdcf9f962acd6e907e0f680ab52'
MANIFEST_PATH = 'yunet/reports/b03_runtime_v1/package_manifest.json'
MANIFEST_SHA256 = 'd1305ad11d4997cf79e3646af2f31a5306b75d751210505de9a80fd0a259bbd0'
CASES = ('zero', 'full255', 'pattern', 'calibration_image_000', 'wider_stress_0', 'wider_stress_1')
CORE = ('program.bin', 'parameter_image.bin', 'post_table.bin')
CASE_LEAVES = ('input.bin', 'heads_golden.bin', 'records_golden.bin', 'task.bin')
REQUIRED = set(CORE) | {f'cases/{case}/{leaf}' for case in CASES for leaf in CASE_LEAVES}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(root, relative):
    require(isinstance(relative, str) and relative and ':' not in relative and '\\' not in relative and
            all(part not in ('', '.', '..') for part in relative.split('/')), 'unsafe asset path')
    root = Path(root).resolve()
    candidate = root / relative
    require(candidate.resolve().is_relative_to(root), 'unsafe asset path escapes root')
    return candidate


def load_manifest(path, expected_sha256=MANIFEST_SHA256):
    raw = Path(path).read_bytes()
    require(digest(raw) == expected_sha256, 'historical manifest SHA mismatch')
    manifest = json.loads(raw)
    require(manifest.get('version') == 'b03-runtime-assets-v1' and manifest.get('passed') is True,
            'unsupported historical manifest version/status')
    files = manifest.get('files_sha256')
    require(isinstance(files, dict) and len(files) == 68, 'historical manifest must contain 68 files')
    require(REQUIRED <= files.keys(), 'historical manifest missing required runtime asset')
    sources = manifest.get('source_sha256')
    require(isinstance(sources, dict) and bool(sources), 'historical source inventory missing')
    for name, expected in list(files.items()) + list(sources.items()):
        safe_path(Path(path).parent, name)
        require(isinstance(expected, str) and re.fullmatch('[0-9a-f]{64}', expected), 'invalid asset digest')
    return manifest


def audit_assets(asset_root, manifest_path, *, expected_manifest_sha256=MANIFEST_SHA256):
    manifest = load_manifest(manifest_path, expected_manifest_sha256)
    matched, missing, mismatches = [], [], []
    for name, expected in manifest['files_sha256'].items():
        path = safe_path(asset_root, name)
        if not path.is_file():
            missing.append(name)
            continue
        actual = digest(path.read_bytes())
        if actual == expected:
            matched.append(name)
        else:
            mismatches.append({'path': name, 'expected_sha256': expected, 'actual_sha256': actual})
    core_ready = all(name in matched for name in CORE)
    ready = [case for case in CASES if core_ready and all(f'cases/{case}/{leaf}' in matched for leaf in CASE_LEAVES)]
    return {'schema': 'triha-b03-asset-audit-v1',
            'status': 'FAIL' if mismatches else 'PARTIAL' if missing else 'PASS_HOST_ASSETS_ONLY',
            'scope': 'Historical byte identity only; no RTL execution, physical DDR, PDS, board or frame-rate proof.',
            'upstream_revision': REVISION, 'historical_manifest_sha256': expected_manifest_sha256,
            'asset_root': str(Path(asset_root).resolve()), 'expected_count': 68,
            'matched_count': len(matched), 'matched': matched, 'missing': missing, 'mismatches': mismatches,
            'core_ready': core_ready, 'runtime_ready_cases': ready,
            'RTL_executed': False, 'DDR_executed': False, 'PDS_executed': False,
            'board_verified': False, 'board_30fps_verified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', required=True, type=Path)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.output and (args.output.resolve() == args.manifest.resolve() or
                        args.output.resolve().is_relative_to(args.assets.resolve())):
        print('audit report must be outside the asset tree and must not replace the manifest', file=sys.stderr)
        return 1
    # Invalidate a prior report before validation, including manifest errors.
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text('{"status":"RUNNING"}\n', encoding='utf-8')
    try:
        report = audit_assets(args.assets, args.manifest)
    except Exception as exc:
        report = {'status': 'FAIL', 'error': str(exc), 'RTL_executed': False, 'board_verified': False}
    text = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.write_text(text, encoding='utf-8')
    print(text, end='')
    return 0 if report['status'] == 'PASS_HOST_ASSETS_ONLY' else 2 if report['status'] == 'PARTIAL' else 1


if __name__ == '__main__':
    sys.exit(main())

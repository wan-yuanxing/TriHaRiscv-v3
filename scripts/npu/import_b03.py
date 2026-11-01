"""Import a reachable B03 RTL closure from immutable Git blobs.

The production filelist is explicit and independently checked. Source files are
kept byte-for-byte; neither the upstream checkout nor existing differing files
are overwritten. This is source admission, not a functionality/physical claim.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
REVISION = '558280b30219acdcf9f962acd6e907e0f680ab52'
DESTINATION = 'rtl/npu/upstream/b03'
FILELIST = 'config/npu_b03_sources.f'
ROOT_MODULES = ['b03_frame_exec_payload', 'b03_block_dma', 'b03_phase_mem_mux_burst']
EXTERNAL = {'GTP_APM_E2', 'GTP_DRM18K_E1', 'GTP_RAM32X1DP', 'GTP_LUT1', 'GTP_GRS'}
# Reviewed canonical manifest identity, independent of the installed manifest.
ADMISSION_SHA256 = '481d6687f21912a431a5ecdc5c8c178efcbd7b580700bb84cf9147251295a9df'
KEYWORDS = set(('module endmodule function endfunction task endtask if else for while '
                'case casez casex endcase begin end generate endgenerate always initial '
                'assign input output inout wire reg integer localparam parameter '
                'posedge negedge repeat wait disable automatic signed unsigned').split())


def need(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(name):
    need(isinstance(name, str) and not re.search(r'[\x00-\x1f\x7f\\:<>"|?*]', name), 'invalid relative path')
    path = PurePosixPath(name)
    need(not path.is_absolute() and path.parts and not any(p in ('.', '..') for p in path.parts)
         and str(path) == name, 'invalid relative path: ' + name)
    for part in path.parts:
        need(not part.endswith(('.', ' ')) and not re.fullmatch(
            r'(?i:CON|PRN|AUX|NUL|COM[1-9鹿虏鲁]|LPT[1-9鹿虏鲁])', part.split('.')[0]), 'unsafe Windows path: ' + name)
    return name


def canonical(manifest):
    return (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + '\n').encode()


def ordinary_path(project, path):
    """Reject links/junctions and non-directory ancestors before reading/writing."""
    project = Path(project).absolute()
    path = Path(path).absolute()
    need(path.is_relative_to(project), 'destination outside project')
    for item in [path, *path.parents]:
        if item.exists() or item.is_symlink():
            info = item.lstat()
            need(not item.is_symlink() and not getattr(info, 'st_file_attributes', 0) &
                 getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400), 'reparse/symlink in destination')
            need(item.is_file() if item == path else item.is_dir(), 'nonordinary destination/ancestor')
        if item == project:
            break


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.PIPE)


def git_rtl(repo, ref):
    need(re.fullmatch('[0-9a-f]{40}', ref) is not None, 'use a full immutable 40-character commit SHA')
    need(git(repo, 'cat-file', '-t', ref).strip() == b'commit', 'source object must be a commit')
    entries = []
    for row in git(repo, 'ls-tree', '-r', '-z', ref, 'rtl').split(b'\0'):
        if not row:
            continue
        meta, path = row.split(b'\t', 1)
        name = safe_path(path.decode('utf-8'))
        if not name.endswith(('.v', '.sv', '.vh', '.svh')):
            continue
        mode, kind, oid = meta.decode().split()
        need(mode in ('100644', '100755') and kind == 'blob', 'ordinary source blob required: ' + name)
        entries.append((name, oid))
    need(entries, 'no RTL blobs found')
    query = ''.join(oid + '\n' for _, oid in entries).encode('ascii')
    process = subprocess.run(['git', '-C', str(repo), 'cat-file', '--batch'], input=query,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    cursor, blobs, identities = 0, {}, {}
    for name, oid in entries:
        end = process.stdout.index(b'\n', cursor)
        header = process.stdout[cursor:end].decode().split()
        need(len(header) == 3 and header[:2] == [oid, 'blob'], 'Git batch identity mismatch')
        size = int(header[2])
        blob = process.stdout[end + 1:end + 1 + size]
        need(len(blob) == size and process.stdout[end + 1 + size:end + 2 + size] == b'\n', 'Git blob length')
        actual = hashlib.sha1(b'blob ' + str(size).encode() + b'\0' + blob).hexdigest()
        need(actual == oid, 'Git blob digest mismatch')
        cursor = end + 2 + size
        blobs[name], identities[name] = blob, oid
    need(cursor == len(process.stdout), 'unexpected Git batch output')
    return blobs, identities


def clean(source):
    # Strings remain for include discovery, but disappear from instance parsing.
    return re.sub(r'//[^\n]*|/\*.*?\*/', ' ', source, flags=re.S)


def after_parenthesis(text, start):
    need(text[start] == '(', 'parameter parenthesis')
    depth = 0
    for index in range(start, len(text)):
        if text[index] == '(':
            depth += 1
        elif text[index] == ')':
            depth -= 1
            if depth == 0:
                return index + 1
    raise ValueError('unterminated module parameter list')


def instances(text):
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    result = set()
    for match in re.finditer(r'\b([A-Za-z_]\w*)\b', text):
        name = match[1]
        if name in KEYWORDS:
            continue
        at = match.end()
        while at < len(text) and text[at].isspace():
            at += 1
        if at < len(text) and text[at] == '#':
            at += 1
            while at < len(text) and text[at].isspace():
                at += 1
            need(at < len(text) and text[at] == '(', 'unsupported parameter syntax: ' + name)
            at = after_parenthesis(text, at)
        # An instance name must precede the port-list, unlike a function call.
        instance = re.match(r'\s*([A-Za-z_]\w*)\s*(?:\[[^\]]+\]\s*)?\(', text[at:])
        if instance and instance[1] not in KEYWORDS and at > match.end():
            result.add(name)
    return result


def dependency_closure(blobs, roots):
    definitions, texts = {}, {}
    need(len({p.casefold() for p in blobs}) == len(blobs), 'case-insensitive path collision')
    for path, blob in blobs.items():
        text = clean(blob.decode('utf-8-sig'))
        texts[path] = text
        for module in re.findall(r'\bmodule\s+([A-Za-z_]\w*)', text):
            definitions.setdefault(module, []).append(path)
    need(roots and len(roots) == len(set(roots)), 'unique nonempty root modules required')
    for root in roots:
        need(root in definitions, 'missing root module: ' + root)
    pending, selected, external, hierarchy = [], set(), set(), {}
    for root in roots:
        need(len(definitions[root]) == 1, 'ambiguous selected module: ' + root)
        pending.append(definitions[root][0])
    while pending:
        path = pending.pop()
        if path in selected:
            continue
        selected.add(path)
        dependencies = instances(texts[path])
        hierarchy[path] = sorted(dependencies)
        for child in sorted(dependencies):
            if child in EXTERNAL:
                external.add(child)
            else:
                need(child in definitions, 'unknown module ' + child + ' in ' + path)
                need(len(definitions[child]) == 1, 'ambiguous selected module: ' + child)
                pending.append(definitions[child][0])
        for directive in re.finditer(r'`include\b([^\n]*)', texts[path]):
            literal = re.fullmatch(r'\s*"([^"]+)"\s*', directive[1])
            need(literal is not None, 'unsupported include syntax in ' + path)
            include = literal[1]
            safe_path(include)
            target = str(PurePosixPath(path).parent / include)
            need(target in blobs, 'missing relative include ' + include + ' in ' + path)
            pending.append(target)
    return sorted(selected), {p: hierarchy[p] for p in sorted(hierarchy)}, sorted(external)


def plan_import(repo, ref, roots):
    blobs, oids = git_rtl(repo, ref)
    selected, hierarchy, external = dependency_closure(blobs, roots)
    files = [{'path': p, 'sha256': digest(blobs[p]), 'git_blob': oids[p], 'bytes': len(blobs[p])}
             for p in sorted(selected)]
    manifest = {'schema_version': 1, 'source_repository': 'https://github.com/keep-s/npu_zgtc',
                'source_commit': ref, 'root_modules': roots, 'destination': DESTINATION,
                'files': files, 'module_dependencies': hierarchy, 'external_modules': external,
                'license_note': 'Upstream RTL files retained verbatim; no repository-level RTL license declared in this snapshot.',
                'scope': 'source admission only; upstream diagnostic scope0 remains unchanged',
                'excluded': ['board/UART/PLL/HMIC top', 'exclusive native session bridge', 'other optimization candidates']}
    return manifest, {p: blobs[p] for p in sorted(selected)}


def validate_manifest(manifest):
    need(manifest['schema_version'] == 1 and manifest['destination'] == DESTINATION, 'manifest schema/destination')
    need(re.fullmatch('[0-9a-f]{40}', manifest['source_commit']) is not None, 'manifest commit')
    names = []
    for item in manifest['files']:
        name = safe_path(item['path'])
        need(name.startswith('rtl/') and name.endswith(('.v', '.sv', '.vh', '.svh')), 'unexpected source path')
        need(re.fullmatch('[0-9a-f]{64}', item['sha256']) is not None, 'manifest SHA256')
        need(re.fullmatch('[0-9a-f]{40}', item['git_blob']) is not None, 'manifest Git blob')
        need(type(item['bytes']) is int and item['bytes'] >= 0, 'manifest byte count')
        names.append(name)
    need(names and names == sorted(set(names)), 'manifest source ordering/duplicates')
    need(len({p.casefold() for p in names}) == len(names), 'case-insensitive path collision')
    return names


def filelist_bytes(manifest):
    return ''.join(DESTINATION + '/' + n + '\n' for n in validate_manifest(manifest)
                   if n.endswith(('.v', '.sv'))).encode('utf-8')


def materialize(project, manifest, blobs):
    names = validate_manifest(manifest)
    need(set(blobs) == set(names), 'blob set differs from manifest')
    writes = {}
    for item in manifest['files']:
        data = blobs[item['path']]
        need(digest(data) == item['sha256'] and len(data) == item['bytes'], 'source SHA256 mismatch')
        need(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == item['git_blob'], 'source Git blob mismatch')
        writes[Path(project) / DESTINATION / item['path']] = data
    selected, hierarchy, external = dependency_closure(blobs, manifest['root_modules'])
    need(selected == names and hierarchy == manifest['module_dependencies'] and external == manifest['external_modules'], 'source dependency closure mismatch')
    writes[Path(project) / DESTINATION / 'UPSTREAM.json'] = canonical(manifest)
    writes[Path(project) / FILELIST] = filelist_bytes(manifest)
    # Complete preflight before the first write; never overwrite user changes.
    for path, data in writes.items():
        ordinary_path(project, path)
        need(not path.exists() or (path.is_file() and path.read_bytes() == data), 'existing file differs: ' + str(path))
    base = Path(project) / DESTINATION
    existing = {p.relative_to(base).as_posix() for p in base.rglob('*') if p.suffix.lower() in ('.v', '.sv', '.vh', '.svh')}
    need(existing <= set(names), 'extra existing HDL files')
    for path, data in writes.items():
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('xb') as stream:
                stream.write(data)
    return verify_import(project, trusted_manifest=manifest)


def verify_import(project, *, trusted_manifest=None):
    base = Path(project) / DESTINATION
    ordinary_path(project, base / 'UPSTREAM.json')
    manifest = json.loads((base / 'UPSTREAM.json').read_text(encoding='utf-8'))
    expected = digest(canonical(trusted_manifest)) if trusted_manifest is not None else ADMISSION_SHA256
    need(digest(canonical(manifest)) == expected, 'manifest differs from trusted admission identity')
    names = validate_manifest(manifest)
    blobs = {}
    for item in manifest['files']:
        path = base / item['path']
        ordinary_path(project, path)
        need(path.is_file() and not path.is_symlink(), 'missing/nonordinary imported source: ' + item['path'])
        data = path.read_bytes()
        need(digest(data) == item['sha256'] and len(data) == item['bytes'], 'imported SHA256 mismatch: ' + item['path'])
        need(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == item['git_blob'], 'imported Git blob mismatch')
        blobs[item['path']] = data
    selected, hierarchy, external = dependency_closure(blobs, manifest['root_modules'])
    need(selected == names and hierarchy == manifest['module_dependencies'] and external == manifest['external_modules'], 'manifest dependency closure mismatch')
    actual = {p.relative_to(base).as_posix() for p in base.rglob('*') if p.suffix in ('.v', '.sv', '.vh', '.svh')}
    need(actual == set(names), 'extra/missing imported HDL files')
    ordinary_path(project, Path(project) / FILELIST)
    need((Path(project) / FILELIST).read_bytes() == filelist_bytes(manifest), 'explicit filelist differs from admitted sources')
    return {'status': 'PASS_SOURCE_ADMISSION', 'files': len(names), 'modules': len(manifest['module_dependencies']),
            'source_commit': manifest['source_commit'], 'rtl_simulated': False, 'physical_admission': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-repo', type=Path, default=ROOT.parent / 'npu_zgtc')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    try:
        if args.check:
            result = verify_import(ROOT)
        else:
            manifest, blobs = plan_import(args.source_repo, REVISION, ROOT_MODULES)
            result = materialize(ROOT, manifest, blobs)
        print(json.dumps(result, indent=2))
        return 0
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print('B03_IMPORT_FAIL: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())








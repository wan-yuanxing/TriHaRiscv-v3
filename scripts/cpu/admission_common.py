"""Local, content-bound inputs for native Windows CPU admission tests."""
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SIM = Path(os.environ.get('TRIHA_VSIM') or shutil.which('vsim') or
           'D:/modeltech64_2020.4/win64/vsim.exe').resolve().parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def validate(root=ROOT):
    root = Path(root).resolve()
    manifest = json.loads((root / 'config/cpu_admission.json').read_text(encoding='utf-8'))
    for row in manifest['files']:
        path = (root / row['destination']).resolve()
        if not path.is_relative_to(root) or not path.is_file() or sha(path) != row['sha256']:
            raise ValueError('admitted source hash mismatch: ' + row['destination'])
    for model in manifest['simulation_models']:
        if not Path(model['path']).is_file() or sha(model['path']) != model['sha256']:
            raise ValueError('primitive hash mismatch: ' + model['path'])
    return manifest


def prepare_isa_inputs(root, target):
    """Stage only pinned test/oracle inputs from the main-tree support ZIP.

    Archived DUT PASS results are not consumed. Every test is executed again.
    Generation files describe the earlier no-C Sail run; no generator is run.
    """
    root, target = Path(root).resolve(), Path(target).resolve()
    manifest = json.loads((root / 'config/cpu_admission.json').read_text(encoding='utf-8'))
    archive = root / manifest['isa_archive']['path']
    if sha(archive) != manifest['isa_archive']['sha256']:
        raise ValueError('ISA archive hash mismatch')
    if not target.is_relative_to(root / 'build'):
        raise ValueError('ISA staging must stay inside main build directory')
    configroot = target / 'act4'
    actroot = configroot / 'generated/triha-rv32im-zicsr'
    planned = []
    with zipfile.ZipFile(archive) as zipped:
        hashes = json.loads(zipped.read('SHA256SUMS.json'))

        def stage(member, destination):
            data = zipped.read(member)
            if hashlib.sha256(data).hexdigest() != hashes[member]:
                raise ValueError('ISA member hash mismatch: ' + member)
            planned.append((destination, data))

        for name in zipped.namelist():
            if name.startswith('act4-generation/') and not name.endswith('/'):
                basename = name.split('/')[-1]
                stage(name, configroot / basename)
                if basename in ['.act_build_cache.json', 'rvtest_config.svh', 'rvtest_config.h',
                                'rvmodel_macros.svh']:
                    stage(name, actroot / basename)
        for suite, expected in [('riscv-tests', 50), ('act4', 53)]:
            listing = suite + '-cases.csv'
            stage(listing, target / 'support' / listing)
            rows = list(csv.DictReader(io.StringIO(zipped.read(listing).decode('utf-8-sig'))))
            if len(rows) != expected:
                raise ValueError('unexpected ISA case count')
            for row in rows:
                case = row['case']
                destination = (target / 'riscv-tests' / case / (case + '.elf') if suite == 'riscv-tests'
                               else actroot / 'elfs/rv32i' / row['category'] / (case + '.elf'))
                stage('runs/' + suite + '/' + case + '/test.elf', destination)
                if suite == 'act4':
                    for suffix in ['.sig', '.sig.log', '.results', '.sig.elf']:
                        stage('runs/act4/' + case + '/' + case + suffix,
                              actroot / 'build/rv32i' / row['category'] / (case + suffix))
    for path, data in planned:
        if not path.resolve().is_relative_to(target):
            raise ValueError('unsafe ISA archive mapping')
        if path.exists() and path.read_bytes() != data:
            raise ValueError('ISA staging conflict: ' + str(path))
    for path, data in planned:
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            path.write_bytes(data)
    return {'input_root': target, 'act4_root': actroot, 'support': target / 'support',
            'archive_sha256': sha(archive), 'staged_files': len(planned)}

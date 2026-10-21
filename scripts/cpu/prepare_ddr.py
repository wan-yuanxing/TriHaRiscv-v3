"""Extract pinned DDR dependencies without reading or modifying another checkout."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def materialize(work, config=ROOT/'config/cpu_ddr.json'):
    work = Path(work).resolve()
    spec = json.loads(Path(config).read_text(encoding='utf-8'))
    if (spec['schema_version'] != 1 or spec['cpu_hz'] != 100000000 or spec['ddr_hz'] != 125000000 or
            spec['axi_data_bits'] != 128 or spec['axi_id_bits'] != 4 or spec['fifo_address_bits'] != 2):
        raise ValueError('unsupported CPU DDR geometry/clock')
    if spec['reset'] != 'single_coordinated_epoch':
        raise ValueError('DDR reset must use a single coordinated epoch')
    if not re.fullmatch('[0-9a-f]{40}', spec['revision']):
        raise ValueError('DDR revision must be an immutable full commit')
    git = Path(shutil.which('git')).resolve()
    result = dict(revision=spec['revision'], files={}, git=str(git),
                  git_sha256=hashlib.sha256(git.read_bytes()).hexdigest())
    for name, digest in spec['files'].items():
        if PurePosixPath(name).is_absolute() or '..' in PurePosixPath(name).parts or ':' in name or '\\' in name:
            raise ValueError('unsafe DDR dependency path')
        command = [str(git), 'cat-file', 'blob', spec['revision']+':'+name]
        data = subprocess.check_output(command, cwd=ROOT)
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError('pinned DDR hash mismatch: '+name)
        target = work/'pinned'/name
        if target.exists() and target.read_bytes() != data:
            raise ValueError('frozen DDR file changed: '+name)
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            target.write_bytes(data)
        result['files'][name] = dict(sha256=digest, path=str(target), command=command,
            git_blob_sha1=hashlib.sha1(b'blob '+str(len(data)).encode('ascii')+b'\0'+data).hexdigest())
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(materialize(args.directory), indent=2))

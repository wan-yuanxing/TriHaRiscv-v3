"""Unpack a hash-pinned Windows simulator tool into build/; no installation."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT=Path(__file__).resolve().parents[2]
FILENAME='verilator-5.48.0-py3-none-win_amd64.whl'
URL='https://files.pythonhosted.org/packages/e1/83/af403e28686d4bdaffe517809fdd77b5c746f3b7953a5880acb60f12e716/'+FILENAME
DIGEST='e03aad7e023bbe585f909276f3c03af66f7ede72155f8f75fdaf4f1ec8250e09'


def prepare(target, wheel=None):
    target=Path(target).resolve()
    if target.exists():raise ValueError('tool directory already exists; preserve and verify its provenance.json')
    data=Path(wheel).read_bytes() if wheel else urllib.request.urlopen(URL,timeout=90).read()
    if hashlib.sha256(data).hexdigest()!=DIGEST:raise ValueError('tool wheel SHA256 mismatch')
    target.mkdir(parents=True)
    package=target/FILENAME;package.write_bytes(data)
    with zipfile.ZipFile(package) as archive:
        for member in archive.infolist():
            path=(target/member.filename).resolve()
            if not path.is_relative_to(target):raise ValueError('unsafe wheel member')
            if member.is_dir():continue
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(archive.read(member))
    files={str(p.relative_to(target)):hashlib.sha256(p.read_bytes()).hexdigest()
           for p in target.rglob('*') if p.is_file()}
    record={'source':URL,'publisher':'dau-dev/verilator-python third-party package',
            'package_version':'5.48.0','wheel_sha256':DIGEST,'files_sha256':files,
            'note':'record actual verilator_bin.exe --version separately; package is not an official release attestation'}
    (target/'provenance.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    return target/'verilator'


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/npu/tools/verilator-5.48.0-win_amd64')
    parser.add_argument('--wheel',type=Path)
    args=parser.parse_args()
    print(prepare(args.output,args.wheel))

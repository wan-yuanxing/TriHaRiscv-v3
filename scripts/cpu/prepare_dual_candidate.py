"""Recreate the measured CPU candidate from checked base files and a patch."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(output,manifest_path=None):
    output=output.resolve()
    build=(ROOT/'build/cpu').resolve()
    if not output.is_relative_to(build) or output==build:
        raise ValueError('Candidate must be a new directory below build/cpu')
    if output.exists():
        raise FileExistsError('Candidate directory already exists; preserve it')
    manifest_path=manifest_path or ROOT/'docs/verification/cpu/dualissue_pairing_sources.json'
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    patch=ROOT/manifest.get('patch_file','docs/verification/cpu/dualissue_pairing_diagnostic.patch')
    if sha(patch)!=manifest['patch_sha256']:
        raise ValueError('Diagnostic patch drift')
    for name,record in manifest['sources'].items():
        if sha(ROOT/name)!=record['base_sha256']:
            raise ValueError('Candidate base drift: '+name)
    for name in manifest['sources']:
        target=output/name
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/name,target)
    prefix=output.relative_to(ROOT).as_posix()
    command=['git','-c','safe.directory='+ROOT.as_posix(),'apply','--whitespace=nowarn','--directory='+prefix,str(patch)]
    subprocess.run(command,cwd=ROOT,check=True,capture_output=True)
    for name,record in manifest['sources'].items():
        if sha(output/name)!=record['candidate_sha256']:
            raise ValueError('Candidate reconstruction drift: '+name)
    return output/'rtl/cpu'


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('output',type=Path)
    parser.add_argument('--manifest',type=Path)
    args=parser.parse_args()
    print('CPU_CANDIDATE_RECONSTRUCTED',prepare(args.output,args.manifest))

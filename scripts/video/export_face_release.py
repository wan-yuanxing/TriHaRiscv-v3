"""Freeze a qualified face package, models and evidence for verified restoration.

Does not publish or access hardware. The destination must be a new directory.
Use restore_face_release.py --release <directory> to independently verify it.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

from common import ROOT
from face_profiles import require_profile
from restore_face_release import digest, verify


def export(qualified, output, additional, components=()):
    qualified=qualified.resolve();output=output.resolve()
    qualification_bytes=qualified.read_bytes()
    q=json.loads(qualification_bytes)
    profile=require_profile(q)
    if not (q['status']=='pass' and q['stage']=='bitstream' and q['internal_timing_met']
            and q['cdc_timing_met'] and q['input_snapshot_verified_before_and_after_build']):
        raise ValueError('A fully qualified bitstream is required')
    if output.exists():
        raise ValueError('Use a new export directory; existing releases are immutable')
    files={}
    bound_inputs={qualified:hashlib.sha256(qualification_bytes).hexdigest()}

    def check_bound(path,expected,message):
        path=path.resolve()
        if path in bound_inputs and bound_inputs[path]!=expected:
            raise ValueError('Conflicting evidence hashes: '+str(path))
        if digest(path)!=expected:
            raise ValueError(message+str(path))
        bound_inputs[path]=expected

    def add(path):
        path=(ROOT/Path(path)).resolve()
        if not path.is_relative_to(ROOT/'build') or not path.is_file():
            raise ValueError('Export payload must be an existing build file: '+str(path))
        files[path.relative_to(ROOT).as_posix()]=path

    def tree(path):
        path=(ROOT/Path(path)).resolve()
        if not path.is_relative_to(ROOT/'build') or not path.is_dir():
            raise ValueError('Export tree must be an existing build directory: '+str(path))
        for child in path.rglob('*'):
            if child.is_file() and not {'work','__pycache__'}.intersection(child.relative_to(path).parts):
                add(child)

    sources=dict(q['inputs'])
    for name, expected in q['evidence_inputs'].items():
        path=Path(name)
        check_bound(path,expected,'Qualified evidence changed: ')
        if path.is_relative_to(ROOT/'build'):
            add(path)
    base=Path(q['source_build_directory'])
    tree(base)
    base_result=json.loads((base/'result.json').read_text(encoding='utf-8'))
    for name,expected in base_result.get('mapping_inputs',{}).items():
        path=Path(name)
        check_bound(path,expected,'Mapping provenance changed: ')
        if path.is_relative_to(ROOT/'build'):
            add(path)
    for entry in q['functional']:
        directory=Path(entry['directory'])
        check_bound(directory/'result.json',entry['result_sha256'],'Functional result changed: ')
        r=json.loads((directory/'result.json').read_text(encoding='utf-8'))
        if r['status']!='PASS':
            raise ValueError('Functional regression has not passed')
        for name,expected in r['source_sha256'].items():
            if name in sources and sources[name]!=expected:
                raise ValueError('Conflicting source identities: '+name)
            sources[name]=expected
        for name,expected in r['output_sha256'].items():
            check_bound(directory/name,expected,'Simulation output changed: ')
        # Preserve the scene actually exercised by this simulation. Historical
        # fixture directory names are not dependencies of a new release.
        for name,expected in r.get('external_sha256',{}).items():
            path=(ROOT/Path(name)).resolve()
            check_bound(path,expected,'Simulation external input changed: ')
            if path.is_relative_to(ROOT/'build'):
                add(path)
            elif path.is_relative_to(ROOT):
                relative=path.relative_to(ROOT).as_posix()
                if relative in sources and sources[relative]!=expected:
                    raise ValueError('Conflicting source identities: '+relative)
                sources[relative]=expected
        tree(directory)
    for name in ('scripts/video/program_board.py','scripts/video/restore_face_release.py',
                 'scripts/video/export_face_release.py','scripts/soc/upload_face_model.py'):
        sources[name]=digest(ROOT/name)
    # Explicit current component results contribute their test sources as well
    # as logs. Historical physical provenance supplied through --include stays
    # historical and is not mistaken for a current-source regression.
    for component in components:
        component=(ROOT/component).resolve()
        if not component.is_relative_to(ROOT/'build') or not component.is_file():
            raise ValueError('Component result must be an existing build file')
        raw=component.read_bytes()
        record=json.loads(raw)
        if record.get('status') not in ('pass','PASS'):
            raise ValueError('Component regression has not passed: '+str(component))
        check_bound(component,hashlib.sha256(raw).hexdigest(),'Component result changed: ')
        tree(component.parent)
        for key in ('inputs','source_sha256','input_hashes'):
            for original,expected in record.get(key,{}).items():
                path=(ROOT/Path(original)).resolve()
                check_bound(path,expected,'Component input changed: ')
                if path.is_relative_to(ROOT/'build'):
                    add(path)
                elif path.is_relative_to(ROOT):
                    name=path.relative_to(ROOT).as_posix()
                    if name in sources and sources[name]!=expected:
                        raise ValueError('Conflicting component source identities: '+name)
                    sources[name]=expected
        artifact_maps=[(key,ROOT) for key in record if key=='artifacts' or key.endswith('_artifacts')]
        artifact_maps += [('output_sha256',component.parent),('output_hashes',component.parent)]
        for key,origin in artifact_maps:
            for original,expected in record.get(key,{}).items():
                path=(origin/Path(original)).resolve()
                check_bound(path,expected,'Component artifact changed: ')
                add(path)
    for name,expected in sources.items():
        check_bound(ROOT/name,expected,'Qualified source changed: ')
    for name in ('build/video/vendor','build/npu/b03_assets_20261030'):
        tree(name)
    for path in additional:
        tree(path) if path.is_dir() else add(path)
    # Include all native audit Tcl/console records, but no unrelated old runs.
    for name in list(files):
        if name.endswith('/result.json'):
            directory=(ROOT/name).parent
            for path in directory.rglob('*'):
                if path.is_file() and (path.suffix=='.tcl' or path.name in ('console.log','receipt.json','routing.rcf','place.log','route.log')):
                    add(path)
    tree(qualified.parent)
    # Receipts bind their own inputs. Preserve the original placement database
    # even when qualification uses a later route-only implementation.
    inspected=set()
    while True:
        pending=[name for name in files if name.endswith('.json') and name not in inspected]
        if not pending:break
        for name in pending:
            inspected.add(name)
            record=json.loads((ROOT/name).read_text(encoding='utf-8-sig'))
            if not isinstance(record,dict):continue
            for key in ('inputs','mapping_inputs','evidence_inputs','bitstream_generation_inputs'):
                entries=record.get(key,{})
                if not isinstance(entries,dict):continue
                for original,expected in entries.items():
                    if not isinstance(expected,str) or len(expected)!=64:continue
                    path=(ROOT/Path(original)).resolve()
                    if path.is_relative_to(ROOT/'build'):
                        check_bound(path,expected,'Bound build input changed: ')
                        add(path)
    package=ROOT/'build/video/releases'/('triha_face_board_'+q['artifact_sha256'][:12])
    if (package/'manifest.json').read_bytes()!=qualified.read_bytes():
        raise ValueError('Offline package differs from qualification')
    for name in ('manifest.json','README.txt','message_review.json','timing.rtr'):
        add(package/name)
    bit=ROOT/q['artifact'];mask=ROOT/q['verify_mask']
    check_bound(bit,q['artifact_sha256'],'Bitstream changed: ')
    check_bound(mask,q['verify_mask_sha256'],'Mask changed: ')
    # Resolve the sole final route from its identity-bound record.
    routes=[]
    for name in files:
        if name.endswith('/receipt.json'):
            r=json.loads((ROOT/name).read_text(encoding='utf-8'))
            if r.get('status')=='ROUTE_REVIEW_READY' and r.get('routed_db') in q['evidence_inputs']:
                routes.append(r)
    if len(routes)!=1:
        raise ValueError('Expected exactly one qualified final route')
    route=routes[0]
    payload_snapshot={name:digest(path) for name,path in files.items()}
    # Recheck earlier evidence after collection. Compression can take minutes;
    # every read must match this snapshot, not merely its newly computed ZIP hash.
    for path,expected in bound_inputs.items():
        if digest(path)!=expected:
            raise ValueError('Bound input changed before exporting: '+str(path))
    output.mkdir(parents=True,exist_ok=False)
    members={};parts=[];index=0;archive=None
    try:
        for name,path in sorted(files.items()):
            # Begin a new part after 45 MiB of compressed data. Individual ADFs
            # remain whole; verify the final ZIP size is below GitHub's cap.
            if archive is None or archive.fp.tell()>45*1024*1024:
                if archive is not None:archive.close()
                index+=1;part=output/f'reproduction-{index:02d}.zip';parts.append(part)
                archive=zipfile.ZipFile(part,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=9)
            data=path.read_bytes()
            actual=hashlib.sha256(data).hexdigest()
            if actual!=payload_snapshot[name]:
                raise ValueError('Payload changed while exporting: '+name)
            info=zipfile.ZipInfo(name,date_time=(2026,11,3,0,0,0))
            info.external_attr=0o100644<<16
            archive.writestr(info,data,compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
            members[name]=dict(bytes=len(data),sha256=actual)
    finally:
        if archive is not None:archive.close()
    direct={}
    for path,expected in ((bit,q['artifact_sha256']),(mask,q['verify_mask_sha256'])):
        dest=output/path.name;shutil.copyfile(path,dest)
        if digest(dest)!=expected:
            raise ValueError('Direct bitstream or mask changed while exporting: '+str(path))
        direct[path.name]=(package/path.name).relative_to(ROOT).as_posix()
    for name,path in files.items():
        if digest(path)!=payload_snapshot[name]:
            raise ValueError('Payload changed while exporting: '+name)
    for path,expected in bound_inputs.items():
        if digest(path)!=expected:
            raise ValueError('Bound input changed while exporting: '+str(path))
    release_files={p.name:dict(bytes=p.stat().st_size,sha256=digest(p)) for p in parts+[output/bit.name,output/mask.name]}
    if any(v['bytes']>=95*1024*1024 for v in release_files.values()):
        raise ValueError('An archive is too large for this Git delivery policy')
    baseline=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    pds_hash=next(value for name,value in q['bitstream_generation_inputs'].items() if name.endswith('pds_shell.exe'))
    manifest=dict(schema_version=1,release=output.name,target='triha_face_board',profile=profile,
        source_base_commit=baseline,source_identity='Qualified file hashes below include current changes; base commit is provenance only.',
        bitstream_sha256=q['artifact_sha256'],verify_mask_sha256=q['verify_mask_sha256'],
        archives=[p.name for p in parts],files=release_files,archive_members=members,source_sha256=sources,
        direct_restore=direct,package_directory=package.relative_to(ROOT).as_posix(),
        routed_database=Path(route['routed_db']).relative_to(ROOT).as_posix(),
        replay_memory_images={n:(qualified.parent/n).relative_to(ROOT).as_posix() for n in ('rom.hex','sram.hex','firmware.elf')},
        pds_shell_sha256=pds_hash,
        limitations=['External HDMI I/O AC is not formally signed off.','Board inference FPS remains unmeasured.',
                    'Inspect separate board acceptance evidence; offline qualification is not visual proof.',
                    'Native replay permits only parsed file-header timestamps to change.',
                    'Fresh synthesis/placement/routing requires new qualification; byte determinism is not promised.'])
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8',newline='\n')
    verify(output,ROOT)
    print('FACE_RELEASE_EXPORT_PASS',output,'members',len(members),'sources',len(sources),flush=True)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--qualified',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--include',type=Path,action='append',default=[])
    p.add_argument('--component',type=Path,action='append',default=[],
                   help='Passed current component result.json; bind its sources and artifacts')
    args=p.parse_args()
    export(args.qualified,args.output,args.include,args.component)


if __name__=='__main__':main()

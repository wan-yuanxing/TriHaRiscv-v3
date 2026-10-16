"""Generate complete hash-locked HMIC IP; board constraints remain separate."""
import argparse
import json
from pathlib import Path
import re
import shutil
import sys
import xml.etree.ElementTree as ET

from common import BUILD,ROOT,run_logged,sha256,tool,write_json
from prepare_reference import relative_path


def verify_dependencies(library,items):
    verified={}
    for item in items:
        relative=str(relative_path(item['path']))
        source=library/relative
        if sha256(source)!=item['sha256']:raise ValueError('DDR dependency hash mismatch: '+relative)
        verified[relative]=source
    return verified


def verify_generated_sources(output,manifest,sources):
    expected={str(relative_path(item['path'])) for item in manifest['dependencies']}
    expected.update(str(relative_path(p)) for p in manifest['generated_sources'])
    if len(sources)!=len(set(sources)) or set(sources)!=expected:
        raise ValueError('DDR hardware filelist differs from exact manifest source set')
    # Revalidate AFTER the external generator, which can rewrite staged files.
    verify_dependencies(output,manifest['dependencies'])
    if 'generated_slice_sha256' in manifest:
        if sha256(output/'rtl/ddrphy/ddr3_test_slice_top_v1_10.v')!=manifest['generated_slice_sha256']:
            raise ValueError('Generated DDR slice hash mismatch')
    return {p:sha256(output/p) for p in sources}


def generate(output):
    output=Path(output).resolve()
    if not output.is_relative_to(BUILD.resolve()):raise ValueError('Generated DDR must stay under build/video')
    output.mkdir(parents=True,exist_ok=False)
    provenance={'status':'running','scope':'Generated IP only; no physical calibration or simulation claim'}
    write_json(output/'provenance.json',provenance)
    try:
        manifest=json.loads((ROOT/'fpga/pg2l100h/ip/video_ddr_manifest.json').read_text(encoding='utf-8'))
        refs=json.loads((ROOT/'fpga/pg2l100h/ip/video_reference_manifest.json').read_text(encoding='utf-8'))
        selected={item['path']:item['sha256'] for item in refs['references']['ddr']['files']}
        source=ROOT/'build/video/vendor/ddr'
        for name,digest in selected.items():
            if sha256(source/name)!=digest:raise ValueError('DDR reference hash mismatch: '+name)
        install=tool('pds_shell').parent.parent
        library=install/str(relative_path(manifest['installed_library_relative']))
        verified=verify_dependencies(library,manifest['dependencies'])
        for relative,path in verified.items():
            dest=output/relative;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,dest)
        for name in ('ddr3_test.idf','ddr3_test.v','ddr3_test_ddrphy_top.v'):
            shutil.copyfile(source/name,output/name)
        log=run_logged([install/'bin/ip_generate.exe','-i',output/'ddr3_test.idf','-disable-syn'],
                       output/'ip_generate.log',cwd=output,timeout=180)
        summary=re.findall(r'Done:\s*(\d+)\s+error\(s\)',log)
        if summary!=['0']:raise RuntimeError('DDR generator did not report exact zero errors')
        for name in ('ddr3_test.v','ddr3_test_ddrphy_top.v'):
            if sha256(output/name)!=selected[name]:raise ValueError('Generated wrapper differs from pinned reference: '+name)
        sources=[str(relative_path(f.attrib['pathname'])) for f in ET.parse(output/'ddr3_test.idf').findall('file_list/source/file')]
        generated_hashes=verify_generated_sources(output,manifest,sources)
        provenance.update(status='pass',sources=generated_hashes,
                          idf_sha256=sha256(output/'ddr3_test.idf'),
                          manifest_sha256=sha256(ROOT/'fpga/pg2l100h/ip/video_ddr_manifest.json'),
                          constraint_policy='Generated pnr FDC contains generic pins; never load it for this board')
    except Exception as error:
        provenance.update(status='fail',reason=str(error));raise
    finally:write_json(output/'provenance.json',provenance)
    return output/'ddr3_test.idf',provenance


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    try:
        path,_=generate(args.output);print('VIDEO_DDR_GENERATE_PASS:',path)
    except (OSError,ValueError,RuntimeError) as error:
        print('VIDEO_DDR_GENERATE_FAIL:',error,file=sys.stderr);raise SystemExit(1)

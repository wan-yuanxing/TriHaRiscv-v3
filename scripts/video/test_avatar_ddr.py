"""DDR-to-sealed-material tests, independent zlib fixtures and immutable inputs."""
import argparse,json,re,sys,zlib
from pathlib import Path
from common import ROOT,fresh_run,input_hashes,run_logged,tool,sha256,write_json

def fixtures(directory,texels,asset=None,corrupt=False,outside=False):
    directory.mkdir(parents=True,exist_ok=True)
    data=asset if asset is not None else bytes(((i*73+(i>>8)*19+(i>>16)*137)^0xa6)&255 for i in range(texels*4))
    if len(data)!=texels*4:raise ValueError('RGBA fixture length')
    (directory/'rgba.bin').write_bytes(data)
    bus=bytearray(data)
    if corrupt:
        # Alter an actual nonzero pixel, leaving the independent admitted CRC.
        index=next(i for i in range(0,len(data),4) if any(data[i:i+4]))
        bus[index]^=1
    if outside:bus[0]^=1
    for name,order,source in [('bus_words','little',bus),('expected_words','big',data)]:
        (directory/(name+'.hex')).write_text(''.join(f'{int.from_bytes(source[i:i+4],order):08x}\n' for i in range(0,len(source),4)),encoding='ascii')
    (directory/'crc.hex').write_text(f'{zlib.crc32(data):08x}\n',encoding='ascii')
    write_json(directory/'fixture.json',dict(bytes=len(data),crc32=zlib.crc32(data),sha256=sha256(directory/'rgba.bin'),format='R G B A ascending byte addresses'))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asset',type=Path,help='Test actual 256x256 RGBA bytes at two pixel ratios and with bad CRC')
    parser.add_argument('--compact',action='store_true',help='Preset-only lossless cache, exact pixels and rejection tests')
    args=parser.parse_args()
    if args.compact and not args.asset:parser.error('--compact requires --asset')
    work=fresh_run('avatar_ddr');latest=ROOT/'build/video/latest_avatar_ddr_component.json'
    result=dict(status='running',directory=work.relative_to(ROOT).as_posix());write_json(latest,result)
    try:
        manifest_path=ROOT/'fpga/pg2l100h/project/video_avatar_ddr.json';m=json.loads(manifest_path.read_text(encoding='utf-8'))
        paths=[ROOT/p for p in m['sources']+m['tests']+m['constraints']]+[manifest_path,ROOT/'scripts/video/test_avatar_ddr.py',ROOT/'scripts/video/common.py']
        paths += [ROOT/'rtl/soc/include/avatar_preset.vh']
        paths += [ROOT/'rtl/video/include/avatar_span_identity.vh']
        span=ROOT/'rtl/video/include/avatar_span_table.vh'
        if span.is_file():paths.append(span)
        asset=None
        if args.asset:
            asset_path=args.asset.resolve();asset=asset_path.read_bytes()
            if len(asset)!=262144:raise ValueError('preset must contain 262144 RGBA bytes')
            paths.append(asset_path);result.update(asset=str(asset_path),asset_sha256=sha256(asset_path))
        result.update(inputs=input_hashes(paths),tools={str(tool(t)):sha256(tool(t)) for t in ('iverilog','vvp')},cases={})
        for t in ('iverilog','vvp'):run_logged([tool(t),'-V'],work/(t+'_version.log'))
        cases=[('tail',68,0,0,12.5),('full_page',65536,0,1,12.5),('ratio',68,0,1,17),('upper_edge',68,0,2,12.5),('minimum',4,0,2,12.5)]
        cases += [(name,68,i,0,12.5) for i,name in enumerate(['lower','upper','unaligned','length','unknown','crc','resp','rid','early_last','missing_last','unknown_data','offline_ar','timeout_r','reset','offline_r','pre_ar_response','offline_after_seal','stray_after_seal','stray_after_failure'],1)]
        if asset is not None:
            cases=[('preset',65536,0,1,12.5),('preset_ratio',65536,0,1,17),('preset_bad_crc',65536,6,1,12.5)]
        if args.compact:
            cases=[('wrong_id',65536,20,1,12.5),('wrong_generation',65536,21,1,12.5),
                   ('wrong_crc',65536,6,1,12.5),('corrupt_payload',65536,22,1,12.5),
                   ('nonzero_outside',65536,23,1,12.5),('preset',65536,0,1,12.5),
                   ('preset_ratio',65536,0,1,17),('reset',65536,14,1,12.5)]
        result['compact_preset']=args.compact
        for name,n,case,page,half in cases:
            cw=work/name;fixtures(cw,n,asset,case==22,case==23);binary=cw/'simulation.vvp'
            run_logged([tool('iverilog'),'-g2012','-Wall','-s',m['test_top'],'-o',binary,
                        '-I',ROOT/'rtl/soc/include','-I',ROOT/'rtl/video/include',
                        f'-P{m["test_top"]}.COMPACT_PRESET={int(args.compact)}',
                        f'-P{m["test_top"]}.TEXELS={n}',f'-P{m["test_top"]}.CASE_ID={case}',f'-P{m["test_top"]}.PAGE={page}',f'-P{m["test_top"]}.PIXEL_HALF={half}',
                        *[ROOT/p for p in m['sources']+m['tests']]],cw/'compile.log')
            log=run_logged([tool('vvp'),binary,'+DIR='+cw.as_posix()],cw/'simulation.log',timeout=180)
            matches=re.findall(r'AVATAR_DDR_PASS (.*)',log)
            if len(matches)!=1:raise RuntimeError('Missing exact pass '+name)
            row={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',matches[0])}
            expected_code=0 if case in (0,14,17,18) else 1 if 1<=case<=5 else 5 if case==6 else 2 if 7<=case<=11 or case==19 else 3 if case in (12,15) else 4 if case==13 else 6
            if args.compact:expected_code=1 if case in (6,20,21) else 5 if case==22 else 7 if case==23 else 0
            if row['code']!=expected_code:raise RuntimeError('Wrong precise result code '+name)
            result['cases'][name]=row
        if result['inputs']!=input_hashes(paths) or any(sha256(p)!=h for p,h in result['tools'].items()):raise RuntimeError('Inputs/tools changed')
        result.update(status='pass',physical_board=False,raw_owner_integrated=False,live_replacement=False,artifacts=input_hashes(p for p in work.rglob('*') if p.is_file()))
    except Exception as error:result.update(status='fail',error=str(error));print(str(error),file=sys.stderr)
    write_json(work/'result.json',result);write_json(latest,result);print('AVATAR_DDR_'+result['status'].upper(),work)
    return 0 if result['status']=='pass' else 1

if __name__=='__main__':raise SystemExit(main())

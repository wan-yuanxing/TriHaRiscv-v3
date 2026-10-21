"""Full-record pixel component suite with independent numerical checking."""
import json
import re
import sys
from common import ROOT, fresh_run, input_hashes, run_logged, sha256, tool, write_json


def main():
    work = fresh_run('record_pixels')
    latest = ROOT / 'build/video/latest_record_pixels_component.json'
    result = dict(status='running', directory=work.relative_to(ROOT).as_posix())
    write_json(latest, result)
    try:
        manifest_path = ROOT / 'fpga/pg2l100h/project/video_record_pixels.json'
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        paths = [ROOT/p for p in manifest['sources'] + manifest['tests'] + manifest['constraints']]
        paths += [manifest_path, ROOT/'scripts/video/test_record_pixels.py', ROOT/'scripts/video/common.py',
                  ROOT/'tb/video/check_record_pixels.py', ROOT/'tb/video/overlay_reference.py',
                  ROOT/'rtl/video/include/video_display.vh', ROOT/'rtl/video/include/video_cfg.vh', ROOT/'config/video_display.json']
        result['inputs'] = input_hashes(paths)
        result['tools'] = {}
        for name in ('iverilog', 'vvp'):
            executable = tool(name)
            result['tools'][str(executable)] = sha256(executable)
            run_logged([executable, '-V'], work/(name+'_version.log'))
        cases = [('normal',80,64,0,12.5,0,0),('ratio',80,64,0,17,0,0),
                 ('tight',80,64,0,12.5,0,1),('header',40,24,1,12.5,0,0),
                 ('asset_key',40,24,2,12.5,0,0),('sample_fault',40,24,3,12.5,0,0),
                 ('reset',40,24,4,12.5,0,0),('unknown',40,24,5,12.5,0,0),
                 ('late_fault',40,24,6,12.5,0,0),('generation_wait',40,24,7,12.5,0,0),
                 ('new_source_asset_wait',40,24,8,12.5,0,0),
                 ('core_fault_pending',40,24,9,12.5,0,0),('same_frame_generation',40,24,10,12.5,0,0),
                 ('sparse',80,64,0,12.5,0,1),('no_primary',80,64,0,12.5,0,0),('full',800,600,0,12.5,1,0)]
        result['cases'] = {}
        for name,width,height,case,half,full,tight in cases:
            directory = work/name
            run_logged([sys.executable, ROOT/manifest['reference'], 'generate', '--directory', directory,
                        '--width', width, '--height', height, '--profile', name if name in ('sparse','no_primary','same_frame_generation') else 'dense'], work/(name+'_generate.log'))
            binary = directory/'simulation.vvp'
            command = [tool('iverilog'), '-g2012', '-Wall', '-I', ROOT/'rtl/video/include',
                       '-s', manifest['test_top'], '-o', binary]
            command += [f'-P{manifest["test_top"]}.{key}={value}' for key,value in
                        [('W',width),('H',height),('CASE_ID',case),('PIXEL_HALF',half),('FULL',full),('TIGHT',tight),('BOX_ONLY',int(name=='no_primary'))]]
            run_logged(command+[ROOT/p for p in manifest['sources']+manifest['tests']], work/(name+'_compile.log'))
            log = run_logged([tool('vvp'),binary,'+DIR='+directory.as_posix()], work/(name+'_simulation.log'),timeout=900)
            matches = re.findall(r'DISPLAY_RECORD_PIXELS_PASS (.*)', log)
            if len(matches)!=1:
                raise RuntimeError('Missing precise RTL pass '+name)
            run_logged([sys.executable,ROOT/manifest['reference'],'check','--directory',directory],work/(name+'_oracle.log'),timeout=900)
            numeric = json.loads((directory/'checked.json').read_text(encoding='utf-8'))
            if numeric['status']!='pass':
                raise RuntimeError('Oracle failed '+name)
            rtl = {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',matches[0])}
            counts = numeric['counts']
            if rtl['pixels']!=counts['pixels'] or rtl['requests']!=counts['requests']:
                raise RuntimeError('Missing/extra observed slots '+name)
            if name in ('normal','ratio','full') and not all(counts[k]>0 for k in ('box','point','avatar')):
                raise RuntimeError('Missing selected feature coverage '+name)
            if name=='sample_fault' and not counts['fault']:
                raise RuntimeError('Missing real sample failure')
            result['cases'][name] = dict(rtl=rtl,oracle=counts)
        if result['inputs']!=input_hashes(paths) or any(sha256(p)!=h for p,h in result['tools'].items()):
            raise RuntimeError('Inputs/tools changed during run')
        result.update(status='pass', actual_raw_owner_integrated=False, material_DDR_integrated=False,
                      global_FREE_verified=False, CPU_NPU_executed=False, physical_board=False,
                      artifacts=input_hashes(p for p in work.rglob('*') if p.is_file()))
    except Exception as error:
        result.update(status='fail',error=str(error));print(str(error),file=sys.stderr)
    write_json(work/'result.json',result);write_json(latest,result)
    print('RECORD_PIXELS_'+result['status'].upper(),work)
    return 0 if result['status']=='pass' else 1


if __name__=='__main__':
    raise SystemExit(main())

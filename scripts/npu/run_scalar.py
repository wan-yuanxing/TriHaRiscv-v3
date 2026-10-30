"""Run scalar arithmetic/component vectors with independent Fraction oracle."""
from pathlib import Path
from datetime import datetime,timezone
import argparse,importlib.util,json,subprocess,sys
from frozen_inputs import FrozenInputs, sha256
ROOT=Path(__file__).resolve().parents[2]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--case');args=parser.parse_args()
    out=ROOT/'build/npu'/datetime.now(timezone.utc).strftime('scalar-%Y%m%dT%H%M%S_%fZ')
    out.mkdir(parents=True)
    result={'status':'RUNNING','directory':str(out),'runs':[],'scope':'scalar client-memory digital test; no CPU, real AXI, PDS or board'}
    try:
        if not __debug__:raise RuntimeError('optimized Python disables oracle checks; PASS is prohibited')
        names=['rtl/npu/npu_scalar_conv.v','tb/npu/operator_oracle.py','tb/npu/tb_npu_scalar_conv.sv',
               'scripts/npu/run_scalar.py','scripts/npu/frozen_inputs.py']
        guard=FrozenInputs(ROOT,out/'inputs',names)
        result['source_sha256']=guard.inputs
        result['external_inputs']=guard.external_inputs
        # The frozen oracle resolves its model sibling relative to inputs/.
        npu=ROOT.parent/'npu_zgtc'
        if (npu/'build/integration_audit/20261020/program.bin').is_file():
            for name in ('yunet/baseline/program_package_manifest_v0_1.json',
                         'build/integration_audit/20261020/program.bin',
                         'build/integration_audit/20261020/parameter_image.bin'):
                guard.external(npu/name,out/'npu_zgtc'/name)
        source=out/'inputs/rtl/npu/npu_scalar_conv.v'
        if not source.exists():raise RuntimeError('npu_scalar_conv is not implemented')
        spec=importlib.util.spec_from_file_location('oracle',out/'inputs/tb/npu/operator_oracle.py');oracle=importlib.util.module_from_spec(spec);spec.loader.exec_module(oracle)
        cases=oracle.emit(out/'vectors')
        for path in (out/'vectors').rglob('*'):
            if path.is_file():guard.track(path)
        result['vectors']=cases
        tools=Path('D:/modeltech64_2020.4/win64')
        result['tools']={}
        for name in ('vlib.exe','vlog.exe','vsim.exe'):
            executable=tools/name;guard.track(executable)
            result['tools'][name]={'path':str(executable),'sha256':sha256(executable)}
        def run(command,name):
            guard.verify()
            try:
                with (out/(name+'.log')).open('w',encoding='utf-8') as log:
                    p=subprocess.run([str(x) for x in command],cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=120)
            finally:guard.verify()
            text=(out/(name+'.log')).read_text(encoding='utf-8')
            if p.returncode: raise RuntimeError(name+' failed: '+text[-2500:])
            return text
        run([tools/'vlib.exe','work'],'vlib')
        run([tools/'vsim.exe','-version'],'version')
        run([tools/'vlog.exe','-sv','-work','work',source,out/'inputs/tb/npu/tb_npu_scalar_conv.sv'],'vlog')
        for case in cases:
            if args.case and case['name']!=args.case:continue
            text=run([tools/'vsim.exe','-c','-onfinish','stop','work.tb_npu_scalar_conv',
                      '+CASE_DIR='+(out/'vectors'/case['name']).as_posix(),'-do','onerror {quit -code 1}; run -all; quit -code 0'],case['name'])
            if text.count('NPU_SCALAR_PASS')!=1 or 'Fatal:' in text:
                raise RuntimeError('scalar simulation missing unique PASS or contains Fatal: '+text[-2500:])
            result['runs'].append(case['name']);print('PASS '+case['name'],flush=True)
        if not result['runs']:raise RuntimeError('no cases run')
        guard.verify();result['source_unchanged']=True;result['status']='PASS'
        result['generated_inputs']=guard.tracked
    except Exception as exc:
        result['status']='FAIL';result['error']=str(exc);print(str(exc),file=sys.stderr)
    result['artifacts_sha256']={str(p.relative_to(out)):sha256(p) for p in out.rglob('*') if p.is_file() and p.suffix in ('.log','.hex','.json')}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(out/'result.json')
    return 0 if result['status']=='PASS' else 1

if __name__=='__main__':raise SystemExit(main())

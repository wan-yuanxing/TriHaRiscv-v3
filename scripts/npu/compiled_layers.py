"""Compile the unchanged Verilog using a run-local native Verilator package."""
from pathlib import Path
import json
import os
import subprocess
import time
from frozen_inputs import sha256


def tool_root(root):
    return Path(os.environ.get('TRIHA_VERILATOR_ROOT',
                str(Path(root)/'build/npu/tools/verilator-5.48.0-win_amd64/verilator'))).resolve()


def build(work, source, harness, verilator_root, compiler):
    work, source, harness = Path(work), Path(source), Path(harness)
    verilator_root, compiler = Path(verilator_root), Path(compiler)
    work.mkdir(parents=True, exist_ok=False)
    frontend = verilator_root / 'bin/verilator_bin.exe'
    include = verilator_root / 'include'
    tracked = [source, harness, frontend, compiler] + sorted(
        p for p in include.rglob('*') if p.is_file())
    before = {str(p):sha256(p) for p in tracked}
    commands = []
    environment = os.environ.copy()
    environment['VERILATOR_ROOT'] = str(verilator_root)
    environment['PATH'] = str(compiler.parent) + os.pathsep + environment.get('PATH','')

    def verify():
        for name,digest in before.items():
            if sha256(name)!=digest:raise RuntimeError('compiled simulation input changed: '+name)

    def run(command, name):
        verify();log=work/(name+'.log');start=time.perf_counter()
        try:
            with log.open('w',encoding='utf-8') as stream:
                result=subprocess.run([str(value) for value in command],cwd=work,env=environment,
                                      stdout=stream,stderr=subprocess.STDOUT,timeout=240)
        finally:verify()
        commands.append({'argv':[str(v) for v in command],'exit_code':result.returncode,
                         'log':str(log),'sha256':sha256(log),'seconds':time.perf_counter()-start})
        if result.returncode:raise RuntimeError(name+' failed: '+log.read_text(encoding='utf-8',errors='replace')[-4000:])

    run([frontend,'--version'],'verilator_version')
    run([compiler,'--version'],'compiler_version')
    obj=work/'obj'
    run([frontend,'--cc','--top-module','npu_scalar_conv','--Mdir',obj,'--Wno-fatal',source],'translate')
    generated={str(p):sha256(p) for p in obj.rglob('*') if p.is_file()}
    binary=work/'npu_layer.exe'
    run([compiler,'-std=c++14','-O3','-pthread','-static','-DVL_TIME_CONTEXT',
         '-I'+str(include),'-I'+str(include/'vltstd'),'-I'+str(obj),
         *sorted(obj.glob('V*.cpp')),include/'verilated.cpp',include/'verilated_threads.cpp',
         harness,'-lpsapi','-o',binary],'compile')
    generated[str(binary)]=sha256(binary)
    tools={'input_'+str(i):{'path':name,'sha256':digest} for i,(name,digest) in enumerate(before.items())}
    result={'binary':str(binary),'tools':tools,'generated':generated,'commands':commands}
    (work/'build.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    return result

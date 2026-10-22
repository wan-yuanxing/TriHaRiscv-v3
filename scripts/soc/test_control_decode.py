"""Actual two-target AXI-Lite traffic and isolated routing mutations."""
from pathlib import Path
import json,re,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/video'))
from common import fresh_run,input_hashes,write_json,tool,sha256,run_logged

def main():
    work=fresh_run('control_decode');latest=ROOT/'build/video/latest_control_decode_component.json'
    result=dict(status='running',directory=work.relative_to(ROOT).as_posix());write_json(latest,result)
    try:
        mp=ROOT/'fpga/pg2l100h/project/video_control_decode.json';m=json.loads(mp.read_text(encoding='utf-8'))
        paths=[ROOT/p for p in m['sources']+m['tests']+m['constraints']]+[mp,Path(__file__),ROOT/'scripts/video/common.py',ROOT/'rtl/video/include/video_capture_v2.vh',ROOT/'rtl/video/include/video_display.vh']
        result.update(inputs=input_hashes(paths),tools={str(tool(t)):sha256(tool(t)) for t in ('iverilog','vvp')},mutations={})
        source=ROOT/m['sources'][0];tb=ROOT/m['tests'][0];original=source.read_text(encoding='utf-8')
        def compile_run(label,src):
            binary=work/(label+'.vvp')
            run_logged([tool('iverilog'),'-g2012','-Wall','-I',ROOT/'rtl/video/include','-s','tb_video_axil_decode','-o',binary,src,tb],work/(label+'_compile.log'))
            run=subprocess.run([str(tool('vvp')),str(binary)],capture_output=True,timeout=30)
            (work/(label+'_simulation.log')).write_bytes(run.stdout+run.stderr)
            return run.returncode,run.stdout.decode('utf-8',errors='replace')
        code,log=compile_run('normal',source)
        if code!=0 or log.count('VIDEO_CONTROL_DECODE_PASS')!=1:
            raise RuntimeError('decoder simulator failed or omitted unique PASS: '+log[-2000:])
        result['counts']={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',log)}
        for name,old,new,expected in [
            ('wrong_target',"decode = 2'd0;","decode = 2'd1;",'DECODE_WRONG_AW_TARGET'),
            ('early_w','write_state == ISSUE && !w_sent','write_state != RESPONSE && w_full','DECODE_W_HOLD'),
            ('wrong_response','m_axi_rdata_i[read_route*32+:32]','m_axi_rdata_i[0+:32]','DECODE_R_HOLD_OR_RESP')]:
            if original.count(old)!=1:raise RuntimeError('mutation source anchor changed: '+name)
            mutant=work/(name+'.v');mutant.write_text(original.replace(old,new),encoding='utf-8',newline='\n')
            code,log=compile_run(name,mutant)
            if code==0 or expected not in log:raise RuntimeError('mutation not rejected: '+name+'\n'+log[-2000:])
            result['mutations'][name]=dict(exit=code,expected=expected)
        if result['inputs']!=input_hashes(paths):raise RuntimeError('control decoder inputs changed')
        if any(sha256(p)!=h for p,h in result['tools'].items()):raise RuntimeError('control decoder tool changed')
        result.update(status='pass',artifacts=input_hashes(p for p in work.iterdir() if p.is_file()))
    except Exception as error:result.update(status='fail',error=str(error));print(error,file=sys.stderr)
    write_json(work/'result.json',result);write_json(latest,result)
    print('VIDEO_CONTROL_DECODE_'+result['status'].upper(),work)
    return 0 if result['status']=='pass' else 1
if __name__=='__main__':raise SystemExit(main())

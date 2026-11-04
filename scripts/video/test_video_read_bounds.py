"""Check the actual arbiter's DDR aperture/page predicate against byte arithmetic."""
from common import ROOT,fresh_run,input_hashes,run_logged,sha256,tool,write_json


def main():
    work=fresh_run('video_read_bounds')
    rtl=ROOT/'rtl/video/video_read_arbiter.sv';tb=ROOT/'tb/video/tb_video_read_bounds.sv'
    tools=[tool('iverilog'),tool('vvp')]
    files=[rtl,tb,ROOT/'scripts/video/test_video_read_bounds.py',ROOT/'scripts/video/common.py']
    result=dict(status='fail',scope='Simulation only',inputs=input_hashes(files),tools={str(p):sha256(p) for p in tools})
    try:
        binary=work/'bounds.vvp'
        run_logged([tools[0],'-g2012','-s','tb_video_read_bounds','-o',binary,rtl,tb],work/'compile.log')
        log=run_logged([tools[1],binary],work/'simulation.log',timeout=180)
        if log.count('VIDEO_READ_BOUNDS_PASS cases=459362')!=1:raise ValueError('Missing bounds proof')
        if input_hashes(files)!=result['inputs']:raise ValueError('Inputs changed')
        result.update(status='pass',cases=459362,artifacts=input_hashes([binary,work/'compile.log',work/'simulation.log']))
    except Exception as error:result['error']=str(error)
    write_json(work/'result.json',result);print(result['status'],work,result.get('error',''))
    return int(result['status']!='pass')


if __name__=='__main__':raise SystemExit(main())

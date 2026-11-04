"""Fast production MMIO, byte-strobe and display-proof control regressions."""
import json,re,sys
from common import ROOT,BUILD,fresh_run,input_hashes,run_logged,tool,sha256,write_json


def main():
    work=fresh_run('display_control_paths')
    result=dict(status='running',directory=work.relative_to(ROOT).as_posix(),cases={},
                scope='Production control components and independent protocol oracles; no physical timing or board acceptance.')
    try:
        names=['rtl/video/video_display_mmio_compact.sv','rtl/video/display_slot_owner.sv',
               'rtl/video/display_record_guard.sv','rtl/video/display_record_link.sv',
               'rtl/video/include/video_display.vh','rtl/video/include/video_cfg.vh',
               'tb/video/tb_video_display_mmio.sv','tb/video/tb_display_shadow_bytes.sv',
               'tb/video/tb_display_record_link.sv','scripts/video/test_display_control_paths.py',
               'scripts/video/common.py']
        paths=[ROOT/n for n in names]
        result['inputs']=input_hashes(paths)
        iv,vvp=tool('iverilog'),tool('vvp')
        result['tools']={str(p):sha256(p) for p in (iv,vvp)}
        tb=(ROOT/'tb/video/tb_video_display_mmio.sv').read_text(encoding='utf-8')
        # The compact implementation serializes 160 record words. Same ABI and
        # response checks; accommodate its documented preparation latency.
        tb=tb.replace('video_display_mmio dut','video_display_mmio_compact #(.ENABLE_LANDMARKS(LANDMARK_PROFILE)) dut')
        tb=tb.replace('waited<80','waited<1000')
        tb=tb.replace('submit(mode,41,0);repeat(25)cycle;','submit(mode,41,0);repeat(400)cycle;')
        tb=tb.replace('#10000000;', '#50000000;')
        mmio_tb=work/'tb_mmio.sv';mmio_tb.write_text(tb,encoding='utf-8')
        tb=(ROOT/'tb/video/tb_display_shadow_bytes.sv').read_text(encoding='utf-8')
        tb=tb.replace('video_display_mmio #','video_display_mmio_compact #')
        byte_tb=work/'tb_bytes.sv';byte_tb.write_text(tb,encoding='utf-8')
        common=[ROOT/'rtl/video'/n for n in ('video_display_mmio_compact.sv','display_record_guard.sv','display_slot_owner.sv')]

        def compile_case(label,top,files,parameters=()):
            binary=work/(label+'.vvp')
            run_logged([iv,'-g2012','-Wall','-I',ROOT/'rtl/video/include','-s',top,*parameters,
                        '-o',binary,*files],work/(label+'_compile.log'))
            return binary

        def run_case(label,binary,args,marker):
            log=run_logged([vvp,binary,*args],work/(label+'.log'),timeout=180)
            lines=[line for line in log.splitlines() if line.startswith(marker)]
            if len(lines)!=1:raise RuntimeError('Missing unique pass '+label)
            result['cases'][label]={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',lines[0])}

        for profile in (1,0):
            label='mmio' if profile else 'rect_mmio'
            binary=compile_case(label,'tb_video_display_mmio',[*common,mmio_tb],
                                [f'-Ptb_video_display_mmio.LANDMARK_PROFILE={profile}'])
            for case in [*range(9),10,11,14]+([] if profile else [12,13]):
                run_case(label+'_'+str(case),binary,['+CASE='+str(case)],'DISPLAY_MMIO_PASS')
        binary=compile_case('bytes','tb_display_shadow_bytes',[*common,byte_tb])
        run_case('bytes',binary,[],'DISPLAY_SHADOW_BYTES_PASS writes=2723 reads=2883')
        for case in range(7):
            label='link_'+str(case)
            binary=compile_case(label,'tb_display_record_link',
                [ROOT/'rtl/video/display_record_link.sv',ROOT/'tb/video/tb_display_record_link.sv'],
                [f'-Ptb_display_record_link.CASE_ID={case}'])
            run_case(label,binary,[],'DISPLAY_RECORD_LINK_PASS')
        if len(result['cases'])!=34 or result['inputs']!=input_hashes(paths):
            raise RuntimeError('Incomplete coverage or changed inputs')
        if any(sha256(p)!=h for p,h in result['tools'].items()):raise RuntimeError('Changed tool')
        result.update(status='pass',artifacts=input_hashes(p for p in work.iterdir() if p.is_file()))
    except Exception as error:result.update(status='fail',error=str(error))
    write_json(work/'result.json',result);write_json(BUILD/'latest_display_control_paths.json',result)
    print('DISPLAY_CONTROL_PATHS_'+result['status'].upper(),work,result.get('error',''),flush=True)
    return 0 if result['status']=='pass' else 1


if __name__=='__main__':raise SystemExit(main())

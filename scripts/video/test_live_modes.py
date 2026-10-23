"""Changing-frame diagnostic mode composition and board tests."""
import argparse
import json
import sys
from common import ROOT,BUILD,fresh_run,input_hashes,write_json,run_logged
from run import simulate

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline',action='store_true')
    args=parser.parse_args()
    work=fresh_run('live_modes')
    result={'status':'running','directory':work.relative_to(ROOT).as_posix(),'cases':[]}
    write_json(BUILD/'latest_live_modes.json',result)
    try:
        names=['rtl/video/'+p for p in ('video_button_debounce.sv','display_mode_control.sv','display_mode_cdc.sv',
               'avatar_texture_cache.sv','avatar_sample_map.sv','display_overlay.sv')]
        names+=['fpga/pg2l100h/rtl/'+('video_demo_mode_output.sv' if args.baseline else 'video_live_mode_output.sv'),
                'tb/video/tb_video_live_mode_output.sv','scripts/video/test_live_modes.py',
                'scripts/video/common.py','scripts/video/run.py','scripts/video/read_board.py','tb/video/test_live_mode_packets.py']
        result['inputs']=input_hashes([ROOT/n for n in names])
        log=simulate(work,'composition','tb_video_live_mode_output',[ROOT/n for n in names if n.endswith('.sv')],
            defines=('LIVE_MODE_DUT=video_demo_mode_output',) if args.baseline else (),timeout=180)
        if log.count('VIDEO_LIVE_MODE_OUTPUT_PASS')!=1:raise RuntimeError('Missing live modes composition PASS')
        result['cases'].append('composition')
        if not args.baseline:
            path=ROOT/'fpga/pg2l100h/project/video_live_mode_board.json'
            board=json.loads(path.read_text(encoding='utf-8'))
            paths=[ROOT/p for p in board['sources']+board['tests']]
            vendor=[ROOT/'build/video/vendor/hdmi'/p for p in board['vendor_sources']]
            result['inputs'].update(input_hashes([path,*paths,*vendor]))
            result['inputs'].update(input_hashes([ROOT/p for p in board['constraints']+[board['pin_reference']]]))
            log=simulate(work,'board',board['test_top'],paths+vendor,[ROOT/'rtl/video/include'],timeout=300)
            if log.count('VIDEO_LIVE_MODE_BOARD_PASS')!=1:raise RuntimeError('Missing live mode board PASS')
            result['cases'].append('board')
            # Prove the retirement check catches early feedback, independently
            # of correct pixel RGB and normal mode request/commit counts.
            original=ROOT/'fpga/pg2l100h/rtl/video_live_mode_output.sv'
            mutant=work/'early_ack.sv'
            text=original.read_text(encoding='utf-8')
            if text.count('.pixel_commit(retire_marker[12])')!=1:raise RuntimeError('Mutation anchor missing')
            mutant.write_text(text.replace('.pixel_commit(retire_marker[12])','.pixel_commit(retire_marker[0])'),encoding='utf-8')
            mutation_sources=[ROOT/n for n in names if n.endswith('.sv') and n!=original.relative_to(ROOT).as_posix()]+[mutant]
            try:
                simulate(work,'early_ack','tb_video_live_mode_output',mutation_sources,timeout=180)
            except RuntimeError as error:
                if 'LIVE_MODE_ACK_BEFORE_VISIBLE_RETIREMENT' not in str(error):raise
            else:raise RuntimeError('Early MODE feedback was incorrectly accepted')
            result['cases'].append('early_ack')
            run_logged([sys.executable,'-m','unittest','discover','-s',ROOT/'tb/video','-p','test_live_mode_packets.py'],work/'packets.log')
            result['cases'].append('packets')
        if input_hashes([ROOT/p for p in result['inputs']])!=result['inputs']:raise RuntimeError('Live mode inputs changed during run')
        result['artifacts']=input_hashes([p for p in work.iterdir() if p.suffix in ('.log','.vvp','.sv')])
        result['status']='pass'
    except Exception as error:result.update(status='fail',error=str(error))
    write_json(work/'result.json',result);write_json(BUILD/'latest_live_modes.json',result)
    print(json.dumps({k:v for k,v in result.items() if k not in ('inputs','artifacts')},ensure_ascii=False))
    return 0 if result['status']=='pass' else 1

if __name__=='__main__':raise SystemExit(main())

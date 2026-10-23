"""Changing-frame end-to-end test; --baseline proves old one-shot limitation."""
import argparse
import json
from common import ROOT, BUILD, fresh_run, input_hashes, write_json, run_logged
import sys
from run import simulate

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', action='store_true')
    parser.add_argument('--full', action='store_true', help='Also run three full 800x600 captures')
    parser.add_argument('--board-only', action='store_true')
    args = parser.parse_args()
    work = fresh_run('live_video')
    result = {'status': 'running', 'directory': str(work.relative_to(ROOT)), 'cases': []}
    write_json(BUILD/'latest_live_video.json', result)
    try:
        manifest = json.loads((ROOT/'fpga/pg2l100h/project/video_raw_board.json').read_text(encoding='utf-8'))
        sources = [ROOT/p for p in manifest['sources'] if not p.startswith('fpga/') and not p.endswith('video_timing.sv')]
        if not args.baseline:
            sources = [p for p in sources if p.name not in ('video_raw_engine.sv', 'video_frame_crc_reader.sv')]
            sources += [ROOT/'rtl/video'/p for p in ('video_memory_scheduler.sv','video_shared_ddr.sv','video_live_engine.sv')]
        sources += [ROOT/'tb/video/models/ddr_native_model.sv', ROOT/'tb/video/models/video_live_memory.sv', ROOT/'tb/video/tb_video_live_engine.sv']
        dependencies=[ROOT/p for p in ('scripts/video/test_live_video.py','scripts/video/run.py','scripts/video/common.py',
            'scripts/video/read_board.py','tb/video/test_live_board_packets.py','rtl/video/include/video_cfg.vh','config/video_cfg.json')]
        result['inputs'] = input_hashes([*sources, *dependencies])
        cases = [('baseline', (), ('LIVE_DUT=video_raw_engine',), ())] if args.baseline else [
            ('delayed', (), (), ()), ('fast', (('DELAYED',0),), (), ()),
            ('source_fault', (), (), ('+CASE=1',)), ('read_stall', (), (), ('+CASE=2',)),
            ('wide', (('W',800),('H',10),('DENSE',1)), (), ())]
        if args.board_only:cases=[]
        if args.full:cases.append(('full', (('W',800),('H',600),('DENSE',1),('PT',40),('PB',40),('TARGET',3),('EPOCHS',1)), (), ()))
        for name, parameters, defines, options in cases:
            log = simulate(work,name,'tb_video_live_engine',sources,[ROOT/'rtl/video/include'],
                           parameters=parameters,defines=defines,run_args=options,timeout=900)
            if log.count('VIDEO_LIVE_ENGINE_PASS') != 1:
                raise RuntimeError('Missing live PASS: '+name)
            result['cases'].append(name)
        if not args.baseline:
            path=ROOT/'fpga/pg2l100h/project/video_live_board.json'
            board=json.loads(path.read_text(encoding='utf-8'))
            paths=[ROOT/p for p in board['sources']+board['tests']]
            vendor=[ROOT/'build/video/vendor/hdmi'/p for p in board['vendor_sources']]
            result['inputs'].update(input_hashes([path,*paths,*vendor]))
            log=simulate(work,'live_board',board['test_top'],paths+vendor,[ROOT/'rtl/video/include'],timeout=300)
            if log.count('VIDEO_LIVE_BOARD_PASS')!=1:raise RuntimeError('Missing live board PASS')
            result['cases'].append('board')
            run_logged([sys.executable,'-m','unittest','discover','-s',ROOT/'tb/video','-p','test_live_board_packets.py'],work/'packets.log')
        if input_hashes([ROOT/p for p in result['inputs']])!=result['inputs']:
            raise RuntimeError('Live verification inputs changed during run')
        result['artifacts']=input_hashes([p for p in work.iterdir() if p.suffix in ('.log','.vvp')])
        result['status'] = 'pass'
    except Exception as error:
        result.update(status='fail',error=str(error))
    write_json(work/'result.json',result)
    write_json(BUILD/'latest_live_video.json', result)
    print(json.dumps({k:result[k] for k in ('status','directory','cases')},ensure_ascii=False))
    if result.get('error'):print(result['error'])
    return 0 if result['status']=='pass' else 1

if __name__=='__main__':
    raise SystemExit(main())

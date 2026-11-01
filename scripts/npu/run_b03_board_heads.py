"""Real two-frame inference using the board NPU profile; no CPU/Video/board claim.

Reuse the admitted upstream native DDR proxy and lease monitors, adapting only
the profile and CPU-post completion ABI. Generated test sources are hash-bound.
"""
import argparse
import json
from pathlib import Path
import re
import sys
import time

import import_b03
import import_b03_tests
from frozen_inputs import FrozenInputs
from run_b03_frame import (ROOT, DEFAULT_ASSETS, DEFAULT_MANIFEST, VENDOR, VENDOR_FILES,
                           _prepare_assets, _simulate, common, digest, need, read_hex_bytes)


def replace_once(text, old, new):
    need(text.count(old) == 1, 'ambiguous upstream test adaptation: ' + old[:70])
    return text.replace(old, new, 1)


def run(output, timeout):
    output.mkdir(parents=True, exist_ok=False)
    result = {'status': 'RUNNING', 'board_verified': False, 'cpu_video_verified': False,
              'profile': {'TRUSTED_MODEL': 1, 'ENABLE_HARDWARE_POST': 0,
                          'M_LANES': 2, 'QUANTIZER_LANES': 1}}
    common.write_json(output/'result.json', result)
    started = time.monotonic()
    try:
        import_b03.verify_import(ROOT)
        tests = import_b03_tests.verify(ROOT)
        prod = (ROOT/import_b03.FILELIST).read_text().splitlines()
        support = [import_b03_tests.DESTINATION+'/'+x['path'] for x in tests['files']]
        names = prod+support+['scripts/npu/run_b03_board_heads.py', 'scripts/npu/run_b03_frame.py',
                              'scripts/npu/frozen_inputs.py', 'scripts/video/common.py',
                              'scripts/npu/import_b03.py', 'rtl/npu/upstream/b03/UPSTREAM.json']
        frozen = FrozenInputs(ROOT, output/'inputs', names)
        vendors = []
        for name in VENDOR_FILES:
            dest = output/'vendor'/name
            frozen.external(VENDOR/name, dest)
            vendors.append(dest)
        vsim = common.tool('vsim')
        frozen.track(vsim)
        cases = ('zero', 'pattern')
        fixture, raw = _prepare_assets(DEFAULT_ASSETS, DEFAULT_MANIFEST, output, cases, frozen)
        testdir = frozen.directory/import_b03_tests.DESTINATION/'Testbench/platform'
        driver = (testdir/'b03_full_frame_payload_driver.svh').read_text()
        driver = replace_once(driver, 'b03_frame_exec_payload frame(',
            'b03_frame_exec_payload #(.TRUSTED_MODEL(1),.ENABLE_HARDWARE_POST(0),.M_LANES(2),.QUANTIZER_LANES(1)) frame(')
        driver = replace_once(driver,
            'if(!frame.table_cache_valid||frame.table_cache_commits!=1)$fatal(1,"input update invalidated unchanged POST table");',
            'if(frame.table_cache_commits!=0)$fatal(1,"CPU-post unexpectedly scanned POST table");')
        driver = replace_once(driver,
            'f_done_faces!=expected_faces||f_done_crc!=expected_crc||',
            'f_done_faces!=0||f_done_crc!=0||')
        driver = replace_once(driver,
            'f_done_result_offset!=task_words[320+:32]||f_done_result_bytes!=128+records_bytes||',
            'f_done_result_offset!=task_words[896+:32]||f_done_result_bytes!=26368||')
        # HEAD bytes and CRC are checked immediately before this range. Only
        # hardware-post record/header readback is replaced by CPU-post checks.
        begin = '        path=$sformatf("%s/records_golden_%0d.hex",root_path,frame_index);'
        end = '        @(negedge compute_clk);done_ready=1;tick;'
        need(driver.count(begin)==driver.count(end)==1, 'post readback boundaries')
        i,j = driver.index(begin),driver.index(end)
        driver = driver[:i]+'''        if(global_commands!=global_dones||recovery_count!=0||fault_count!=0||!f_done_live)
            $fatal(1,"CPU-post outstanding debt or recovery");
        if(table_crc_commands!=0||post_commands!=0||frame.table_cache_commits!=0||held_post!=0)
            $fatal(1,"CPU-post performed hardware POST");
        $display("PASS B03_BOARD_HEADS_PROXY frame=%0d ops=%0d preflights=%0d modelcycles=%0d framecycles=%0d globalcommands=%0d globaldones=%0d CE0reads=%0d CE0dones=%0d headCRC=%h",frame_index,model_ops,preflights,held_model,held_total,global_commands,global_dones,ce0_reads,ce0_dones,~head_crc);
'''+driver[j:]
        driver_path = output/'board_heads_driver.svh'
        driver_path.write_text(driver, encoding='utf-8', newline='\n')
        top = (testdir/'tb_b03_full_frame_payload.sv').read_text()
        top = replace_once(top, '`include "b03_full_frame_payload_driver.svh"',
                           '`include "'+driver_path.as_posix()+'"')
        top = replace_once(top, 'module tb_b03_full_frame_payload;', 'module tb_b03_board_heads;')
        top_path = output/'tb_b03_board_heads.sv'
        top_path.write_text(top, encoding='utf-8', newline='\n')
        frozen.track(top_path); frozen.track(driver_path)
        sources = vendors+[frozen.directory/p for p in prod+support if p.endswith(('.v','.sv'))]+[top_path]
        print('BOARD_HEADS_RUN '+str(output), flush=True)
        row, text = _simulate(output, 'tb_b03_board_heads', fixture, sources, frozen, vsim, timeout, True, True)
        lines = [line for line in text.splitlines() if 'PASS B03_BOARD_HEADS_PROXY ' in line]
        need(len(lines)==2, 'two frames required')
        frames = []
        for index,(case,line) in enumerate(zip(cases,lines)):
            heads = read_hex_bytes(fixture/f'heads_actual_{index}.hex')
            need(heads==raw[f'cases/{case}/heads_golden.bin'], 'independent HEAD byte mismatch')
            metrics = {k:int(v,16 if k.endswith('CRC') else 10) for k,v in re.findall(r'(\w+)=([0-9a-fA-F]+)',line)}
            need(metrics['frame']==index and metrics['ops']==metrics['preflights']==79 and
                 metrics['globalcommands']==metrics['globaldones'], 'frame coverage/debt')
            frames.append({'case':case,'metrics':metrics,'head_sha256':digest(heads)})
        for marker,count in [('TASK',2),('OP',316),('EPOCH',316)]:
            found = re.findall('PASS B03_SHARED_'+marker+r'_STABLE starts=(\d+) ends=(\d+) checks=(\d+) ce0=(\d+)',text)
            need(len(found)==1 and tuple(map(int,found[0][:2]))==(count,count) and
                 min(map(int,found[0][2:]))>0, 'lease coverage '+marker)
        frozen.verify()
        result.update(status='PASS_TWO_FRAME_BOARD_HEADS', frames=frames, simulation=row,
                      source_sha256=frozen.inputs, external_sha256=frozen.external_inputs,
                      tracked_sha256=frozen.tracked)
    except Exception as exc:
        result.update(status='FAIL',error=str(exc))
    result['host_seconds']=time.monotonic()-started
    common.write_json(output/'result.json',result)
    print(result['status']+' '+result.get('error',''),flush=True)
    return int(result['status']!='PASS_TWO_FRAME_BOARD_HEADS')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--timeout',type=int,default=1800)
    args=parser.parse_args()
    sys.exit(run(args.output.resolve(),args.timeout))

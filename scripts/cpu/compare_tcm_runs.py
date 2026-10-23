"""Verify frozen TCM evidence and entire ordered WB/store windows."""
import argparse
import json
from pathlib import Path
from compare_cache_runs import verify_outputs, compare_traces, sha


def compare(baseline, candidate):
    a, b = verify_outputs(baseline), verify_outputs(candidate)
    if a['iterations'] != b['iterations'] or sha(baseline/'firmware.elf') != sha(candidate/'firmware.elf'):
        raise ValueError('TCM firmware changed')
    for directory in [baseline, candidate]:
        firmware = json.loads((directory/'firmware-result.json').read_text(encoding='utf-8-sig'))
        flags = firmware['compiler_flags']
        if '-O2' not in flags or any('flto' in f or f == '-O3' for f in flags):
            raise ValueError('Optimization contract changed')
    traces = compare_traces(baseline,candidate,('tcm.wb.log','tcm.store.log'))
    x,y = a['profile']['cycles'],b['profile']['cycles']
    return dict(status='PASS', scope='RTL short TCM comparison, not board/official score or timing acceptance',
        baseline_directory=str(baseline),candidate_directory=str(candidate),
        baseline_result_sha256=sha(baseline/'result.json'),candidate_result_sha256=sha(candidate/'result.json'),
        firmware_sha256=sha(candidate/'firmware.elf'),iterations=b['iterations'],trace_comparison=traces,
        baseline=a['profile'],candidate=b['profile'],baseline_score=b['iterations']*1e6/x,
        candidate_score=b['iterations']*1e6/y,cycles_saved=x-y,throughput_gain_percent=(x/y-1)*100,
        tcm_short_target_met=b['iterations']*1e6/y>4,actual_postroute_100mhz=False,board_validated=False)


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('baseline',type=Path)
    parser.add_argument('candidate',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    baseline,candidate,output=args.baseline.resolve(),args.candidate.resolve(),args.output.resolve()
    if output.is_relative_to(baseline) or output.is_relative_to(candidate):
        raise ValueError('Do not overwrite frozen evidence')
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text('{"status":"RUNNING"}\n',encoding='utf-8')
    try:
        row=compare(baseline,candidate)
    except Exception as error:
        row=dict(status='FAIL',error=str(error))
    output.write_text(json.dumps(row,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(row['status'],row.get('candidate_score',row.get('error')))
    raise SystemExit(0 if row['status']=='PASS' else 1)

"""Replay the admitted public-port CSR checks, including IALIGN=32 EPC behavior."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import shutil
import sys
from admission_common import ROOT, SIM, sha, save, validate
from run_isa_regression import native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--broken', action='store_true')
    args = parser.parse_args()
    work = ROOT / 'build/cpu' / ('csr-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    row = dict(status='RUNNING', broken=args.broken, input_hashes={}, external_hashes={},
               commands=[], runner_return_code=1,
               scope='Native ModelSim CSR unit test; no timing or board acceptance')
    save(work / 'result.json', row)
    try:
        validate()
        sources = ['rtl/cpu/triha_csr_regfile.v', 'rtl/cpu/triha_csr.v',
                   'tb/cpu/tb_csr_functional.v']
        names = sources + ['rtl/cpu/vendor/src/core/biriscv_defs.v', 'config/cpu_admission.json',
                           'scripts/cpu/run_csr.py', 'scripts/cpu/admission_common.py',
                           'scripts/cpu/run_isa_regression.py', 'scripts/cpu/run_modelsim.do']
        for name in names:
            dest = work / 'src' / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, dest)
            row['input_hashes'][name] = sha(dest)
        commands = [('vsim', ['-version']), ('vmap', ['-c']), ('vlib', ['work']),
                    ('vlog', ['+incdir+' + (work/'src/rtl/cpu/vendor/src/core').as_posix(),
                              *[work/'src'/p for p in sources]]),
                    ('vsim', ['-c', '-onfinish', 'exit', '-voptargs=+acc',
                              '-gCORRUPT_RESULT='+str(int(args.broken)), 'work.tb_csr_functional',
                              '-do', work/'src/scripts/cpu/run_modelsim.do'])]
        for index, (tool, arguments) in enumerate(commands):
            executable = SIM / (tool + '.exe')
            row['external_hashes'][str(executable)] = sha(executable)
            record, output = native(executable, arguments, work, work/(str(index)+'-'+tool+'.log'), 90)
            row['commands'].append(record)
            last = index == len(commands)-1
            if last and args.broken:
                if 'CSR_UNIT_FAIL' not in output or '** Fatal' not in output:
                    raise ValueError('CSR negative did not reach the intended functional check')
                row.update(status='FAIL', negative_rejected=True, runner_return_code=1)
            elif record['return_code'] or record['timed_out'] or '** Error' in output:
                raise ValueError('native CSR tool failed: ' + tool)
            elif last:
                if 'CSR_UNIT_PASS' not in output or 'CSR_UNIT_FAIL' in output:
                    raise ValueError('CSR functional check failed')
                row.update(status='PASS', runner_return_code=0,
                           pass_line=next(x for x in output.splitlines() if 'CSR_UNIT_PASS' in x))
    except Exception as error:
        row.update(status='FAIL', error=str(error), runner_return_code=1)
    finally:
        row['source_unchanged'] = all(sha(ROOT/p)==h and sha(work/'src'/p)==h
                                      for p,h in row['input_hashes'].items())
        row['external_unchanged'] = all(sha(p)==h for p,h in row['external_hashes'].items())
        if not row['source_unchanged'] or not row['external_unchanged']:
            row.update(status='FAIL', error='inputs changed during run', runner_return_code=1)
        row['output_hashes'] = {p.relative_to(work).as_posix():sha(p) for p in work.rglob('*')
                                if p.is_file() and p.name != 'result.json'}
        save(work/'result.json', row)
    print(row['status'], work/'result.json', row.get('error', row.get('pass_line', '')))
    return row['runner_return_code']


if __name__ == '__main__':
    sys.exit(main())

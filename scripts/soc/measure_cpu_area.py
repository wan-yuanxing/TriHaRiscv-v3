"""Measure CPU hierarchy in the board target; no routing, bitstream or programming."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess

from gen_board import ROOT
from run import sha, save
from cpu_area import parse_resources, review_predictor


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--firmware-directory', required=True, type=Path)
    parser.add_argument('--clock-directory', required=True, type=Path)
    parser.add_argument('--pds-shell', type=Path, default=Path('D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe'))
    args = parser.parse_args()
    firmware = args.firmware_directory.resolve()
    pll = args.clock_directory.resolve() / 'ip/cpu_board_pll.v'
    work = ROOT / 'build/soc' / ('cpu-area-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir()
    result = dict(status='RUNNING', stage='map', directory=str(work), input_hashes={}, external_hashes={},
                  output_hashes={}, commands=[], source_unchanged=False, timing_closed=False, programmed=False,
                  scope='CPU-only synthesis hierarchy area in board target; no functional/timing/programming claim')
    save(work / 'result.json', result)
    print('CPU_AREA_RUN', work, flush=True)
    try:
        core = json.loads((ROOT / 'fpga/pg2l100h/project/cpu_core.json').read_text(encoding='utf-8'))
        soc = json.loads((ROOT / 'fpga/pg2l100h/project/cpu_minimal_soc_compact.json').read_text(encoding='utf-8'))
        recipe = json.loads((ROOT / 'fpga/pg2l100h/project/cpu_board.json').read_text(encoding='utf-8'))
        rtl = core['sources'] + soc['sources'] + recipe['sources']
        names = rtl + core['headers'] + soc['headers'] + [recipe['constraints']] + recipe['physical_constraints']
        names += ['config/cpu_board.json', 'config/soc_map.json', 'fpga/pg2l100h/project/cpu_core.json',
                  'fpga/pg2l100h/project/cpu_minimal_soc_compact.json', 'fpga/pg2l100h/project/cpu_board.json',
                  'rtl/cpu/ADAPTATIONS.json', 'rtl/cpu/vendor/UPSTREAM.json',
                  'scripts/soc/measure_cpu_area.py', 'scripts/soc/cpu_area.py']
        for name in sorted(set(names)):
            source, target = ROOT / name, work / 'src' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
            result['input_hashes'][name] = sha(source)
        for name in ('rom.hex', 'sram.hex'):
            source = firmware / name
            (work / name).write_bytes(source.read_bytes())
            result['external_hashes'][str(source)] = sha(source)
        (work / 'ip').mkdir()
        (work / 'ip/cpu_board_pll.v').write_bytes(pll.read_bytes())
        result['external_hashes'][str(pll)] = sha(pll)
        result['external_hashes'][str(args.pds_shell)] = sha(args.pds_shell)

        def tcl(path):
            value = Path(path).as_posix()
            if any(c in value for c in '{}\r\n'):
                raise ValueError('unsupported Tcl path')
            return '{' + value + '}'

        lines = [f"set_arch -family {core['family']} -device {core['device']} -speedgrade {core['speedgrade']} -package {core['package']}"]
        lines += ['add_design ' + tcl(work / 'src' / name) for name in rtl]
        lines += ['add_design ' + tcl(work / 'ip/cpu_board_pll.v')]
        lines += ['add_constraint ' + tcl(work / 'src' / name) for name in [recipe['constraints']] + recipe['physical_constraints']]
        lines += ['compile -top_module triha_cpu_board_top -include_path {' +
                  tcl(work / 'src' / core['include_directory']) + ' ' + tcl(work / 'src/rtl/soc/include') + '}',
                  'synthesize -ads -write_verilog TRUE', 'dev_map -detail']
        script = work / 'area.tcl'
        script.write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
        command = [str(args.pds_shell), '-file', str(script), '-work_dir', str(work), '-project_name', 'cpu_board']
        with (work / 'pds.stdout.log').open('wb') as out, (work / 'pds.stderr.log').open('wb') as err:
            process = subprocess.Popen(command, cwd=work, stdout=out, stderr=err, creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                process.wait(timeout=900)
            except subprocess.TimeoutExpired:
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
                process.wait()
                raise RuntimeError('owned PDS area measurement timed out')
        result['commands'] = [dict(command=command, return_code=process.returncode)]
        log = (work / 'pds.stdout.log').read_text(encoding='utf-8', errors='replace')
        if process.returncode or re.search(r'(?im)^\s*(E:|ERROR[: ]|FATAL[: ])', log):
            raise RuntimeError('PDS area flow failed; inspect actual logs')
        for stage in ('compile', 'synthesize', 'dev_map'):
            if not re.search(r'(?m)^Executing : ' + stage + r'(?: [^\r\n]*)? successfully\.', log):
                raise RuntimeError('missing successful area stage: ' + stage)
        review_predictor((work / 'compile/run.log').read_text(encoding='utf-8'))
        report = work / 'synthesize/triha_cpu_board_top.snr'
        result['cpu_only_resources'] = parse_resources(report.read_text(encoding='utf-8'))
        result['synthesis_report_sha256'] = sha(report)
        result['status'] = 'PASS'
    except Exception as error:
        result.update(status='FAIL', error=str(error))
    finally:
        result['source_unchanged'] = all(sha(ROOT / n) == h for n, h in result['input_hashes'].items())
        result['source_unchanged'] &= all(sha(n) == h for n, h in result['external_hashes'].items())
        if not result['source_unchanged']:
            result.update(status='FAIL', error='area inputs changed')
        result['output_hashes'] = {p.relative_to(work).as_posix(): sha(p) for p in work.rglob('*') if p.is_file() and p != work / 'result.json'}
        result['runner_return_code'] = 0 if result['status'] == 'PASS' else 1
        save(work / 'result.json', result)
    print('CPU_AREA', result['status'], result.get('cpu_only_resources'), work / 'result.json', flush=True)
    return result['runner_return_code']


if __name__ == '__main__':
    raise SystemExit(main())

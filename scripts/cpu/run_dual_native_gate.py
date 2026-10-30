"""Compile/map a frozen SRAM CPU candidate before spending a PNR attempt."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

from prepare_dual_physical import prepare, verify_package


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('simulation', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    work = args.output.resolve()
    prepare(args.simulation, work, io_registers=True)
    verify_package(work)
    lines = (work / 'build.tcl').read_text(encoding='utf-8').splitlines()
    assert sum(line.startswith('pnr ') for line in lines) == 1
    lines = [line for line in lines if not line.startswith(('pnr ', 'report_timing '))]
    assert all(line.split()[0] in {'set_arch', 'add_design', 'add_constraint', 'compile', 'synthesize', 'dev_map'} for line in lines)
    tcl = work / 'native-only.tcl'
    tcl.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    executable = Path('D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe')
    command = [str(executable), '-file', str(tcl), '-work_dir', str(work), '-project_name', 'triha_minimal_soc']
    inputs = {str(path): sha(path) for path in [Path(__file__).resolve(), executable, tcl, work / 'prepared.json']}
    row = dict(status='RUNNING', scope='Fresh compile/synthesize/dev_map; no route or timing acceptance',
               timing_closed=False, input_hashes=inputs, command=command, started_utc=time.time())
    result_path = work / 'native-result.json'

    def save():
        result_path.write_text(json.dumps(row, indent=2) + '\n', encoding='utf-8')

    environment = os.environ.copy()
    temporary = work / 'native-temp'
    temporary.mkdir()
    environment['TEMP'] = environment['TMP'] = str(temporary)
    save()
    print('DUAL_NATIVE_RUN', work, flush=True)
    try:
        with (work / 'native-console.log').open('wb') as log:
            process = subprocess.Popen(command, cwd=work, env=environment, stdout=log, stderr=subprocess.STDOUT)
            row['windows_pid'] = process.pid
            save()
            try:
                row['return_code'] = process.wait(timeout=900)
            except subprocess.TimeoutExpired:
                # Bound only this owned process tree, never any unrelated PDS.
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
                row['return_code'] = process.wait(timeout=30)
                raise RuntimeError('Owned native compilation exceeded 900 seconds')
        verify_package(work)
        log = (work / 'native-console.log').read_text(encoding='utf-8', errors='replace')
        row['stages'] = {stage: bool(re.search(r'(?m)^Executing : ' + stage + r'(?: [^\r\n]*)? successfully\.\s*$', log))
                         for stage in ('compile', 'synthesize', 'dev_map')}
        row['source_unchanged'] = all(sha(Path(path)) == digest for path, digest in inputs.items())
        row['status'] = 'PASS' if row['return_code'] == 0 and row['source_unchanged'] and all(row['stages'].values()) else 'FAIL'
    except Exception as error:
        row.update(status='FAIL', error=str(error))
    finally:
        row['elapsed_seconds'] = round(time.time() - row['started_utc'], 3)
        row['output_hashes'] = {path.relative_to(work).as_posix(): sha(path) for path in work.rglob('*')
                                if path.is_file() and path != result_path and 'native-temp' not in path.parts}
        save()
    print('DUAL_NATIVE', row['status'], flush=True)
    return 0 if row['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())

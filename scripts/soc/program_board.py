"""Volatile CPU Program/Verify. Never opens a COM port or writes Flash."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import socket
import subprocess
import time

from gen_board import ROOT
from run import sha, save

PDS = Path('D:/pango/PDS_2022.2-SP6.4/bin')


def validate_package(directory):
    manifest = json.loads((directory / 'manifest.json').read_text(encoding='utf-8'))
    if manifest.get('status') != 'PASS' or not manifest.get('timing_closed') or manifest.get('target') not in ('cpu_board', 'cpu_coremark'):
        raise ValueError('need a passing 100MHz CPU board package')
    required = {'triha_cpu_board_top.sbit', 'triha_cpu_board_top.smsk', 'review.json', 'result.json'}
    if not required.issubset(manifest['files']):
        raise ValueError('incomplete package')
    for name, digest in manifest['files'].items():
        if Path(name).name != name or sha(directory / name) != digest:
            raise ValueError('package file changed: ' + name)
    if sha(directory / 'triha_cpu_board_top.sbit') != manifest['bitstream_sha256'] or sha(directory / 'triha_cpu_board_top.smsk') != manifest['verify_mask_sha256']:
        raise ValueError('bitstream/mask identity mismatch')
    return manifest


def listening():
    try:
        with socket.create_connection(('127.0.0.1', 65420), timeout=.2):
            return True
    except OSError:
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    args = parser.parse_args()
    package = args.package.resolve()
    manifest = validate_package(package)
    from review_board import review
    if not review(Path(manifest['route_directory']))['timing_closed']:
        raise ValueError('independent route review failed')
    work = ROOT / 'build/soc' / ('board-coremark-program-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir()
    bit = package / 'triha_cpu_board_top.sbit'
    result = dict(status='RUNNING', operation='volatile_cpu_program_verify', directory=str(work),
                  program_script_sha256=sha(Path(__file__)),
                  package=str(package), manifest_sha256=sha(package / 'manifest.json'),
                  bitstream_sha256=sha(bit), verify_mask_sha256=sha(bit.with_suffix('.smsk')),
                  expected_device_id='00602899', programmed=False, verified=False, flash_written=False,
                  serial_port_opened=False, board_coremark_validated=False, restore_video=False,
                  tool_hashes={str(PDS / n): sha(PDS / n) for n in ('cdt_cfg_shell.exe', 'cdt_js.exe')},
                  started_utc=datetime.now(timezone.utc).isoformat())
    save(work / 'result.json', result)
    print('CPU_PROGRAM_RUN', work, flush=True)
    server = None
    try:
        with (work / 'server.log').open('wb') as log:
            if not listening():
                server = subprocess.Popen([str(PDS / 'cdt_js.exe'), '-port', '65420', '-work_dir', str(work)],
                    cwd=work, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
                deadline = time.monotonic() + 5
                while not listening() and server.poll() is None and time.monotonic() < deadline:
                    time.sleep(.1)
                if not listening():
                    raise RuntimeError('JTAG server unavailable')
            path = bit.as_posix()
            if any(c in path for c in '{}\r\n'):
                raise ValueError('unsafe Tcl path')
            script = work / 'program_verify.tcl'
            script.write_text('cfg_connect -ip 127.0.0.1 -port 65420\ncfg_scan_chain\n'
                'set actual_id [cfg_read_device_property -mode 0]\n'
                'if {![string equal -nocase $actual_id {00602899}]} {error "Target ID mismatch"}\n'
                f'cfg_assign_file -file {{{path}}} -device_index 0\n'
                'cfg_program -device_index 0\ncfg_verify -device_index 0\ncfg_disconnect\n', encoding='ascii')
            with (work / 'program_verify.log').open('wb') as log:
                process = subprocess.Popen([str(PDS / 'cdt_cfg_shell.exe'), '-file', str(script), '-work_dir', str(work)],
                    cwd=work, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
                result['programmer_pid'] = process.pid
                save(work / 'result.json', result)
                try:
                    process.wait(timeout=90)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
                    raise RuntimeError('owned CPU programmer timed out')
            text = (work / 'program_verify.log').read_text(encoding='utf-8', errors='replace')
            result.update(native_return_code=process.returncode,
                device_found='PG2L100H' in text and '0x00602899' in text,
                programmed='Executing : cfg_program -device_index 0 successfully.' in text,
                verified='Executing : cfg_verify -device_index 0 successfully.' in text)
            if process.returncode or not all(result[k] for k in ('device_found', 'programmed', 'verified')) or any(line.lstrip().startswith('E:') for line in text.splitlines()):
                raise RuntimeError('Program/Verify failed; see actual log')
            if validate_package(package) != manifest or sha(package / 'manifest.json') != result['manifest_sha256']:
                raise ValueError('package changed during programming')
            result['status'] = 'PASS'
    except Exception as error:
        result.update(status='FAIL', error=str(error))
    finally:
        if server is not None and server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)
        result['finished_utc'] = datetime.now(timezone.utc).isoformat()
        result['output_hashes'] = {p.name: sha(p) for p in work.iterdir() if p.is_file() and p.name != 'result.json'}
        save(work / 'result.json', result)
    print('CPU_PROGRAM', result['status'], work / 'result.json', flush=True)
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())

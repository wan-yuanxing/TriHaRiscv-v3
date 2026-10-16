"""IdentifyPG2L100H, program volatile configuration and verify matching mask."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

from common import BUILD,ROOT,fresh_run,sha256,tool,write_json
from scan_board import listening


def classify_log(log,exit_code):
    identified='PG2L100H' in log and '0x00602899' in log
    programmed='Executing : cfg_program -device_index 0 successfully.' in log
    verified='Executing : cfg_verify -device_index 0 successfully.' in log
    clean=not any(line.lstrip().startswith('E:') for line in log.splitlines())
    return {'device_found':identified,'programmed':programmed,'verified':verified,
            'status':'pass' if identified and programmed and verified and clean and exit_code==0 else 'fail'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target',choices=('video_board_smoke','video_rx_board','video_ddr_bist','video_axi_capture'),required=True)
    parser.add_argument('--start-server',action='store_true')
    args=parser.parse_args()
    work=fresh_run('board_program')
    result={'operation':'volatile_program_and_verify','target':args.target,'status':'running',
            'directory':str(work.relative_to(ROOT)),'programmed':False,'verified':False,
            'picture_observed':False,'flash_written':False}
    write_json(BUILD/'latest_board_program.json',result)
    server=None
    try:
        package_path=BUILD/f'latest_package_{args.target}.json'
        if not package_path.exists():package_path=BUILD/'latest_package.json'
        package=json.loads(package_path.read_text(encoding='utf-8'))
        build=json.loads((ROOT/package['directory']/'manifest.json').read_text(encoding='utf-8'))
        if package['status']!='pass' or build['target']!=args.target or not build['internal_timing_met']:
            raise ValueError('Package is not a successful matching target')
        for name,digest in build['inputs'].items():
            if sha256(ROOT/name)!=digest:raise ValueError('Source changed since build: '+name)
        bit=ROOT/package['directory']/Path(build['artifact']).name
        mask=bit.with_suffix('.smsk')
        if sha256(bit)!=package['bitstream_sha256'] or sha256(mask)!=package['verify_mask_sha256']:
            raise ValueError('Package bitstream/mask hash mismatch')
        result.update(bitstream=str(bit.relative_to(ROOT)),bitstream_sha256=sha256(bit),verify_mask_sha256=sha256(mask))
        directory=tool('pds_shell').parent
        with (work/'server.log').open('w',encoding='utf-8') as out:
            if not listening(65420):
                if not args.start_server:raise RuntimeError('No server; use --start-server')
                server=subprocess.Popen([str(directory/'cdt_js.exe'),'-port','65420','-work_dir',str(work)],
                    cwd=work,stdout=out,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
                deadline=time.monotonic()+5
                while not listening(65420) and time.monotonic()<deadline:time.sleep(.1)
                if not listening(65420):raise RuntimeError('JTAG server did not start')
            # ID command returns Tcl value as well as log text. Abort before
            # assigning any file if scan/ID is not the expected physical target.
            script=work/'program_verify.tcl'
            path=bit.resolve().as_posix()
            if any(ch in path for ch in '{}\r\n'):raise ValueError('Unsupported Tcl file path')
            script.write_text('cfg_connect -ip 127.0.0.1 -port 65420\n'
                'cfg_scan_chain\n'
                'set actual_id [cfg_read_device_property -mode 0]\n'
                'if {![string equal -nocase $actual_id {00602899}]} {error "Target ID mismatch"}\n'
                f'cfg_assign_file -file {{{path}}} -device_index 0\n'
                'cfg_program -device_index 0\ncfg_verify -device_index 0\ncfg_disconnect\n',encoding='ascii')
            with (work/'program_verify.log').open('w',encoding='utf-8') as log:
                process=subprocess.run([str(directory/'cdt_cfg_shell.exe'),'-file',str(script),'-work_dir',str(work)],
                    cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=90)
            log=(work/'program_verify.log').read_text(encoding='utf-8',errors='replace')
            result.update(classify_log(log,process.returncode),log_sha256=sha256(work/'program_verify.log'))
            print('\n'.join(line for line in log.splitlines() if not line.startswith('The Progress:')).encode('ascii',errors='backslashreplace').decode())
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.TimeoutExpired) as error:
        result.update(status='fail',reason=str(error));print(str(error),file=sys.stderr)
    finally:
        if server is not None:
            server.terminate()
            try:server.wait(timeout=5)
            except subprocess.TimeoutExpired:server.kill();server.wait(timeout=5)
        write_json(work/'result.json',result)
        write_json(BUILD/'latest_board_program.json',result)
    print('VIDEO_BOARD_PROGRAM:',result['status'],work)
    return 0 if result['status']=='pass' else 1


if __name__=='__main__':raise SystemExit(main())

"""Program/Verify the separately verified RX observer using volatile JTAG only."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

from common import ROOT,BUILD,fresh_run,sha256,tool,write_json
from program_board import classify_log
from scan_board import listening


def main():
    work=fresh_run('rx_image_probe_program')
    result={'status':'running','target':'video_rx_image_probe','directory':str(work.relative_to(ROOT)),
            'operation':'volatile_program_and_verify','programmed':False,'verified':False,'flash_written':False}
    pointer=BUILD/'latest_rx_image_probe_program.json';write_json(pointer,result);server=None
    try:
        build=json.loads((BUILD/'latest_rx_image_probe_build.json').read_text(encoding='utf-8'))
        tests=json.loads((BUILD/'latest_rx_image_probe_test.json').read_text(encoding='utf-8'))
        assert build['status']=='pass' and build['target']=='video_rx_image_probe' and build['internal_timing_met']
        assert tests['status']=='pass'
        assert all(sha256(ROOT/p)==h for group in (build['inputs'],tests['inputs']) for p,h in group.items())
        review_ref=json.loads((BUILD/'current_rx_image_probe_review_ref.json').read_text(encoding='utf-8'))
        assert sha256(ROOT/review_ref['path'])==review_ref['sha256']
        review=json.loads((ROOT/review_ref['path']).read_text(encoding='utf-8'))
        assert review['status']=='pass' and not review['findings']
        assert all(sha256(ROOT/p)==h for p,h in review['inputs'].items())
        bit=ROOT/build['artifact'];mask=ROOT/build['verify_mask']
        assert mask==bit.with_suffix('.smsk')
        assert sha256(bit)==build['artifact_sha256'] and sha256(mask)==build['verify_mask_sha256']
        package=BUILD/'releases'/('video_rx_image_probe_'+build['artifact_sha256'][:12]);package.mkdir(parents=True,exist_ok=True)
        for source in (bit,mask,ROOT/build['timing_report']):shutil.copyfile(source,package/source.name)
        write_json(package/'manifest.json',build)
        bit=package/bit.name
        result.update(bitstream=str(bit.relative_to(ROOT)),bitstream_sha256=sha256(bit),verify_mask_sha256=sha256(bit.with_suffix('.smsk')),
                      build=str(Path(build['directory'])/'result.json'),tests=str(Path(tests['directory'])/'result.json'),review=review_ref)
        directory=tool('pds_shell').parent
        with (work/'server.log').open('w',encoding='utf-8') as out:
            if not listening(65420):
                server=subprocess.Popen([str(directory/'cdt_js.exe'),'-port','65420','-work_dir',str(work)],cwd=work,
                    stdout=out,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
                deadline=time.monotonic()+5
                while not listening(65420) and time.monotonic()<deadline:time.sleep(.1)
                assert listening(65420),'JTAG server did not start'
            path=bit.resolve().as_posix();assert not any(c in path for c in '{}\r\n')
            script=work/'program_verify.tcl'
            script.write_text('cfg_connect -ip 127.0.0.1 -port 65420\ncfg_scan_chain\n'
                'set actual_id [cfg_read_device_property -mode 0]\n'
                'if {![string equal -nocase $actual_id {00602899}]} {error "Target ID mismatch"}\n'
                f'cfg_assign_file -file {{{path}}} -device_index 0\n'
                'cfg_program -device_index 0\ncfg_verify -device_index 0\ncfg_disconnect\n',encoding='ascii')
            with (work/'program_verify.log').open('w',encoding='utf-8') as log:
                process=subprocess.run([str(directory/'cdt_cfg_shell.exe'),'-file',str(script),'-work_dir',str(work)],
                    cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=90)
            log=(work/'program_verify.log').read_text(encoding='utf-8',errors='replace')
            result.update(classify_log(log,process.returncode),log_sha256=sha256(work/'program_verify.log'))
            print('\n'.join(line for line in log.splitlines() if not line.startswith('The Progress:')))
    except (OSError,ValueError,KeyError,AssertionError,subprocess.TimeoutExpired) as error:
        result.update(status='fail',error=str(error));print(str(error),file=sys.stderr)
    finally:
        if server is not None:
            server.terminate()
            try:server.wait(timeout=5)
            except subprocess.TimeoutExpired:server.kill();server.wait(timeout=5)
        write_json(work/'result.json',result);write_json(pointer,result)
    print('RX_IMAGE_PROBE_PROGRAM',result['status'],work)
    return 0 if result['status']=='pass' else 1


if __name__=='__main__':raise SystemExit(main())

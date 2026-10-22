"""Generate and package a timing-admitted standalone CPU/DDR diagnostic image.

Never scans, programs, accesses a serial port or changes an existing release.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import subprocess

from review_ddr_board import physical
from run_cache import ROOT, sha
from run_ddr_board_route import save, tcl


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--route-dir',type=Path,required=True)
    args=parser.parse_args()
    route=args.route_dir.resolve()
    stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    work=ROOT/'build/cpu'/('ddr-board-package-'+stamp)
    work.mkdir(parents=True)
    record=dict(status='RUNNING',programmed=False,board_validated=False,commands=[],
        input_hashes={},output_hashes={},runner_return_code=None,route_directory=str(route))
    save(work/'result.json',record)
    print('CPU_DDR_PACKAGE_RUN',work,flush=True)
    try:
        reviewed=physical(route)
        if not reviewed['timing_closed'] or reviewed['timing_status']!='PASS':
            raise ValueError('complete post-route timing admission is required')
        terminal=json.loads((route/'result.json').read_text(encoding='utf-8'))
        coremark = terminal.get('firmware_profile') == 'ddr-coremark'
        shared = coremark and terminal.get('placement_base', 0x80000000) == 0x82000000
        if coremark:
            firmware = json.loads((Path(terminal['firmware_directory'])/'result.json').read_text(encoding='utf-8'))
            if firmware['cpu_core_luts'] != reviewed['resources']['u_core']['lut']:
                raise ValueError('UART CPU-only LUT denominator differs from the actual mapped image')
        pds=Path(next(k for k in terminal['external_hashes'] if Path(k).name=='pds_shell.exe'))
        record['input_hashes']={str(Path(__file__).resolve()):sha(__file__),
            str(ROOT/'scripts/cpu/review_ddr_board.py'):sha(ROOT/'scripts/cpu/review_ddr_board.py'),
            str(ROOT/'scripts/cpu/run_ddr_board_route.py'):sha(ROOT/'scripts/cpu/run_ddr_board_route.py'),
            str(pds):terminal['external_hashes'][str(pds)],str(route/'result.json'):sha(route/'result.json')}
        original=route/'place_route/triha_cpu_ddr_board_top_pnr.adf'
        frozen=work/'frozen-pnr.adf'
        shutil.copyfile(original,frozen)
        record['input_hashes'][str(frozen)]=sha(original)
        if sha(frozen)!=sha(original):raise ValueError('routed database copy drift')
        script=work/'bitstream.tcl'
        script.write_text('set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676\n'
            'gen_bit_stream -force_to_run -input_db_file '+tcl(frozen)+' -scbv {High Voltage}\n',
            encoding='utf-8',newline='\n')
        command=[str(pds),'-file',str(script),'-work_dir',str(work),'-project_name','cpu_ddr_board']
        cmd=dict(command=command,return_code=None,timed_out=False)
        record['commands'].append(cmd)
        with (work/'pds.log').open('wb') as output:
            process=subprocess.Popen(command,cwd=work,stdout=output,stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW)
            cmd['windows_pid']=process.pid
            try:process.wait(timeout=180)
            except subprocess.TimeoutExpired:
                cmd['timed_out']=True
                if process.poll() is None:
                    cleanup=subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],
                        capture_output=True,timeout=30,creationflags=subprocess.CREATE_NO_WINDOW)
                    (work/'owned-cleanup.log').write_bytes(cleanup.stdout+cleanup.stderr)
                process.wait(timeout=30)
            cmd['return_code']=process.returncode
        log=(work/'pds.log').read_text(encoding='utf-8',errors='replace')
        if (cmd['timed_out'] or cmd['return_code']!=0 or re.search(r'(?im)^\s*(E:|ERROR:|FATAL:)',log) or
                not re.search(r'(?m)^Executing : gen_bit_stream(?: [^\r\n]*)? successfully\.\s*$',log)):
            raise ValueError('actual bitstream generation failed')
        bit=work/'generate_bitstream/triha_cpu_ddr_board_top.sbit'
        mask=bit.with_suffix('.smsk')
        if not bit.is_file() or not mask.is_file() or min(bit.stat().st_size,mask.stat().st_size)==0:
            raise ValueError('missing bitstream or verification mask')
        # Re-read the complete original physical binding after generation.
        checked=physical(route)
        if checked!=reviewed or not all(Path(p).is_file() and sha(p)==h for p,h in record['input_hashes'].items()):
            raise ValueError('bitstream inputs changed')
        prefix = ('cpu_ddr_coremark_'+('shared_' if shared else 'on_' if terminal['cache_enable'] else 'off_')) if coremark else 'cpu_ddr_board_'
        output=ROOT/'build/soc/releases'/(prefix+sha(bit)[:12])
        output.mkdir(parents=True,exist_ok=False)
        sources={p.name:p for p in [bit,mask,route/'rom.hex',route/'sram.hex',route/'firmware.elf',
            Path(terminal['firmware_directory'])/'firmware.map',
            route/'report_timing/triha_cpu_ddr_board_top.rtr',route/'report_timing/rtr.db',
            route/'src/fpga/pg2l100h/constraints/cpu_ddr_board.fdc']}
        sources['route-result.json']=route/'result.json'
        sources['triha_cpu_ddr_board_top_pnr.adf']=frozen
        if coremark:
            sources['coremark.elf'] = route/'payload/firmware.elf'
            sources['coremark.map'] = route/'payload/firmware.map'
            sources['coremark.bin'] = route/'payload/firmware.bin'
        for name,source in sources.items():
            shutil.copyfile(source,output/name)
            if sha(output/name)!=sha(source):raise ValueError('package copy drift: '+name)
        save(output/'review.json',reviewed)
        readme='''# TriHa CPU DDR diagnostic image

PG2L100H/FBG676/-6. Nominal CPU100MHz, DDR125MHz; actual multi-corner post-route
setup/hold/recovery/removal/pulse width, Gray max-delay and skew all passed.
Six-stage single-issue RV32IM/CSR, BTB/BHT/RAS512/512/4, GShare off.
I/D caches16KiB each, two ways,32B lines; D write-through/no-write-allocate.

Exclusive native DDR owner. No Video/NPU/shared fabric. This diagnostic
overwrites private0x80010000 and shared0x87300000,8192bytes each; it must not
run alongside another native port owner. It also tests changed private code
at0x80001000 with FENCE.I. This firmware is not CoreMark.

N3/N2 reference125MHz, D18 free27MHz, KEY0 C22 active-low, UART C24 115200/8N1.
Expected UART: CPU_DDR_BOOT, then CPU_DDR_PASS private=8192 shared=8192 fence_i=1.
KEY0 reruns the self-test. LED0 heartbeat, LED1 DDR ready, LED2 software PASS,
LED3 hardware/software failure. Digital-model tests passed two full boots;
actual DDR training, PLL operation and board execution remain unverified.

Not programmed or board-tested. Keep the prior deployment unchanged.
Any later board operation requires separate authorization; no Flash writes.
The matching smsk is provided for verification. rtr.db is native PDS XML,
including complete Slow/Fast skew groups; review.json binds it and the text report.
'''
        if coremark:
            readme = '''# TriHa DDR CoreMark image

PG2L100H/FBG676/-6, CPU100MHz, DDR125MHz. Actual multi-corner post-route
setup/hold/recovery/removal/pulse width and complete Gray max-delay/skew passed.
Six-stage single-issue RV32IM/CSR, BTB512/BHT512/RAS4, GShare off.
'''
            readme += 'Paired I/D Cache: '+('ON, 16KiB each, two ways, 32B lines.\n' if terminal['cache_enable'] else 'OFF, compile-time bypass.\n')
            readme += '''
SRAM starts the system, waits for DDR, copies and verifies the exact payload,
executes FENCE.I and enters private DDR0x80000000. Code/data and the16KiB stack
below0x80020000 are in private DDR. No other native DDR owner may run.
The benchmark is CoreMark1.0, GCC15.2-O2/noLTO,5000iterations,2000bytes.
SRAM0x16ff0 holds only the CPU-only LUT denominator, read after timing;
this metadata does not change the off/on loaded DDR benchmark bytes.

UART C24, COM12/115200/8N1/no flow control. KEY0 reruns the workload.
Expected: CPU_DDR_COREMARK_PAYLOAD_PASS, standard CRCs, precise cycle/score
and CoreMark/LUTs, CPU_COREMARK_BOARD_PASS. Raw board capture is required;
this package's generation is not a physical score or official submission.
No instruction-retirement CSR is implemented: do not claim measured board IPC.
Not programmed by this packager. No Flash, shared SoC fabric or Video/NPU.
'''
            if shared:
                readme = readme.replace('enters private DDR0x80000000', 'enters shared uncached DDR0x82000000')
                readme = readme.replace('below0x80020000 are in private DDR', 'below0x82020000 are in shared uncached DDR')
                readme += '\nAll benchmark I/D requests bypass Cache through shared-region attributes.\nCache hardware remains present. This is not same-address compile-time Cache off/on.\n'
            readme += '\nDDR payload base: '+hex(terminal.get('placement_base', 0x80000000))+'\n'
        (output/'README.md').write_text(readme,encoding='utf-8',newline='\n')
        files={p.name:sha(p) for p in output.iterdir() if p.is_file()}
        manifest=dict(status='PASS',target='cpu_ddr_board',firmware_profile='ddr-coremark' if coremark else 'ddr-diagnostic',
            route_directory=str(route),package_work_directory=str(work),timing_closed=True,
            programmed=False,board_validated=False,physical_ddr_training_validated=False,
            bitstream_sha256=sha(bit),verify_mask_sha256=sha(mask),files=files,
            cpu_only_resources=reviewed['resources']['u_core'])
        if coremark:
            manifest.update(cache_enable=terminal['cache_enable'],
                placement_base=terminal.get('placement_base', 0x80000000),
                payload_sha256=sha(route/'payload/firmware.bin'), iterations=5000,
                cache_resources=reviewed['resources']['u_cache'])
        save(output/'manifest.json',manifest)
        record.update(status='PASS',runner_return_code=0,release_directory=str(output),
            release_manifest_sha256=sha(output/'manifest.json'))
    except Exception as error:
        record.update(status='FAIL',runner_return_code=1,error=str(error))
    finally:
        record['output_hashes']={p.relative_to(work).as_posix():sha(p) for p in work.rglob('*')
            if p.is_file() and p.name!='result.json'}
        save(work/'result.json',record)
    print('CPU_DDR_PACKAGE',record['status'],record.get('release_directory',record.get('error','')),flush=True)
    return record['runner_return_code']


if __name__=='__main__':
    raise SystemExit(main())

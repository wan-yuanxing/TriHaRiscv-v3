"""Frozen native implementation of the standalone CPU/DDR board boundary.

Runs the actual PLL and DDR hardware IP, never the digital test substitutes.
Flow success is REVIEW_REQUIRED until independently reviewed final timing.
No bitstream generation, board access, or other process ownership is implied.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

from run_cache import ROOT, sha
from prepare_ddr import materialize
from gen_ddr_board import generate
from review_cache_soc import verify_run


def save(path, row):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(row, indent=2, ensure_ascii=False)+'\n', encoding='utf-8', newline='\n')
    temporary.replace(path)


def tcl(path):
    text = Path(path).resolve().as_posix()
    if any(c in text for c in '{}\n\r'):
        raise ValueError('unsafe Tcl path')
    return '{'+text+'}'


def project():
    name = 'fpga/pg2l100h/project/cpu_ddr_board.json'
    recipe = json.loads((ROOT/name).read_text(encoding='utf-8'))
    base = json.loads((ROOT/recipe['soc_manifest']).read_text(encoding='utf-8'))
    sources = base['sources']+recipe['sources']
    if (recipe['top'] != 'triha_cpu_ddr_board_top' or len(set(sources)) != len(sources) or
            any(not n.endswith('.v') or not n.startswith(('rtl/', 'fpga/')) for n in sources) or
            recipe['pinned_sources'] != ['rtl/video/video_async_fifo.sv', 'rtl/video/axi128_hmic256.sv']):
        raise ValueError('invalid hardware-only CPU DDR manifest')
    return name, recipe, base, sources


def pnr_command(minutes, seed):
    if type(seed) is not int or not 1 <= seed <= 20:
        raise ValueError('placement seed must be an integer in1..20')
    return (f'pnr -action_timeout {minutes} -optimize_multi_corner_timing -fix_hold_violation '
        f'-fix_hold_violation_iterations 5 -gplace_seed {seed} -dump_router_congestion_plot TRUE '
        '-slack_prior_in_global_router TRUE -refineplacement_iteration 40 '
        '-logic_optimize_lut6d_combing_strategy 3 -mode performance -plc_decongestion 1')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--firmware-dir', type=Path, required=True)
    parser.add_argument('--coremark-preflight', type=Path,
        help='One-iteration native DDR preflight matching a full 5000-iteration build')
    parser.add_argument('--map-only', action='store_true', help='Area metadata only; never timing admission')
    parser.add_argument('--placement-seed', type=int, choices=range(1,21), default=1,
        help='One explicit bounded placement comparison; all timing constraints remain unchanged')
    args = parser.parse_args()
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    work = ROOT/'build/cpu'/('ddr-board-route-'+stamp)
    work.mkdir(parents=True)
    started = time.monotonic()
    row = dict(schema_version=1, status='RUNNING', flow_status='RUNNING', timing_closed=False,
        input_hashes={}, external_hashes={}, evidence_hashes={}, frozen_hardware_hashes={}, output_hashes={},
        commands=[], programmed=False, bitstream_generated=False, board_validated=False,
        runner_return_code=None, placement_seed=args.placement_seed, directory=str(work), started_utc=datetime.now(timezone.utc).isoformat())
    print('CPU_DDR_BOARD_ROUTE_RUN', work, flush=True)
    save(work/'result.json', row)

    def heartbeat(stage, process=None):
        save(work/'progress.json', dict(status=row['status'], stage=stage, windows_runner_pid=os.getpid(),
            windows_child_pid=process.pid if process else None,
            actual_command=process.args if process else None,
            heartbeat_utc=datetime.now(timezone.utc).isoformat(), elapsed_seconds=round(time.monotonic()-started, 3)))

    def native(exe, arguments, label, timeout=180):
        command = [str(exe), *[p.as_posix() if isinstance(p, Path) else str(p) for p in arguments]]
        record = dict(command=command, return_code=None, timed_out=False, log=label+'.log')
        row['commands'].append(record)
        row['external_hashes'][str(Path(exe).resolve())] = sha(exe)
        with (work/(label+'.log')).open('wb') as output:
            process = subprocess.Popen(command, cwd=work, stdout=output, stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW)
            record['windows_pid'] = process.pid
            began = time.monotonic()
            heartbeat(label, process)
            while process.poll() is None:
                if time.monotonic()-began > timeout:
                    record['timed_out'] = True
                    killed = subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                        capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW, timeout=30)
                    record['owned_cleanup_return_code'] = killed.returncode
                    (work/(label+'-cleanup.log')).write_bytes(killed.stdout+killed.stderr)
                    process.wait(timeout=30)
                    break
                time.sleep(2)
                heartbeat(label, process)
            record['return_code'] = process.returncode
            record['elapsed_seconds'] = round(time.monotonic()-began, 3)
        save(work/'result.json', row)
        text = (work/(label+'.log')).read_text(encoding='utf-8', errors='replace')
        if process.returncode or record['timed_out']:
            raise RuntimeError(f'{label} returned {process.returncode}; timed_out={record["timed_out"]}')
        return text

    try:
        heartbeat('validation')
        generate(check=True)
        firmware_dir = args.firmware_dir.resolve()
        if args.coremark_preflight:
            from ddr_coremark_review import pair
            firmware, short = pair(firmware_dir, args.coremark_preflight)
            row.update(firmware_profile='ddr-coremark', cache_enable=firmware['cache_enable'],
                placement_base=firmware.get('placement_base', 0x80000000),
                coremark_preflight=str(args.coremark_preflight.resolve()))
            for name in ['result.json', *short['output_hashes']]:
                row['evidence_hashes'][str(args.coremark_preflight.resolve()/name)] = sha(args.coremark_preflight.resolve()/name)
        else:
            firmware = verify_run(firmware_dir)
            if (firmware['test'] != 'boot' or firmware['fault'] != 'none' or not firmware['pinned_unchanged'] or
                    '-O2' not in firmware['compiler_flags'] or '-flto' in firmware['compiler_flags']):
                raise ValueError('need passing unchanged O2 two-boot board simulation')
            sim = (firmware_dir/'simulation.log').read_text(encoding='utf-8')
            if ('CPU_DDR_BOARD_PASS boots=2 tested_private=8192 tested_shared=8192' not in sim or
                    'Errors: 0, Warnings: 0' not in sim):
                raise ValueError('missing complete clean two-boot test')
        row['firmware_directory'] = str(firmware_dir)
        for name in ['result.json', *firmware['output_hashes']]:
            row['evidence_hashes'][str(firmware_dir/name)] = sha(firmware_dir/name)
        for name in ['rom.hex', 'sram.hex', 'firmware.elf']:
            shutil.copyfile(firmware_dir/name, work/name)
        if args.coremark_preflight:
            shutil.copytree(firmware_dir/'payload', work/'payload')
        row['binding'] = materialize(work)
        row['external_hashes'][row['binding']['git']] = row['binding']['git_sha256']
        recipe_name, recipe, base, sources = project()
        config = json.loads((ROOT/recipe['board_config']).read_text(encoding='utf-8'))
        if (config['pnr_action_minutes'], config['outer_seconds'], config['cpu_period_ns']) != (20, 1500, 10.0):
            raise ValueError('unexpected implementation budget/CPU period')
        row['scope'] = recipe['scope']
        names = sources+base['headers']+recipe['headers']+recipe['constraints']+[
            recipe_name, recipe['soc_manifest'], recipe['board_config'],
            'config/cpu_ddr.json', 'config/cpu_board.json', 'config/cpu_toolchain.json', 'config/soc_map.json',
            'fpga/pg2l100h/ip/video_reference_manifest.json', 'fpga/pg2l100h/ip/video_ddr_manifest.json',
            'fpga/pg2l100h/constraints/video_ddr_bist.fdc',
            'rtl/cpu/ADAPTATIONS.json', 'rtl/cpu/CACHE_ADAPTATIONS.json', 'rtl/cpu/vendor/UPSTREAM.json',
            'scripts/cpu/run_ddr_board_route.py', 'scripts/cpu/run_cache.py', 'scripts/cpu/prepare_ddr.py',
            'scripts/cpu/gen_ddr_board.py', 'scripts/cpu/review_cache_soc.py', 'scripts/cpu/compare_cache_runs.py',
            'scripts/soc/board_pll.py', 'scripts/soc/gen_board.py', 'scripts/soc/run.py', 'scripts/soc/gen_config.py',
            'scripts/video/gen_ddr.py', 'scripts/video/common.py', 'scripts/video/prepare_reference.py']
        if args.coremark_preflight:
            names += ['scripts/cpu/ddr_coremark_review.py', 'scripts/cpu/ddr_coremark_firmware.py']
        for name in sorted(set(names)):
            path = Path(name)
            if path.is_absolute() or '..' in path.parts or ':' in name:
                raise ValueError('unsafe project input')
            row['input_hashes'][name] = sha(ROOT/name)
            dest = work/'src'/name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/name, dest)
            if sha(dest) != row['input_hashes'][name]:
                raise ValueError('snapshot changed: '+name)
        # The generator uses its repository-relative ROOT. Its current and
        # snapshot hashes are frozen and rechecked; the output must remain
        # under build/video before copying the complete hardware source set.
        ddr_staging = ROOT/'build/video'/('cpu-ddr-route-ip-'+stamp)
        native(sys.executable, [ROOT/'scripts/video/gen_ddr.py', '--output', ddr_staging], 'ddr-generate', 240)
        ddr = json.loads((ddr_staging/'provenance.json').read_text(encoding='utf-8'))
        if ddr['status'] != 'pass' or len(ddr['sources']) != 74:
            raise ValueError('actual generated DDR filelist admission failed')
        shutil.copytree(ddr_staging, work/'ip/ddr')
        for name, digest in ddr['sources'].items():
            if sha(work/'ip/ddr'/name) != digest:
                raise ValueError('actual DDR source drift: '+name)
        row['ddr_ip_provenance'] = ddr
        # Loading board_pll with its script-directory imports uses only
        # established Windows generators; no additional tool environment.
        sys.path.insert(0, str(ROOT/'scripts/soc'))
        from board_pll import generate as generate_pll
        pll = generate_pll(work/'ip/cpu_pll', native)
        pds = Path(os.environ.get('TRIHA_PDS_SHELL', 'D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe'))
        row['pds_version'] = native(pds, ['-version'], 'pds-version', 30).strip()
        hardware = [work/'src'/n for n in sources]
        hardware += [work/'pinned'/n for n in recipe['pinned_sources']]
        hardware += [pll]+[work/'ip/ddr'/n for n in ddr['sources']]
        if any('/tb/' in p.as_posix() or 'model' in p.name for p in hardware):
            raise ValueError('simulation substitute in hardware filelist')
        frozen = hardware+[work/'src'/n for n in base['headers']+recipe['headers']+recipe['constraints']]
        frozen += [work/'rom.hex', work/'sram.hex', work/'firmware.elf']
        row['frozen_hardware_hashes'] = {p.relative_to(work).as_posix():sha(p) for p in frozen}
        top = recipe['top']
        lines = [f'set_arch -family {base["family"]} -device {base["device"]} -speedgrade {base["speedgrade"]} -package {base["package"]}']
        lines += ['add_design '+tcl(p) for p in hardware]
        lines += ['add_constraint '+tcl(work/'src'/n) for n in recipe['constraints']]
        includes = [work/'src/rtl/soc/include', work/'src/rtl/cpu/vendor/src/core']
        parameters = (' -defined_parameters {CACHE_ENABLE '+str(row['cache_enable'])+'}') if args.coremark_preflight else ''
        lines += [f'compile -system_verilog -top_module {top} -include_path '+'{'+ ' '.join(tcl(p) for p in includes)+'}'+parameters,
            'synthesize -ads -write_verilog TRUE', 'dev_map -detail',
            pnr_command(config['pnr_action_minutes'], args.placement_seed),
            'report_timing -max_path 64 -report_max_skew -report_exception TRUE']
        if args.map_only:
            lines = lines[:-2]
            row['area_only'] = True
        script = work/'build.tcl'
        script.write_text('\n'.join(lines)+'\n', encoding='utf-8', newline='\n')
        row['frozen_hardware_hashes']['build.tcl'] = sha(script)
        save(work/'prepared.json', row)
        row['prepared_sha256'] = sha(work/'prepared.json')
        output = native(pds, ['-file', script, '-work_dir', work, '-project_name', 'cpu_ddr_board'],
            'pds', config['outer_seconds'])
        stages = {}
        for stage in (['compile', 'synthesize', 'dev_map'] if args.map_only else ['compile', 'synthesize', 'dev_map', 'pnr', 'report_timing']):
            stages[stage] = bool(re.search(r'(?m)^Executing : '+stage+r'(?: [^\r\n]*)? successfully\.\s*$', output))
        row['stages'] = stages
        if not all(stages.values()) or re.search(r'(?im)^\s*(?:E:|ERROR:|FATAL:)', output):
            raise RuntimeError('native PDS errors or missing actual stage success')
        if args.map_only:
            row.update(flow_status='MAPPED', status='MAPPED', runner_return_code=0,
                review_required='Area-only native map; no post-route timing or board admission')
            return 0
        report = work/'report_timing'/(top+'.rtr')
        if not report.is_file():
            raise ValueError('missing final route timing report')
        row.update(flow_status='PASS', status='REVIEW_REQUIRED', runner_return_code=2,
            timing_report=str(report), timing_report_sha256=sha(report),
            review_required='All clock/corner setup, hold, recovery, removal, MPW; Gray delay/skew and exception match review')
    except Exception as error:
        row.update(status='FAIL', flow_status='FAIL', error=str(error), runner_return_code=1)
    finally:
        def stable(entries, prefix=Path()):
            return all((prefix/p).is_file() and sha(prefix/p)==h for p,h in entries.items())
        row['source_unchanged'] = stable(row['input_hashes'], ROOT)
        row['external_unchanged'] = stable(row['external_hashes'])
        row['evidence_unchanged'] = stable(row['evidence_hashes'])
        row['hardware_unchanged'] = stable(row['frozen_hardware_hashes'], work)
        if not all(row[k] for k in ['source_unchanged', 'external_unchanged', 'evidence_unchanged', 'hardware_unchanged']):
            row.update(status='FAIL', error='physical implementation binding drift', runner_return_code=1, timing_closed=False)
        row['output_hashes'] = {p.relative_to(work).as_posix():sha(p) for p in work.rglob('*')
            if p.is_file() and p.name not in ['result.json', 'progress.json']}
        row['elapsed_seconds'] = round(time.monotonic()-started, 3)
        row['finished_utc'] = datetime.now(timezone.utc).isoformat()
        save(work/'result.json', row)
        heartbeat('terminal')
    print('CPU_DDR_BOARD_ROUTE', row['status'], row.get('error', ''), flush=True)
    return row['runner_return_code']


if __name__ == '__main__':
    raise SystemExit(main())

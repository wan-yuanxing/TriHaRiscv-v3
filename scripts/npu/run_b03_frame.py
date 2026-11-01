"""Run B03 payload control and actual two-frame MODEL/POST through a native proxy.

No shared DDR arbiter, HMIC model, physical timing, board or 30fps claim.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import time
import zlib

from audit_b03_assets import digest, load_manifest, safe_path
from frozen_inputs import FrozenInputs
import import_b03
import import_b03_tests

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ASSETS = ROOT / 'build/npu/b03_assets_20261030/assets'
DEFAULT_MANIFEST = ROOT / 'model/yunet/upstream/b03_558280b/package_manifest.json'
VENDOR = Path('D:/pango/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
VENDOR_FILES = ('GTP_GRS.v', 'GTP_DRM18K_E1.v', 'GTP_APM_E2.v', 'GTP_RAM32X1DP.v', 'GTP_LUT1.v')
spec = importlib.util.spec_from_file_location('triha_video_common', ROOT / 'scripts/video/common.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)


def need(ok, message):
    if not ok:
        raise ValueError(message)


def checked_asset(root, name, hashes):
    path = safe_path(root, name)
    need(path.is_file(), 'missing asset: ' + name)
    raw = path.read_bytes()
    need(name in hashes and digest(raw) == hashes[name], 'asset SHA mismatch: ' + name)
    return raw


def check_log(text, markers):
    bad = [line for line in text.splitlines() if re.search(r'\b(?:ERROR|FATAL|WARNING)(?=\s|:|!|$)', line, re.I)]
    summaries = re.findall(r'Errors:\s*(\d+),\s*Warnings:\s*(\d+)', text, re.I)
    need(not bad and summaries and all(pair == ('0', '0') for pair in summaries), 'nonclean simulator diagnostics: ' + str(bad[:8]))
    for marker in markers:
        need(marker in text, 'missing PASS marker: ' + marker)
    return {'diagnostics': bad, 'summaries': summaries}


def read_hex_bytes(path):
    words = Path(path).read_text(encoding='ascii').split()
    need(all(re.fullmatch('[0-9a-fA-F]{2}', word) for word in words), 'invalid/unknown output hex byte')
    return bytes(int(word, 16) for word in words)


def verify_result_bytes(heads, result, golden_heads, golden_records, index):
    need(len(heads) == 26368 and heads == golden_heads, 'full HEAD824 byte mismatch')
    need(len(result) >= 128 and len(golden_records) % 32 == 0, 'private result length')
    words = struct.unpack('<32I', result[:128])
    need(zlib.crc32(result[:124]) == words[31], 'private header CRC mismatch')
    need(result[128:] == golden_records and words[11] == len(golden_records) and
         zlib.crc32(result[128:]) == words[12], 'private records bytes/CRC mismatch')
    need(words[:10] == (0x3352504e, 1, 128, 1, 0, 0, 100 + index, 77, 1000 + index, 0),
         'private header identity/status mismatch')
    need(words[10] == len(golden_records) // 32 and words[13] == 0x900080 and
         words[15] == words[29] == words[30] == 0 and words[28] == 1, 'private header count/scope mismatch')
    return {'faces': words[10], 'records_bytes': words[11], 'header_crc32': words[31],
            'records_crc32': words[12], 'head_sha256': digest(heads), 'result_sha256': digest(result)}


def _bytehex(path, raw):
    path.write_text(''.join(f'{byte:02x}\n' for byte in raw), encoding='ascii', newline='\n')


def _prepare_assets(root, manifest_path, output, cases, frozen):
    manifest = load_manifest(manifest_path)
    frozen.track(manifest_path)
    hashes = manifest['files_sha256']
    names = ['program.bin', 'parameter_image.bin', 'post_table.bin', 'heads_init.bin']
    names += [f'cases/{case}/{leaf}.bin' for case in cases for leaf in ('task', 'input', 'heads_golden', 'records_golden')]
    raw = {}
    for name in names:
        raw[name] = checked_asset(root, name, hashes)
        frozen.external(root / name, frozen.directory / 'assets' / name)
    out = output / 'assets'
    out.mkdir()
    task = struct.unpack('<32I', raw[f'cases/{cases[0]}/task.bin'])
    header = struct.unpack('<32I', raw['program.bin'][:128])
    regions = [(task[4], 'program.bin'), (task[6] + header[7], 'parameter_image.bin'),
               (task[8], f'cases/{cases[0]}/input.bin'), (task[28], 'heads_init.bin'), (task[12], 'post_table.bin')]
    uploads = []
    for index, (offset, name) in enumerate(regions):
        _bytehex(out / f'upload_{index}.hex', raw[name])
        uploads.append(f'{offset:08x} {len(raw[name])} upload_{index}.hex\n')
    (out / 'uploads.txt').write_text(str(len(uploads)) + '\n' + ''.join(uploads), encoding='ascii', newline='\n')
    lines = []
    for index, case in enumerate(cases):
        records, heads = raw[f'cases/{case}/records_golden.bin'], raw[f'cases/{case}/heads_golden.bin']
        need(len(records) % 32 == 0 and len(heads) == 26368, 'golden case geometry')
        lines.append(f'{len(records)//32} {zlib.crc32(records):08x} {zlib.crc32(heads):08x}\n')
        for leaf in ('task', 'input', 'heads_golden', 'records_golden'):
            _bytehex(out / f'{leaf}_{index}.hex', raw[f'cases/{case}/{leaf}.bin'])
    (out / 'frame_cases.txt').write_text(str(len(cases)) + '\n' + ''.join(lines), encoding='ascii', newline='\n')
    for path in out.iterdir():
        frozen.track(path)
    return out, raw


def _simulate(output, top, root_arg, sources, frozen, vsim, timeout, full, heads_only=False):
    sim = output / top
    sim.mkdir()
    (sim / 'sources.f').write_text(''.join('"' + p.as_posix() + '"\n' for p in sources), encoding='ascii', newline='\n')
    includes = frozen.directory / import_b03_tests.DESTINATION / 'Testbench/platform'
    fields = ('run_ce frame_index f_debug_stage f_debug_op f_done_valid f_done_status f_done_faces '
              'host_owner compute_epoch f_select_post model_ops preflights global_commands global_dones table_crc_commands').split() if full else ['debug_stage', 'done_valid', 'done_status', 'epoch', 'compute_fault_valid']
    access = ' '.join('+acc=rn+/' + top + '/' + field for field in fields)
    script = ('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nvlib work\n'
              'vlog -sv -mfcu -f sources.f {+incdir+' + includes.as_posix() + '}\n'
              'vsim -voptargs={' + access + '} -t 1ps work.' + top + ' {+ROOT=' + root_arg.as_posix() + '}\n'
              'vcd file trace.vcd\nvcd add ' + ' '.join('/' + top + '/' + field for field in fields) + '\n'
              'run -all\nvcd flush\nquit -code 0 -force\n')
    (sim / 'run.do').write_text(script, encoding='ascii', newline='\n')
    frozen.track(sim / 'sources.f')
    frozen.track(sim / 'run.do')
    frozen.verify()
    command = [str(vsim), '-c', '-do', 'run.do', '-l', 'transcript.log']
    started = time.monotonic()
    with (sim / 'console.log').open('wb') as stream:
        process = subprocess.Popen(command, cwd=sim, stdout=stream, stderr=subprocess.STDOUT,
                                   creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        common.write_json(sim / 'process.json', {'pid': process.pid, 'argv': command, 'started_utc': time.time(), 'timeout_seconds': timeout})
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=30)
            raise ValueError('simulation timeout; partial logs retained: ' + str(sim))
    frozen.verify()
    need(code == 0, 'simulator failed exit=' + str(code) + '; see ' + str(sim / 'console.log'))
    logs = {name: (sim / name).read_text(encoding='utf-8', errors='replace') for name in ('console.log', 'transcript.log')}
    markers = ['PASS B03_FULL_FRAME_PROXY ', 'PASS B03_SHARED_TASK_STABLE ', 'PASS B03_SHARED_OP_STABLE '] if full else [
        'PASS B03_FRAME_LIFETIME cases=6 headerbeats=4' if top.endswith('lifetime') else 'PASS B03_FRAME_ACK_RESET_OVERLAP']
    if heads_only:
        markers[0] = 'PASS B03_BOARD_HEADS_PROXY '
    diagnostics = {name: check_log(text, markers) for name, text in logs.items()}
    trace = sim / 'trace.vcd'
    need(trace.is_file() and trace.stat().st_size > 0, 'simulation trace missing')
    text = trace.read_text(encoding='ascii')
    for field in fields:
        need(re.search(r'\$var\s+\S+\s+\d+\s+\S+\s+' + re.escape(field) + r'(?:\s|\[)', text), 'selected VCD field missing: ' + field)
    return {'top': top, 'host_seconds': time.monotonic() - started, 'simulation_exit_code': code,
            'diagnostics': diagnostics, 'directory': str(sim), 'vcd_sha256': digest(trace.read_bytes())}, logs['console.log']


def run(output, suite, assets=DEFAULT_ASSETS, manifest=DEFAULT_MANIFEST, cases=('zero', 'pattern'), timeout=7200):
    output = Path(output).resolve()
    need(not output.exists(), 'fresh output directory required')
    need(suite in ('control', 'frames'), 'unknown suite')
    need(len(cases) == 2 and len(set(cases)) == 2, 'upstream full-frame lease coverage requires two distinct frames')
    output.mkdir(parents=True)
    common.write_json(output / 'result.json', {'status': 'RUNNING', 'board_verified': False})
    try:
        import_b03.verify_import(ROOT)
        test_manifest = import_b03_tests.verify(ROOT)
        prod = (ROOT / import_b03.FILELIST).read_text(encoding='utf-8').splitlines()
        support = [import_b03_tests.DESTINATION + '/' + row['path'] for row in test_manifest['files']]
        names = prod + support + ['scripts/npu/run_b03_frame.py', 'scripts/npu/frozen_inputs.py', 'scripts/video/common.py']
        frozen = FrozenInputs(ROOT, output / 'inputs_snapshot', names)
        vendor = output / 'vendor_snapshot'
        for leaf in VENDOR_FILES:
            frozen.external(VENDOR / leaf, vendor / leaf)
        vsim = common.tool('vsim')
        frozen.track(vsim)
        version = subprocess.check_output([str(vsim), '-version'], stderr=subprocess.STDOUT).decode(errors='replace').strip()
        sources = [vendor / leaf for leaf in VENDOR_FILES] + [frozen.directory / name for name in prod + support if name.endswith(('.v', '.sv'))]
        report = {'status': 'RUNNING', 'source_commit': import_b03.REVISION, 'suite': suite, 'simulator': str(vsim),
                  'simulator_version': version, 'source_sha256': frozen.inputs, 'external_sha256': frozen.external_inputs,
                  'board_verified': False, 'actual_HMIC': False, 'physical_DDR_verified': False, 'production_release': False}
        if suite == 'control':
            runs = []
            for top in ('tb_b03_payload_lifetime', 'tb_b03_payload_ack_reset'):
                row, _ = _simulate(output, top, output, sources, frozen, vsim, min(timeout, 180), False)
                runs.append(row)
                print('B03_CONTROL_PASS ' + top, flush=True)
            raw = read_hex_bytes(output / 'header.hex')
            need(len(raw) == 128, 'lifetime header length')
            words = struct.unpack('<32I', raw)
            need(zlib.crc32(raw[:124]) == words[31], 'lifetime independent header CRC')
            need(words[:6] == (0x3352504e, 1, 128, 1, 0, 0) and words[6] == words[8] == 105 and
                 words[9] == 0x12345678 and words[10] == words[11] == words[12] == words[15] == words[29] == words[30] == 0 and
                 words[13] == 0x900080 and words[18] == 3 and words[20] == 4, 'lifetime header identity/counts')
            report.update(status='PASS_CONTROL_ONLY', simulations=runs, header_sha256=digest(raw),
                          leaf_completions_injected=True, actual_full_79op_MODEL_POST=False,
                          scope='Actual payload parent lifetime/ACK RTL; successful graph and POST leaf completions injected.')
        else:
            fixture, raw = _prepare_assets(Path(assets), Path(manifest), output, cases, frozen)
            row, text = _simulate(output, 'tb_b03_full_frame_payload', fixture, sources, frozen, vsim, timeout, True)
            lines = [line for line in text.splitlines() if 'PASS B03_FULL_FRAME_PROXY ' in line]
            need(len(lines) == 2, 'two full-frame PASS markers required')
            frames = []
            for index, (case, line) in enumerate(zip(cases, lines)):
                metrics = {k: int(v, 16 if k.endswith('CRC') else 10) for k, v in re.findall(r'(\w+)=([0-9a-fA-F]+)', line)}
                need(metrics['frame'] == index and metrics['ops'] == metrics['preflights'] == 79 and
                     metrics['globalcommands'] == metrics['globaldones'] and metrics['tableCRCcommands'] == (3072 if index == 0 else 0), 'frame coverage/debt/table cache')
                checked = verify_result_bytes(read_hex_bytes(fixture / f'heads_actual_{index}.hex'),
                    read_hex_bytes(fixture / f'result_actual_{index}.hex'), raw[f'cases/{case}/heads_golden.bin'],
                    raw[f'cases/{case}/records_golden.bin'], index)
                need(metrics['faces'] == checked['faces'], 'frame result count')
                frames.append({'case': case, 'metrics': metrics, 'independent_output_check': checked})
            for marker, count in [('TASK', 2), ('OP', 316), ('EPOCH', 316)]:
                found = re.findall('PASS B03_SHARED_' + marker + r'_STABLE starts=(\d+) ends=(\d+) checks=(\d+) ce0=(\d+)', text)
                need(len(found) == 1 and tuple(map(int, found[0][:2])) == (count, count) and min(map(int, found[0][2:])) > 0, 'shared ' + marker + ' lifetime coverage')
            report.update(status='PASS_TWO_FRAME_NATIVE_PROXY', simulations=[row], frames=frames,
                          actual_full_79op_MODEL_POST=True, leaf_completions_injected=False,
                          actual_CDC_session_bridge=True, native_byte_memory_proxy=True,
                          scope='Actual 79-op MODEL plus FPGA POST and CDC/native bridge; native memory is byte proxy; not shared DDR/board.')
        frozen.verify()
        report['tracked_sha256'] = frozen.tracked
        report['host_seconds'] = sum(row['host_seconds'] for row in report['simulations'])
        common.write_json(output / 'result.json', report)
        return report
    except Exception as exc:
        common.write_json(output / 'result.json', {'status': 'FAIL', 'error': str(exc), 'suite': suite,
                                                  'board_verified': False, 'actual_full_79op_MODEL_POST': False})
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=('control', 'frames'), required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--assets', type=Path, default=DEFAULT_ASSETS)
    parser.add_argument('--manifest', type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument('--cases', nargs=2, default=['zero', 'pattern'])
    parser.add_argument('--timeout', type=int, default=7200)
    args = parser.parse_args()
    try:
        result = run(args.output, args.suite, args.assets, args.manifest, args.cases, args.timeout)
        print(json.dumps({'status': result['status'], 'host_seconds': result['host_seconds'], 'output': str(args.output)}))
        return 0
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

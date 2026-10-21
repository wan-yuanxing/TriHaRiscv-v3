"""Live native C <-> actual RTL MMIO, with no injected lifecycle events.

The simulator pauses at RPC boundaries. This verifies function/ownership,
not CPU speed, DDR visibility or real-time hardware throughput.
"""
import argparse
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time
import zlib
from common import ROOT, fresh_run, input_hashes, sha256, tool, write_json
from record_pipeline_reference import fixtures


def relay(command, executable, failure, work, env, timeout):
    events = queue.Queue(maxsize=4096)
    processes = []
    threads = []
    logs = []

    def launch(label, args):
        out = (work / (label + '.log')).open('w', encoding='utf-8', newline='\n')
        err = (work / (label + '_stderr.log')).open('w', encoding='utf-8')
        logs.extend((out, err))
        proc = subprocess.Popen(list(map(str, args)), cwd=ROOT, env=env,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=err, text=True, encoding='ascii', bufsize=1)
        processes.append(proc)

        def read():
            try:
                for line in proc.stdout:
                    out.write(line); out.flush()
                    events.put((label, line.rstrip('\r\n')))
            finally:
                events.put((label, None))
        thread = threading.Thread(target=read, daemon=True)
        threads.append(thread); thread.start()
        return proc

    transcript = (work / 'rpc.log').open('w', encoding='ascii', newline='\n')
    logs.append(transcript)
    pending = None
    host = None
    counts = {}
    passes = {}
    pixel_counts = None
    ended = set()
    deadline = time.monotonic() + timeout
    try:
        sim = launch('rtl', command)
        while len(ended) < 2:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('live RPC wall timeout; pending=' + str(pending))
            try:
                label, line = events.get(timeout=min(remaining, 30))
            except queue.Empty:
                print('PIPELINE_WAIT', work.name, 'pending', pending, flush=True)
                continue
            if line is None:
                ended.add(label)
                if label == 'rtl' and 'rtl' not in passes:
                    raise RuntimeError('RTL exited before PASS; inspect ' + str(work))
                if label == 'host' and 'host' not in passes:
                    raise RuntimeError('C exited before PASS; inspect ' + str(work))
                continue
            if label == 'rtl' and line == 'PIPELINE_RPC_READY':
                if host is not None:
                    raise RuntimeError('duplicate RTL ready')
                host = launch('host', [executable] + (['--failure'] if failure else []))
            elif label == 'host' and line.startswith('RPC '):
                if pending is not None or not re.fullmatch(
                        r'RPC [RWFASVTE] [CDX] [0-9a-f]{8} [0-9a-f]{8}', line):
                    raise RuntimeError('invalid/overlapping C request: ' + line)
                pending = line[4:]
                op, target, _, _ = pending.split()
                if (op in 'RWFAS' and target not in 'CD') or (op in 'VTE' and target != 'X'):
                    raise RuntimeError('bad RPC target')
                counts[op] = counts.get(op, 0) + 1
                transcript.write('C> ' + pending + '\n'); transcript.flush()
                sim.stdin.write(pending + '\n'); sim.stdin.flush()
            elif label == 'rtl' and line.startswith('RPC_REPLY '):
                if pending is None or host is None or not re.fullmatch(r'RPC_REPLY [0-9a-f]{8}', line):
                    raise RuntimeError('unsolicited/invalid RTL response')
                transcript.write('RTL> ' + line + '\n'); transcript.flush()
                host.stdin.write(line + '\n'); host.stdin.flush(); pending = None
            elif line.startswith('VIDEO_RECORD_PIPELINE_' + ('RTL' if label == 'rtl' else 'C') + '_PASS '):
                if label in passes:
                    raise RuntimeError('duplicate PASS')
                passes[label] = line
            elif label == 'rtl' and line.startswith('RECORD_MODE_PIXELS '):
                pixel_counts={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)}
            elif label == 'rtl' and line.startswith('PIPELINE_PROGRESS '):
                print(line, flush=True)
            elif label == 'rtl' and 'rtl' in passes and re.fullmatch(
                    r'.*tb_video_record_pipeline\.sv:\d+: \$finish called at \d+ \(1ps\)', line):
                pass  # Icarus 13 emits this tool diagnostic after $finish.
            else:
                raise RuntimeError('unexpected ' + label + ' output: ' + line)
        if pending is not None or set(passes) != {'host', 'rtl'}:
            raise RuntimeError('incomplete RPC exchange')
        for proc in processes:
            if proc.wait(timeout=10) != 0:
                raise RuntimeError('child process failed')
        for log in logs:
            log.flush()
        if any((work / (label + '_stderr.log')).stat().st_size for label in ('host', 'rtl')):
            raise RuntimeError('nonempty child stderr')
        return dict(rpc_counts=counts, passes=passes,mode_pixels=pixel_counts)
    finally:
        # Only children launched by this runner are stopped.
        for proc in processes:
            if proc.poll() is None:
                proc.terminate()
        for proc in processes:
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill(); proc.wait(timeout=10)
        for thread in threads:
            thread.join(timeout=2)
        for log in logs:
            log.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=['all', 'normal', 'bad_eof', 'corrupt'], default='all')
    parser.add_argument('--timeout', type=int, default=4800)
    args = parser.parse_args()
    work = fresh_run('record_pipeline')
    latest = ROOT / 'build/video/latest_record_pipeline_component.json'
    result = dict(status='running', directory=work.relative_to(ROOT).as_posix())
    write_json(latest, result)
    try:
        import json
        manifest_path = ROOT / 'fpga/pg2l100h/project/video_record_pipeline.json'
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        cc = Path(os.environ.get('TRIHA_HOST_CC', 'D:/Xilinx/Vivado/2018.3/msys64/mingw64/bin/gcc.exe'))
        iv, vvp = tool('iverilog'), tool('vvp')
        names = manifest['sources'] + manifest['tests'] + manifest['constraints'] + [
            'scripts/video/record_pipeline_reference.py','tb/video/check_record_pixels.py','tb/video/overlay_reference.py',
            manifest_path.relative_to(ROOT).as_posix(), 'scripts/video/test_record_pipeline.py',
            'scripts/video/common.py', 'tb/video/test_video_record_pipeline.c',
            'sw/drivers/video_capture.c', 'sw/drivers/video_display.c', 'sw/drivers/video_frame_pool.c',
            'sw/include/video_capture.h', 'sw/include/video_capture_v2.h',
            'sw/include/video_display.h', 'sw/include/video_display_abi.h',
            'sw/include/video_frame_pool.h', 'sw/include/video_cfg.h',
            'rtl/video/include/video_cfg.vh', 'rtl/video/include/video_capture_v2.vh',
            'rtl/video/include/video_display.vh']
        paths = [ROOT / n for n in names]
        result['inputs'] = input_hashes(paths)
        result['tools'] = {str(p): sha256(p) for p in (cc, iv, vvp)}
        env = dict(os.environ)
        env['PATH'] = str(cc.parent) + os.pathsep + str(cc.parents[2] / 'usr/bin') + os.pathsep + env['PATH']

        def run(command, log):
            done = subprocess.run(list(map(str, command)), cwd=ROOT, env=env,
                                  capture_output=True, timeout=120)
            (work / log).write_bytes(done.stdout + done.stderr)
            if done.returncode:
                raise RuntimeError(log + ': ' + (done.stdout + done.stderr).decode(errors='replace')[-3000:])

        for label, path in [('cc', cc), ('iverilog', iv), ('vvp', vvp)]:
            run([path, '--version' if label == 'cc' else '-V'], label + '_version.log')
        executable = work / 'controller.exe'
        run([cc, '-static', '-std=c99', '-O2', '-Wall', '-Wextra', '-Werror', '-I', ROOT / 'sw/include',
             ROOT / 'tb/video/test_video_record_pipeline.c', ROOT / 'sw/drivers/video_capture.c',
             ROOT / 'sw/drivers/video_display.c', ROOT / 'sw/drivers/video_frame_pool.c',
             '-o', executable], 'c_compile.log')
        scenarios = [('bad_eof', 10, 1), ('corrupt', 10, 2), ('normal', 600, 0)]
        result['cases'] = {}
        for label, height, case_id in scenarios:
            if args.case not in ('all', label):
                continue
            case_work = work / label; case_work.mkdir()
            print('RECORD_PIPELINE_FIXTURE',label,flush=True)
            fixtures(case_work,height)
            env['TRIHA_RECORD_FIXTURE']=str(case_work/'record.bin')
            crc = case_work / 'source_crc.hex'
            values = []
            for tag in range(5):
                image = bytes((37*x+19*y+83*c+(x*y >> 3)+tag*43+tag*x) & 255
                              for y in range(height) for x in range(800) for c in range(3))
                values.append(f'{zlib.crc32(image):08x}')
            crc.write_text('\n'.join(values) + '\n', encoding='ascii', newline='\n')
            sim = case_work / 'simulation.vvp'
            run([iv, '-g2012', '-Wall', '-I', ROOT / 'rtl/video/include',
                 '-s', 'tb_video_record_pipeline', '-P', f'tb_video_record_pipeline.H={height}',
                 '-P', f'tb_video_record_pipeline.CASE_ID={case_id}', '-o', sim]
                + [ROOT / p for p in manifest['sources'] + manifest['tests']], label + '_compile.log')
            print('PIPELINE_CASE', label, flush=True)
            result['cases'][label] = relay([vvp, sim, '+CRC=' + crc.as_posix(),'+DIR='+case_work.as_posix()], executable,
                                          case_id != 0, case_work, env, args.timeout)
        if result['inputs'] != input_hashes(paths) or any(sha256(p) != h for p, h in result['tools'].items()):
            raise RuntimeError('inputs/tools changed during run')
        result.update(status='pass', native_C_executed=True, live_RTL_MMIO=True,
                      cpu_executed=False, physical_visibility_verified=False,
                      physical_ingress=False, real_NPU=False,
                      artifacts=input_hashes(p for p in work.rglob('*') if p.is_file()))
    except Exception as error:
        result.update(status='fail', error=str(error)); print(str(error), file=sys.stderr)
    write_json(work / 'result.json', result); write_json(latest, result)
    print('VIDEO_RECORD_PIPELINE_' + result['status'].upper(), work, flush=True)
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())

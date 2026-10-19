"""Explicit frozen native-CPU to Video diagnostic using Windows ModelSim/GCC."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/video'))
from common import BUILD, fresh_run, input_hashes, sha256, tool, write_json
import gen_config
import gen_regs

REVISION = '8a2a07cf02ae758131a0235887ea244b16c5a1f4'
TOP = 'tb_cpu_video_firmware'
OWN = ['config/cpu_video_fixture.json', 'scripts/soc/run_cpu_video.py',
       'tb/soc/test_cpu_video_runner.py', 'tb/soc/tb_cpu_video_firmware.sv',
       'sw/tests/video_control/start.S', 'sw/tests/video_control/link.ld',
       'sw/tests/video_control/main.c']


def safe_relative(value):
    if (not isinstance(value, str) or not value or '\\' in value or ':' in value
            or value.startswith('/') or any(p in ('', '.', '..') for p in value.split('/'))
            or any(ord(c) < 32 for c in value)):
        raise ValueError('unsafe explicit path: ' + repr(value))
    path = PurePosixPath(value)
    if path.is_absolute():
        raise ValueError('unsafe explicit path: ' + value)
    return path


def load_fixture(path=None):
    fixture = json.loads((path or ROOT / OWN[0]).read_text(encoding='utf-8'))
    if fixture['schema_version'] != 1 or fixture['cpu_revision'] != REVISION:
        raise ValueError('fixture must freeze the exact reviewed CPU revision')
    for key in ('cpu_blobs', 'cpu_sources'):
        if not fixture[key] or len(set(fixture[key])) != len(fixture[key]):
            raise ValueError('empty/duplicate explicit CPU paths')
        for value in fixture[key]:
            safe_relative(value)
    if not set(fixture['cpu_sources']) <= set(fixture['cpu_blobs']):
        raise ValueError('CPU compile sources must be exported blobs')
    if fixture['rom'] != {'base': 0, 'bytes': 8192} or fixture['sram'] != {'base': 65536, 'bytes': 32768}:
        raise ValueError('fixture memory contract changed')
    geometry = fixture['test_geometry']
    if geometry != {'width': 30, 'height': 20, 'pad_top': 2, 'pad_bottom': 1} or any(type(x) is not int for x in geometry.values()):
        raise ValueError('diagnostic geometry must exactly match TB and firmware constants')
    return fixture


def git_bytes(*args):
    result = subprocess.run(['git', '-C', str(ROOT), *args], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise RuntimeError('Git object read failed: ' + result.stderr.decode('utf-8', errors='replace'))
    return result.stdout


def export_cpu(fixture, target):
    revision = fixture['cpu_revision']
    if not re.fullmatch('[0-9a-f]{40}', revision):
        raise RuntimeError('missing pinned CPU object: invalid object ID')
    try:
        if git_bytes('cat-file', '-t', revision).strip() != b'commit':
            raise RuntimeError('not a commit')
    except RuntimeError as error:
        raise RuntimeError('missing pinned CPU object ' + revision + '; no HEAD fallback') from error
    target = target.resolve()
    records = []
    for relative in fixture['cpu_blobs']:
        safe_relative(relative)
        entry = git_bytes('ls-tree', revision, '--', relative).decode('utf-8').strip()
        match = re.fullmatch(r'100644 blob ([0-9a-f]{40})\t' + re.escape(relative), entry)
        if not match:
            raise RuntimeError('pinned source is not an explicit ordinary blob: ' + relative)
        blob = match.group(1)
        data = git_bytes('cat-file', 'blob', blob)
        if hashlib.sha1(b'blob ' + str(len(data)).encode('ascii') + b'\0' + data).hexdigest() != blob:
            raise RuntimeError('Git blob hash mismatch: ' + relative)
        output = target / relative
        if not output.resolve().is_relative_to(target):
            raise ValueError('unsafe export destination: ' + relative)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(data)
        records.append({'path': relative, 'git_blob': blob, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
    verify_snapshots(target, records)
    return records


def verify_snapshots(target, records):
    target = target.resolve()
    for record in records:
        safe_relative(record['path'])
        path = target / record['path']
        if not path.resolve().is_relative_to(target) or not path.is_file() or sha256(path) != record['sha256']:
            raise RuntimeError('snapshot changed: ' + record['path'])


def check_generated_headers(root=ROOT):
    for name, generator in (('video_cfg', gen_config), ('video_regs', gen_regs)):
        raw = (root / ('config/' + name + '.json')).read_bytes()
        config = json.loads(raw, object_pairs_hook=gen_regs.unique_object)
        generator.validate(config)
        for relative, text in generator.generated_files(config, hashlib.sha256(raw).hexdigest()).items():
            path = root / relative
            if not path.is_file() or path.read_bytes() != text.encode('utf-8'):
                raise RuntimeError('stale generated header: ' + relative)


def copy_inputs(paths, target, expected):
    records = []
    for relative in sorted(set(paths)):
        safe_relative(relative)
        source = ROOT / relative
        output = target / relative
        if not output.resolve().is_relative_to(target.resolve()):
            raise ValueError('unsafe source snapshot path: ' + relative)
        output.parent.mkdir(parents=True, exist_ok=True)
        data = source.read_bytes()
        if hashlib.sha256(data).hexdigest() != expected[relative]:
            raise RuntimeError('copy differs from frozen input: ' + relative)
        output.write_bytes(data)
        records.append({'path': relative, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
    verify_snapshots(target, records)
    return records


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=('bridge', 'firmware', 'all'), default='all')
    args = parser.parse_args(argv)
    work = fresh_run('cpu_video_firmware')
    latest = BUILD / 'cpu_video_firmware/result.json'
    result = {'status': 'running', 'suite': args.suite, 'root': str(ROOT),
              'directory': work.relative_to(ROOT).as_posix(), 'inputs': {}, 'inputs_after': {},
              'artifacts': {}, 'commands': [], 'runs': [], 'negative_tests': [],
              'scope': 'Digital diagnostic only; no production CPU import, shared fabric/coherency, CPU timing, physical board or bitstream result.'}
    write_json(latest, result)
    source_target = work / 'inputs'
    cpu_target = work / 'cpu_snapshot'
    source_records = []
    cpu_records = []
    tool_records = {}
    generated_inputs = {}

    def verify_all():
        verify_snapshots(source_target, source_records)
        verify_snapshots(cpu_target, cpu_records)
        for name, record in tool_records.items():
            if sha256(record['path']) != record['sha256']:
                raise RuntimeError('tool/model changed: ' + name)
        for relative, digest in generated_inputs.items():
            if sha256(work / relative) != digest:
                raise RuntimeError('generated simulation input changed: ' + relative)
        if result['inputs'] and input_hashes(ROOT / p for p in result['inputs']) != result['inputs']:
            raise RuntimeError('original fixture inputs changed during tool execution')

    def execute(command, name, *, expected_failure=None, timeout=180):
        verify_all()
        command = [str(p) for p in command]
        log = work / (name + '.log')
        command_record = {'argv': command, 'cwd': str(work), 'log': log.name}
        result['commands'].append(command_record)
        try:
            with log.open('w', encoding='utf-8') as stream:
                completed = subprocess.run(command, cwd=work, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
                command_record['exit_code'] = completed.returncode
        finally:
            verify_all()
        text = log.read_text(encoding='utf-8', errors='replace')
        if expected_failure:
            if completed.returncode == 0 or expected_failure not in text or 'CPU_VIDEO_FIRMWARE_PASS' in text:
                raise RuntimeError('negative test was not rejected as expected: ' + name + '\n' + text[-3000:])
            result['negative_tests'].append({'name': name, 'status': 'rejected', 'exit_code': completed.returncode, 'reason': expected_failure, 'log': log.name})
        elif completed.returncode:
            raise RuntimeError(name + ' exit ' + str(completed.returncode) + '\n' + text[-4000:])
        print(name + (' REJECTED' if expected_failure else ' OK'), flush=True)
        return text

    try:
        check_generated_headers()
        fixture = load_fixture()
        if args.suite in ('bridge', 'all'):
            execute([sys.executable, ROOT / 'scripts/video/run.py', '--suite', 'cpu_axil'], 'portable_bridge', timeout=600)
            child = BUILD / 'latest_cpu_axil.json'
            evidence = json.loads(child.read_text(encoding='utf-8'))
            if evidence['status'] != 'pass' or 'cpu_axil' not in evidence['passed']:
                raise RuntimeError('portable bridge child did not pass')
            shutil.copyfile(child, work / 'portable_bridge_result.json')
            result['bridge'] = {'directory': evidence['directory'], 'result_sha256': sha256(child)}
        if args.suite in ('firmware', 'all'):
            mmio_manifest = 'fpga/pg2l100h/project/video_capture_mmio.json'
            mmio = json.loads((ROOT / mmio_manifest).read_text(encoding='utf-8'))
            paths = OWN + mmio['sources'] + ['rtl/soc/cpu_native_axil.v', mmio_manifest,
                'config/video_regs.json', 'config/video_cfg.json',
                'sw/include/video_cfg.h', 'sw/include/video_regs.h',
                'rtl/video/include/video_cfg.vh', 'rtl/video/include/video_regs.vh',
                'scripts/video/common.py', 'scripts/video/gen_config.py', 'scripts/video/gen_regs.py']
            result['inputs'] = input_hashes(ROOT / p for p in set(paths))
            source_records = copy_inputs(paths, source_target, result['inputs'])
            check_generated_headers(source_target)
            cpu_records = export_cpu(fixture, cpu_target)
            result['cpu'] = {'revision': fixture['cpu_revision'], 'git_object_root': str(ROOT),
                             'snapshot_root': 'cpu_snapshot', 'blobs': cpu_records}
            result['source_snapshot'] = {'root': 'inputs', 'files': source_records}
            result['test_geometry'] = fixture['test_geometry']
            result['simulation_memories'] = {key: fixture[key] for key in ('rom', 'sram')}
            primitives = json.loads((cpu_target / 'config/cpu_primitives.json').read_text(encoding='utf-8'))
            vsim = tool('vsim')
            gcc = Path(os.environ.get('TRIHA_RISCV_GCC', fixture['gcc']))
            executables = {'gcc': gcc, 'objcopy': gcc.with_name(gcc.name.replace('gcc.exe', 'objcopy.exe')),
                           'objdump': gcc.with_name(gcc.name.replace('gcc.exe', 'objdump.exe')),
                           'nm': gcc.with_name(gcc.name.replace('gcc.exe', 'nm.exe')),
                           'vsim': vsim, 'vlog': vsim.with_name('vlog.exe'), 'vlib': vsim.with_name('vlib.exe'),
                           'python': Path(sys.executable)}
            for name, path in executables.items():
                if not path.is_file():
                    raise FileNotFoundError('missing installed tool ' + str(path))
                tool_records[name] = {'path': str(path), 'sha256': sha256(path)}
            for model in primitives['simulation_models']:
                if not Path(model['path']).is_file() or sha256(model['path']) != model['sha256']:
                    raise RuntimeError('pinned installed primitive model hash mismatch')
                tool_records[model['module']] = {key: model[key] for key in ('path', 'sha256')}
            result['tools_and_models'] = tool_records
            result['python_version'] = sys.version
            execute([gcc, '--version'], 'gcc_version')
            execute([vsim, '-version'], 'modelsim_version')
            execute([sys.executable, '-m', 'unittest', 'discover', '-s', ROOT / 'tb/soc', '-p', 'test_cpu_video_runner.py', '-v'], 'freeze_contract_tests')
            execute([executables['vlib'], 'work'], 'modelsim_library')
            compile_sources = [cpu_target / p for p in fixture['cpu_sources']]
            compile_sources += [Path(p['path']) for p in primitives['simulation_models']]
            compile_sources += [source_target / p for p in mmio['sources']]
            compile_sources += [source_target / 'rtl/soc/cpu_native_axil.v', source_target / 'tb/soc/tb_cpu_video_firmware.sv']
            execute([executables['vlog'], '-sv', '-mfcu', '-work', 'work',
                     '+incdir+' + (cpu_target / 'rtl/cpu/vendor/src/core').as_posix(),
                     '+incdir+' + (source_target / 'rtl/video/include').as_posix(), *compile_sources], 'modelsim_compile')
            symbols = {}
            for case in range(3):
                elf = work / f'firmware_{case}.elf'
                binary = work / f'firmware_{case}.bin'
                flags = ['-march=rv32i_zicsr', '-mabi=ilp32', '-Os', '-ffreestanding', '-fno-builtin',
                         '-fno-pic', '-fno-pie', '-msmall-data-limit=0', '-mno-relax',
                         '-nostdlib', '-nostartfiles', '-Wall', '-Wextra', '-Werror',
                         '-I' + str(source_target / 'sw/include'), '-DTEST_CASE=' + str(case),
                         '-T', source_target / 'sw/tests/video_control/link.ld',
                         '-Wl,--build-id=none', '-Wl,-Map=' + str(work / f'firmware_{case}.map')]
                execute([gcc, *flags, source_target / 'sw/tests/video_control/start.S',
                         source_target / 'sw/tests/video_control/main.c', '-o', elf], f'gcc_case_{case}')
                generated_inputs[elf.name] = sha256(elf)
                execute([executables['objcopy'], '-O', 'binary', elf, binary], f'objcopy_case_{case}')
                data = binary.read_bytes()
                if len(data) > fixture['rom']['bytes']:
                    raise RuntimeError('firmware exceeds diagnostic ROM')
                binary.write_bytes(data.ljust(fixture['rom']['bytes'], b'\0'))
                generated_inputs[binary.name] = sha256(binary)
                execute([executables['objdump'], '-d', elf], f'disassembly_case_{case}')
                nm = execute([executables['nm'], '-n', elf], f'symbols_case_{case}')
                symbols[case] = {parts[2]: int(parts[0], 16) for line in nm.splitlines()
                                 if len(parts := line.split()) == 3 and re.fullmatch('[0-9a-fA-F]+', parts[0])}
            def simulation(name, dual, case, *, bad=0, no_control=0, rejection=None):
                signature = work / (name + '.signature.hex')
                macro = work / (name + '.do')
                # ModelSim 2020.4 maps $fatal through $finish, so -onfinish exit
                # returns zero for failures too. Only the checked, closed SRAM
                # signature file permits a zero exit from the finish breakpoint.
                macro.write_text('onerror {quit -code 1}\nonbreak {if {[file exists ' + signature.name + ']} {quit -code 0} else {quit -code 2}}\nrun -all\nquit -code 3\n', encoding='utf-8', newline='\n')
                generated_inputs[macro.name] = sha256(macro)
                text = execute([vsim, '-c', '-onfinish', 'stop', 'work.' + TOP,
                    '-gDUAL_ISSUE=' + str(dual), '-gTEST_CASE=' + str(case),
                    '-gBAD_DATA=' + str(bad), '-gNO_CONTROL=' + str(no_control),
                    '+ROM_IMAGE=' + (work / f'firmware_{case}.bin').as_posix(),
                    '+SIGNATURE=' + signature.as_posix(),
                    '-do', macro.as_posix()],
                    name, expected_failure=rejection, timeout=240)
                if rejection:
                    return
                if 'CPU_VIDEO_FIRMWARE_PASS' not in text or not signature.is_file():
                    raise RuntimeError('missing real CPU firmware completion: ' + name)
                words = [int(line, 16) for line in signature.read_text(encoding='utf-8').splitlines()]
                if len(words) != 16 or words[5] != symbols[case]['fault_load_pc'] or words[8] != symbols[case]['fault_store_pc']:
                    raise RuntimeError('SRAM trap PC disagrees with ELF instruction symbols')
                result['runs'].append({'name': name, 'status': 'pass', 'dual_issue': dual, 'case': case,
                    'signature': signature.name, 'signature_words': [f'{x:08x}' for x in words],
                    'marker': next(line.strip('# ') for line in text.splitlines() if 'CPU_VIDEO_FIRMWARE_PASS' in line)})
            simulation('red_no_control', 0, 0, no_control=1, rejection='CPU_VIDEO_FAIL timeout')
            for dual in (0, 1):
                for case in range(3):
                    simulation(f'firmware_dual_{dual}_case_{case}', dual, case)
            simulation('mutant_dma_memory_corruption', 0, 0, bad=1, rejection='raw coverage/gap 0')
            verify_all()
            result['inputs_after'] = input_hashes(ROOT / p for p in result['inputs'])
            result['generated_simulation_inputs'] = generated_inputs
        result['status'] = 'pass'
    except Exception as error:
        result['status'] = 'fail'
        result['error'] = str(error)
        print('CPU_VIDEO_FAIL:', error, file=sys.stderr, flush=True)
    finally:
        if result['inputs']:
            try:
                result['inputs_after'] = input_hashes(ROOT / p for p in result['inputs'])
                if result['inputs_after'] != result['inputs']:
                    result['status'] = 'fail'
                    result['error'] = 'source inputs changed during run'
            except OSError as error:
                result['status'] = 'fail'
                result['error'] = str(error)
        result['artifacts'] = {p.relative_to(work).as_posix(): sha256(p) for p in sorted(work.rglob('*'))
                               if p.is_file() and p != work / 'result.json' and 'work' not in p.relative_to(work).parts}
        write_json(work / 'result.json', result)
        write_json(latest, result)
    print('CPU_VIDEO_' + result['status'].upper() + ' ' + work.relative_to(ROOT).as_posix(), flush=True)
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())

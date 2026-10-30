"""Pinned RV32I CPU -> NPU operator -> byte DDR diagnostic (Windows native)."""
import argparse
from datetime import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
REVISION = 'dc00f801d0b3cf1e40faf32bd799c14b9d6b330e'
TOP = 'tb_cpu_npu_operator'
SOURCES = [
    'rtl/npu/npu_axi128_single.v', 'rtl/npu/npu_operator_mmio.v',
    'rtl/npu/npu_scalar_conv.v', 'rtl/npu/npu_operator_top.v',
    'rtl/soc/cpu_native_axil.v', 'tb/npu/tb_cpu_npu_operator.sv',
]
INPUTS = SOURCES + [
    'rtl/npu/include/npu_regs.vh', 'config/npu_regs.json',
    'scripts/npu/gen_regs.py', 'scripts/npu/run_cpu_operator.py',
    'tb/npu/operator_oracle.py', 'sw/include/npu_regs.h',
    'sw/include/npu_operator.h', 'sw/drivers/npu_operator.c',
    'sw/tests/npu_operator/start.S', 'sw/tests/npu_operator/link.ld',
    'sw/tests/npu_operator/main.c',
]
CASES = ('dense_u8', 'dw_s8', 'dense_s8', 'dense_i16', 'dw_u8', 'tail17', 'stride2', 'no_pad',
         'positive_tie', 'negative_tie', 'shift0', 'shift63', 'frozen_conv0')


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def relative_path(value):
    if not isinstance(value, str) or not value or '\\' in value or ':' in value or value.startswith('/') or any(
            part in ('', '.', '..') for part in value.split('/')):
        raise ValueError('unsafe explicit path ' + repr(value))
    return PurePosixPath(value)


def git_bytes(*args):
    run = subprocess.run(['git', '-C', str(ROOT), *args], stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, check=False)
    if run.returncode:
        raise RuntimeError('pinned Git read failed: ' + run.stderr.decode('utf-8', errors='replace'))
    return run.stdout


def export_cpu(target):
    """Read only exact ordinary Git blobs; never use the dirty CPU checkout."""
    if git_bytes('cat-file', '-t', REVISION).strip() != b'commit':
        raise RuntimeError('missing exact reviewed CPU commit; no HEAD fallback')
    filelist = git_bytes('show', REVISION + ':config/cpu_sources.f').decode('utf-8')
    sources = [line.strip() for line in filelist.splitlines()
               if line.strip() and not line.lstrip().startswith('#')]
    sources = [p for p in sources if p.startswith('rtl/cpu/') and '/tb/' not in p]
    if not sources or len(set(sources)) != len(sources) or 'rtl/cpu/triha_cpu.v' not in sources:
        raise RuntimeError('invalid pinned explicit CPU source list')
    blobs = sources + ['config/cpu_sources.f', 'config/cpu_primitives.json',
                       'rtl/cpu/vendor/src/core/biriscv_defs.v']
    records = []
    for relative in blobs:
        relative_path(relative)
        entry = git_bytes('ls-tree', REVISION, '--', relative).decode('utf-8').strip()
        match = re.fullmatch(r'100644 blob ([0-9a-f]{40})\t' + re.escape(relative), entry)
        if not match:
            raise RuntimeError('pinned input is not ordinary blob: ' + relative)
        blob = match.group(1)
        data = git_bytes('cat-file', 'blob', blob)
        if hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() != blob:
            raise RuntimeError('Git blob content hash mismatch')
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        records.append({'path': relative, 'git_blob': blob, 'sha256': sha256(destination), 'bytes': len(data)})
    return sources, records


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cases', nargs='+', choices=CASES, default=['dense_u8', 'dw_s8'])
    parser.add_argument('--modes', nargs='+', choices=('poll', 'irq'), default=['poll', 'irq'])
    parser.add_argument('--scenario', choices=('all', 'red-no-control', 'red-corruption', 'green'), default='all',
                        help='Individual negative scenarios intentionally return nonzero.')
    args = parser.parse_args(argv)
    work = ROOT / 'build/npu' / ('cpu_operator_' + datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8])
    work.mkdir(parents=True)
    latest = ROOT / 'build/npu/latest_cpu_operator.json'
    result = dict(status='running', directory=work.relative_to(ROOT).as_posix(), cpu_revision=REVISION,
                  commands=[], runs=[], negative_tests=[], inputs={}, inputs_after={},
                  scope='Digital same-clock single-issue diagnostic. Shared byte DDR model and local CPU read port; '
                        'no physical DDR/CDC/coherent system fabric, CPU production import, PDS or board result.')
    write_json(latest, result)
    source_target, cpu_target = work / 'inputs', work / 'cpu_snapshot'
    source_records, cpu_records, tools, generated, external = [], [], {}, {}, []

    def verify_all():
        for target, records in ((source_target, source_records), (cpu_target, cpu_records)):
            for record in records:
                if sha256(target / record['path']) != record['sha256']:
                    raise RuntimeError('frozen source changed: ' + record['path'])
        for relative, digest in result['inputs'].items():
            if sha256(ROOT / relative) != digest:
                raise RuntimeError('original source changed during run: ' + relative)
        for name, record in tools.items():
            if sha256(record['path']) != record['sha256']:
                raise RuntimeError('tool/model changed: ' + name)
        for relative, digest in generated.items():
            if sha256(work / relative) != digest:
                raise RuntimeError('generated input changed: ' + relative)
        for record in external:
            if sha256(record['source']) != record['sha256'] or sha256(work / record['snapshot']) != record['sha256']:
                raise RuntimeError('frozen model input changed: ' + record['source'])

    def execute(command, name, timeout=240):
        verify_all()
        command = [str(value) for value in command]
        record = {'argv': command, 'cwd': str(work), 'log': name + '.log'}
        result['commands'].append(record)
        try:
            with (work / record['log']).open('w', encoding='utf-8') as stream:
                completed = subprocess.run(command, cwd=work, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
                record['exit_code'] = completed.returncode
        finally:
            verify_all()
        text = (work / record['log']).read_text(encoding='utf-8', errors='replace')
        return completed.returncode, text

    def checked(command, name):
        code, text = execute(command, name)
        if code:
            raise RuntimeError(name + ' exit ' + str(code) + '\n' + text[-5000:])
        print(name + ' OK', flush=True)
        return text

    def freeze_generated(path):
        generated[path.relative_to(work).as_posix()] = sha256(path)

    try:
        if not __debug__:
            raise RuntimeError('optimized Python disables oracle checks; PASS is prohibited')
        result['inputs'] = {p: sha256(ROOT / p) for p in INPUTS}
        for relative, digest in result['inputs'].items():
            relative_path(relative)
            destination = source_target / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((ROOT / relative).read_bytes())
            if sha256(destination) != digest:
                raise RuntimeError('snapshot changed while copying')
            source_records.append({'path': relative, 'sha256': digest, 'bytes': destination.stat().st_size})
        cpu_sources, cpu_records = export_cpu(cpu_target)
        result['source_snapshot'] = {'root': 'inputs', 'files': source_records}
        result['cpu'] = {'revision': REVISION, 'snapshot_root': 'cpu_snapshot', 'blobs': cpu_records}
        gcc = Path(os.environ.get('TRIHA_RISCV_GCC', 'D:/AI_Tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe'))
        vsim = Path(os.environ.get('TRIHA_VSIM', 'D:/modeltech64_2020.4/win64/vsim.exe'))
        executables = dict(gcc=gcc, objcopy=gcc.with_name('riscv-none-elf-objcopy.exe'),
                           objdump=gcc.with_name('riscv-none-elf-objdump.exe'),
                           nm=gcc.with_name('riscv-none-elf-nm.exe'), vsim=vsim,
                           vlog=vsim.with_name('vlog.exe'), vlib=vsim.with_name('vlib.exe'), python=Path(sys.executable))
        primitives = json.loads((cpu_target / 'config/cpu_primitives.json').read_text(encoding='utf-8'))['simulation_models']
        for name, path in executables.items():
            tools[name] = {'path': str(path), 'sha256': sha256(path)}
        for model in primitives:
            if sha256(model['path']) != model['sha256']:
                raise RuntimeError('pinned primitive hash mismatch: ' + model['module'])
            tools[model['module']] = {'path': model['path'], 'sha256': model['sha256']}
        result['tools_and_models'] = tools
        result['python_version'] = sys.version
        checked([sys.executable, source_target / 'scripts/npu/gen_regs.py', '--check'], 'generated_headers')
        checked([gcc, '--version'], 'gcc_version')
        checked([vsim, '-version'], 'modelsim_version')
        checked([executables['vlib'], 'work'], 'modelsim_library')
        checked([executables['vlog'], '-sv', '-mfcu', '-work', 'work',
                 '+incdir+' + (cpu_target / 'rtl/cpu/vendor/src/core').as_posix(),
                 '+incdir+' + (source_target / 'rtl/npu/include').as_posix(),
                 *[cpu_target / p for p in cpu_sources], *[p['path'] for p in primitives],
                 *[source_target / p for p in SOURCES]], 'modelsim_compile')
        spec = importlib.util.spec_from_file_location('frozen_operator_oracle', source_target / 'tb/npu/operator_oracle.py')
        oracle = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(oracle)
        vectors = work / 'vectors'
        vectors.mkdir()
        manifest = oracle.emit(vectors)
        if 'frozen_conv0' in args.cases:
            # The source checkout is not used by simulation. Copy and freeze
            # all three reviewed model artifacts before constructing vectors.
            model_source = ROOT.parent / 'npu_zgtc'
            model_snapshot = work / 'frozen_model'
            for relative in ('yunet/baseline/program_package_manifest_v0_1.json',
                             'build/integration_audit/20261020/program.bin',
                             'build/integration_audit/20261020/parameter_image.bin'):
                source = model_source / relative
                destination = model_snapshot / relative
                digest = sha256(source)
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(source.read_bytes())
                if sha256(destination) != digest:
                    raise RuntimeError('model artifact changed while copying')
                external.append({'source': str(source), 'snapshot': destination.relative_to(work).as_posix(),
                                 'sha256': digest, 'bytes': destination.stat().st_size})
            verify_all()
            overrides = oracle.frozen_conv0(model_snapshot)
            folder = vectors / 'frozen_conv0'
            folder.mkdir()
            cfg, memory, expected, ys = oracle.make_case(918, **overrides)
            for name, data in (('memory', memory), ('expected', expected)):
                (folder / (name + '.hex')).write_text(''.join(f'{v:02x}\n' for v in data), encoding='ascii')
            (folder / 'config.hex').write_text(''.join(f'{v:08x}\n' for v in cfg), encoding='ascii')
            manifest.append({'name': 'frozen_conv0', 'config': cfg, 'output_values': len(ys),
                             'expected_error': 0, 'frozen_sources': external,
                             'scope': 'Real frozen Conv_0 weights/bias/per-channel requant, cropped 7x5 input; not a full layer.'})
            write_json(vectors / 'cases.json', manifest)
            result['frozen_model_inputs'] = external
        for path in vectors.rglob('*'):
            if path.is_file():
                freeze_generated(path)
        result['vectors'] = {'manifest': 'vectors/cases.json', 'oracle': 'inputs/tb/npu/operator_oracle.py'}
        for case in dict.fromkeys(args.cases):
            folder = vectors / case
            cfg = [int(v, 16) for v in (folder / 'config.hex').read_text().splitlines()]
            output_bytes = cfg[19] * (2 if cfg[16] == 3 else 1)
            expected = bytes(int(v, 16) for v in (folder / 'expected.hex').read_text().splitlines())[0x6000:0x6000 + output_bytes]
            packed = cfg[:5] + [cfg[5] | cfg[6] << 16, cfg[7] | cfg[8] << 16,
                                cfg[9] | cfg[10] << 16, cfg[11] | cfg[12] << 8 | cfg[13] << 16 | cfg[14] << 24,
                                cfg[15] | cfg[16] << 8, 0, 0, 0]
            header = folder / 'operator_vectors.h'
            header.write_text('static struct npu_operator_config vector_config = {' +
                              ','.join(hex(v) + 'u' for v in packed) + '};\n' +
                              'static const uint8_t expected_output[] = {' +
                              ','.join(hex(v) for v in expected) + '};\n', encoding='utf-8')
            freeze_generated(header)
            for mode in dict.fromkeys(args.modes):
                base = case + '_' + mode
                elf, binary = work / (base + '.elf'), work / (base + '.bin')
                flags = ['-march=rv32i_zicsr', '-mabi=ilp32', '-Os', '-ffreestanding', '-fno-builtin',
                         '-fno-pic', '-fno-pie', '-msmall-data-limit=0', '-mno-relax', '-nostdlib', '-nostartfiles',
                         '-Wall', '-Wextra', '-Werror', '-I' + str(source_target / 'sw/include'), '-I' + str(folder),
                         '-DIRQ_MODE=' + str(int(mode == 'irq')), '-T', source_target / 'sw/tests/npu_operator/link.ld',
                         '-Wl,--build-id=none', '-Wl,-Map=' + str(work / (base + '.map'))]
                checked([gcc, *flags, source_target / 'sw/tests/npu_operator/start.S',
                         source_target / 'sw/tests/npu_operator/main.c', source_target / 'sw/drivers/npu_operator.c',
                         '-o', elf], 'gcc_' + base)
                freeze_generated(elf)
                checked([executables['objcopy'], '-O', 'binary', elf, binary], 'objcopy_' + base)
                data = binary.read_bytes()
                if len(data) > 8192:
                    raise RuntimeError('firmware exceeds 8KiB diagnostic ROM')
                binary.write_bytes(data.ljust(8192, b'\0'))
                freeze_generated(binary)
                checked([executables['objdump'], '-d', elf], 'disassembly_' + base)
                checked([executables['nm'], '-n', elf], 'symbols_' + base)

                def simulation(name, no_control=0, bad_data=0, rejection=None):
                    signature, output = work / (name + '.signature.hex'), work / (name + '.output.hex')
                    macro = work / (name + '.do')
                    # $fatal can return zero in ModelSim 2020.4. Only our closed
                    # signature file authorizes success from its finish breakpoint.
                    macro.write_text('onerror {quit -code 1}\nonbreak {if {[file exists ' + signature.name +
                                     ']} {quit -code 0} else {quit -code 2}}\nrun -all\nquit -code 3\n', encoding='utf-8')
                    freeze_generated(macro)
                    code, text = execute([vsim, '-c', '-onfinish', 'stop', 'work.' + TOP,
                        '-gIRQ_MODE=' + str(int(mode == 'irq')), '-gNO_CONTROL=' + str(no_control), '-gBAD_DATA=' + str(bad_data),
                        '+ROM_IMAGE=' + binary.as_posix(), '+SIGNATURE=' + signature.as_posix(),
                        '+MEMORY=' + (folder / 'memory.hex').as_posix(), '+EXPECTED=' + (folder / 'expected.hex').as_posix(),
                        '+CONFIG=' + (folder / 'config.hex').as_posix(), '+OUTPUT=' + output.as_posix(), '-do', macro.as_posix()], name)
                    if rejection:
                        if not code or rejection not in text or 'CPU_NPU_OPERATOR_PASS' in text or signature.exists():
                            raise RuntimeError('negative scenario not rejected correctly: ' + name + '\n' + text[-4000:])
                        result['negative_tests'].append({'name': name, 'status': 'rejected', 'exit_code': code, 'reason': rejection})
                        print(name + ' REJECTED exit=' + str(code), flush=True)
                        return
                    if code or 'CPU_NPU_OPERATOR_PASS' not in text or not signature.is_file() or not output.is_file():
                        raise RuntimeError('CPU diagnostic failed: ' + name + ' exit=' + str(code) + '\n' + text[-5000:])
                    words = [int(v, 16) for v in signature.read_text().splitlines()]
                    observed = bytes(int(v, 16) for v in output.read_text().splitlines())
                    if len(words) != 16 or words[0] != 0x4350554e or words[2] != 2 or words[4] != output_bytes * 2 or observed != expected:
                        raise RuntimeError('closed CPU signature/output disagrees with independent oracle')
                    result['runs'].append({'name': name, 'status': 'pass', 'case': case, 'mode': mode,
                                           'tasks': 2, 'output_bytes_per_task': output_bytes,
                                           'signature': signature.name, 'signature_words': words,
                                           'elf': elf.name, 'output': output.name,
                                           'marker': next(v.strip('# ') for v in text.splitlines() if 'CPU_NPU_OPERATOR_PASS' in v)})
                    print(name + ' PASS', flush=True)

                if case == args.cases[0] and mode == args.modes[0]:
                    if args.scenario in ('all', 'red-no-control'):
                        simulation('red_no_control', no_control=1, rejection='CPU_NPU_FAIL timeout')
                    if args.scenario in ('all', 'red-corruption'):
                        simulation('red_corrupted_output', bad_data=1, rejection='CPU_NPU_FAIL firmware signature bad00020')
                if args.scenario in ('all', 'green'):
                    simulation(base)
                else:
                    break
            if args.scenario.startswith('red-'):
                break
        verify_all()
        result['generated_simulation_inputs'] = generated
        if args.scenario.startswith('red-'):
            result['status'] = 'expected_rejection'
        else:
            result['status'] = 'pass'
    except Exception as error:
        result['status'] = 'fail'
        result['error'] = str(error)
        print('CPU_NPU_FAIL: ' + str(error), file=sys.stderr, flush=True)
    finally:
        if result['inputs']:
            result['inputs_after'] = {p: sha256(ROOT / p) for p in result['inputs']}
            if result['inputs_after'] != result['inputs']:
                result['status'] = 'fail'
                result['error'] = 'source inputs changed during run'
        result['artifacts'] = {p.relative_to(work).as_posix(): sha256(p) for p in sorted(work.rglob('*'))
                               if p.is_file() and p != work / 'result.json' and 'work' not in p.relative_to(work).parts}
        write_json(work / 'result.json', result)
        write_json(latest, result)
    print('CPU_NPU_' + result['status'].upper() + ' ' + work.relative_to(ROOT).as_posix(), flush=True)
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())

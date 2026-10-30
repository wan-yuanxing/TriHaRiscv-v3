"""Frozen full-size Dense/DW vectors through the actual scalar Verilog DUT."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import time
from frozen_inputs import FrozenInputs, sha256

ROOT = Path(__file__).resolve().parents[2]
SEGMENTS = ('input', 'weight', 'bias', 'requant', 'output')
BASES = (0x82800000, 0x82B00000, 0x82C00000, 0x82D00000, 0x83300000)
MARKER = re.compile(r'NPU_LAYER_PASS cycles=(\d+) compute=(\d+) reads=(\d+) writes=(\d+) bytes=(\d+)')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def asset_path(root, value):
    require(isinstance(value, str) and value and '\\' not in value and ':' not in value,
            'unsafe asset path')
    pure = PurePosixPath(value)
    require(not pure.is_absolute() and all(part not in ('', '.', '..') for part in pure.parts),
            'unsafe asset path')
    path = root / pure
    require(path.resolve().is_relative_to(root.resolve()), 'asset path escaped root')
    return path


def pack_lines(source, target):
    data = source.read_bytes()
    data += bytes((-len(data)) % 16)
    target.write_text(''.join(data[i:i+16][::-1].hex() + '\n' for i in range(0, len(data), 16)),
                      encoding='ascii')


def validate_layer(root, layer):
    require(layer.get('no_crop') is True, 'cropped layer cannot qualify as full-size')
    require(type(layer.get('operator_id')) is int and layer['operator_id'] >= 0, 'invalid operator id')
    config = asset_path(root, layer['config'])
    config_hex = asset_path(root, layer['config_hex'])
    require(sha256(config) == layer['config_sha256'], 'config hash mismatch')
    require(sha256(config_hex) == layer['config_hex_sha256'], 'config hex hash mismatch')
    words = json.loads(config.read_text(encoding='utf-8'))['config_words']
    require(len(words) == 32 and all(type(v) is int and 0 <= v <= 0xffffffff for v in words), 'config words')
    require([int(x, 16) for x in config_hex.read_text(encoding='ascii').split()] == words,
            'config JSON/hex mismatch')
    require(words[:5] == list(BASES) and not any(words[22:]), 'config address/reserved words')
    iw, ih, ci, co, ow, oh, kernel, stride, pad, dw, signed, fmt = words[5:17]
    require(1 <= iw <= 320 and 1 <= ih <= 320 and 1 <= ci <= 64 and 1 <= co <= 64,
            'geometry outside implemented range')
    require(kernel in (1, 3) and stride in (1, 2) and pad in (0, 1) and dw in (0, 1) and
            signed in (0, 1) and fmt in (1, 2, 3), 'unsupported kernel/format')
    require(not dw or ci == co, 'depthwise channels')
    require(ow == (iw + 2*pad - kernel)//stride + 1 and oh == (ih + 2*pad-kernel)//stride + 1 and
            ow > 0 and oh > 0, 'output shape formula')
    require(layer['input_shape'] == [1, ci, ih, iw] and layer['output_shape'] == [1, co, oh, ow],
            'layer shape disagrees with config')
    k = kernel*kernel*(1 if dw else ci)
    sizes = [iw*ih*ci, ((co+15)//16)*k*16, co*4, co*8, ow*oh*co*(2 if fmt == 3 else 1)]
    require(words[17:22] == sizes, 'config segment lengths')
    require(layer['macs'] == ow*oh*co*k, 'layer MAC count')
    for i, name in enumerate(SEGMENTS):
        record = layer['segments'][name]
        path = asset_path(root, record['path'])
        require(record['address'] == BASES[i] and record['bytes'] == sizes[i] and path.stat().st_size == sizes[i],
                'segment length/address mismatch ' + name)
        require(sha256(path) == record['sha256'], 'segment hash mismatch ' + name)
    return words


def validate_manifest(path, asset_root=None):
    root = asset_root or path.parent
    manifest = json.loads(path.read_text(encoding='utf-8'))
    require(isinstance(manifest.get('cases'), list) and manifest['cases'], 'empty layer manifest')
    names = [case['name'] for case in manifest['cases']]
    require(len(set(names)) == len(names), 'duplicate input case')
    for case in manifest['cases']:
        require(re.fullmatch(r'[A-Za-z0-9_-]+', case['name']) is not None, 'unsafe case name')
        ids = [layer['operator_id'] for layer in case['layers']]
        require(len(ids) == len(set(ids)), 'duplicate layer operator id')
        for layer in case['layers']:
            validate_layer(root, layer)
    return manifest


def prepare_case(asset_root, layer, target, guard):
    words = validate_layer(asset_root, layer)
    target.mkdir(parents=True)
    for key, filename in (('config', 'config.json'), ('config_hex', 'config.hex')):
        guard.external(asset_path(asset_root, layer[key]), target / filename)
        require(sha256(target/filename) == layer[key+'_sha256'], 'frozen config hash mismatch')
    for name in SEGMENTS:
        filename = 'expected' if name == 'output' else name
        source = asset_path(asset_root, layer['segments'][name]['path'])
        binary, packed = target / (filename+'.bin'), target / (filename+'.hex')
        guard.external(source, binary)
        require(sha256(binary) == layer['segments'][name]['sha256'], 'frozen segment hash mismatch '+name)
        pack_lines(binary, packed)
        guard.track(packed)
    return words


def execute(command, cwd, log, guard, records, timeout):
    guard.verify()
    command = [str(value) for value in command]
    record = {'command': command, 'cwd': str(cwd), 'log': str(log)}
    records.append(record)
    try:
        with log.open('w', encoding='utf-8') as stream:
            completed = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                       timeout=timeout)
        record['exit_code'] = completed.returncode
    finally:
        guard.verify()
    record['sha256'] = sha256(log)
    output = log.read_text(encoding='utf-8', errors='replace')
    if completed.returncode:
        raise RuntimeError('command exit %d: %s' % (completed.returncode, output[-5000:]))
    return output


def compile_modelsim(work, inputs, guard, commands):
    tools = Path('D:/modeltech64_2020.4/win64')
    records = {}
    for name in ('vlib', 'vlog', 'vmap', 'vopt', 'vsim'):
        path = tools / (name+'.exe')
        guard.track(path)
        records[name] = {'path': str(path), 'sha256': sha256(path)}
    directory = work / 'modelsim'
    directory.mkdir()
    execute([tools/'vsim.exe', '-version'], directory, directory/'version.log', guard, commands, 60)
    execute([tools/'vmap.exe', '-c'], directory, directory/'vmap_copy.log', guard, commands, 60)
    execute([tools/'vlib.exe', 'work'], directory, directory/'vlib.log', guard, commands, 60)
    execute([tools/'vmap.exe', 'work', (directory/'work').as_posix()], directory,
            directory/'vmap.log', guard, commands, 60)
    execute([tools/'vlog.exe', '-sv', '-work', 'work', inputs/'rtl/npu/npu_scalar_conv.v',
             inputs/'tb/npu/tb_npu_layer.sv'], directory, directory/'compile.log', guard, commands, 120)
    execute([tools/'vopt.exe', 'work.tb_npu_layer', '-o', 'layer_optimized'], directory,
            directory/'optimize.log', guard, commands, 120)
    guard.track(directory/'modelsim.ini')
    return {'modelsimini': directory/'modelsim.ini', 'vsim': tools/'vsim.exe', 'tools': records}


def run_case_modelsim(backend, directory, max_cycles, negative, guard, commands, timeout):
    command = [backend['vsim'], '-c', '-onfinish', 'stop', '-modelsimini', backend['modelsimini'].as_posix(), 'work.layer_optimized',
               '+CASE_DIR='+directory.as_posix(), '+MAX_CYCLES='+str(max_cycles)]
    if negative:
        command.append('+CORRUPT_OUTPUT')
    command += ['-wlf', str(directory/'wave.wlf'), '-do', 'onerror {quit -code 1}; run -all; quit -code 0']
    output = execute(command, directory, directory/'simulation.log', guard, commands, timeout)
    actual = bytearray()
    path = directory / 'actual.hex'
    if path.is_file():
        for line in path.read_text(encoding='ascii').splitlines():
            line = line.split('//', 1)[0].strip()
            if not line:
                continue
            for token in line.split():
                require(re.fullmatch(r'[0-9a-fA-F]{32}', token) is not None, 'invalid actual output line')
                actual.extend(int(token, 16).to_bytes(16, 'little'))
    return output, bytes(actual)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--cases', nargs='+')
    parser.add_argument('--ops', nargs='+', type=int)
    parser.add_argument('--jobs', type=int, default=1)
    parser.add_argument('--timeout', type=int, default=7200)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--negative', action='store_true', help='Intentionally reject the corrupted first output.')
    parser.add_argument('--simulator', choices=('modelsim', 'compiled'), default='modelsim')
    parser.add_argument('--verilator-root', type=Path)
    parser.add_argument('--compiler', type=Path)
    args = parser.parse_args(argv)
    work = (args.output or ROOT/'build/npu'/datetime.now(timezone.utc).strftime('layers-rtl-%Y%m%dT%H%M%S_%fZ')).resolve()
    work.mkdir(parents=True, exist_ok=False)
    result = {'status': 'RUNNING', 'directory': str(work), 'runs': [], 'commands': [],
              'scope': 'actual scalar RTL at full layer dimensions; client memory model, independent layer inputs; '
                       'no CPU/MMIO/AXI, graph chaining, physical DDR/CDC or board signoff',
              'simulator': args.simulator}
    latest = ROOT/'build/npu/latest_layers_rtl.json'
    write_json(latest, result)
    try:
        require(__debug__, 'optimized Python disables source oracle checks; PASS prohibited')
        require(1 <= args.jobs <= 16 and args.timeout > 0, 'invalid jobs/timeout')
        manifest_path = args.manifest.resolve()
        names = ['rtl/npu/npu_scalar_conv.v', 'tb/npu/tb_npu_layer.sv', 'scripts/npu/run_layer_rtl.py',
                 'scripts/npu/frozen_inputs.py']
        if args.simulator == 'compiled':
            names += ['tb/npu/npu_layer_main.cpp', 'scripts/npu/compiled_layers.py', 'scripts/npu/prepare_layer_tool.py']
        guard = FrozenInputs(ROOT, work/'inputs', names)
        guard.external(manifest_path, work/'assets/manifest.json')
        # Freeze before parsing. Every path in these immutable bytes still
        # refers to the original asset tree; prepare_case freezes each segment
        # and checks that copy against the manifest's declared digest.
        manifest = validate_manifest(work/'assets/manifest.json', asset_root=manifest_path.parent)
        guard.verify()
        result['source_sha256'] = guard.inputs
        result['manifest'] = {'path': str(manifest_path), 'sha256': sha256(work/'assets/manifest.json')}
        for original, digest in manifest.get('source_sha256', {}).items():
            guard.track(Path(original))
            require(guard.tracked[str(Path(original))] == digest, 'upstream source hash mismatch '+original)
        selected = [(case['name'], layer) for case in manifest['cases'] if not args.cases or case['name'] in args.cases
                    for layer in case['layers'] if not args.ops or layer['operator_id'] in args.ops]
        require(selected, 'no cases/layers selected')
        if args.cases:
            require(set(args.cases) <= {case['name'] for case in manifest['cases']}, 'unknown requested input case')
        if args.ops:
            require(set(args.ops) <= {layer['operator_id'] for _, layer in selected}, 'unknown requested operator')
        prepared = []
        for case_name, layer in selected:
            directory = work/'runs'/case_name/('op%03d' % layer['operator_id'])
            words = prepare_case(manifest_path.parent, layer, directory, guard)
            prepared.append((case_name, layer, directory, words))
        result['frozen_assets_sha256'] = guard.external_inputs
        if args.simulator == 'modelsim':
            backend = compile_modelsim(work, work/'inputs', guard, result['commands'])
            result['tools'] = backend['tools']
        else:
            spec = importlib.util.spec_from_file_location('compiled_layer_backend', work/'inputs/scripts/npu/compiled_layers.py')
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            verilator_root = args.verilator_root.resolve() if args.verilator_root else module.tool_root(ROOT)
            compiler = args.compiler.resolve() if args.compiler else Path('D:/Xilinx/Vivado/2018.3/msys64/mingw64/bin/g++.exe')
            provenance = verilator_root.parent/'provenance.json'
            guard.external(provenance, work/'tool_provenance.json')
            provenance_record = json.loads((work/'tool_provenance.json').read_text(encoding='utf-8'))
            for name, digest in provenance_record['files_sha256'].items():
                original = asset_path(verilator_root.parent, name.replace('\\', '/'))
                guard.track(original)
                require(guard.tracked[str(original)] == digest, 'simulator package provenance hash mismatch '+name)
            result['simulator_package_provenance'] = {'path': str(provenance), 'sha256': sha256(work/'tool_provenance.json'),
                                                       'source': provenance_record['source'],
                                                       'wheel_sha256': provenance_record['wheel_sha256']}
            guard.verify()
            backend = module.build(work/'compiled', work/'inputs/rtl/npu/npu_scalar_conv.v',
                                   work/'inputs/tb/npu/npu_layer_main.cpp', verilator_root, compiler)
            guard.verify()
            guard.track(backend['binary'])
            for record in backend.get('tools', {}).values():
                if isinstance(record, dict) and 'path' in record:
                    require(sha256(record['path']) == record['sha256'], 'compiled tool input changed '+record['path'])
                    guard.track(record['path'])
            for path, digest in backend.get('generated', {}).items():
                require(sha256(path) == digest, 'compiled generated input changed '+str(path))
                guard.track(path)
            result['tools'] = backend.get('tools', {})
            result['compiled_backend'] = backend

        def run_one(item):
            case_name, layer, directory, words = item
            record = {'case': case_name, 'operator_id': layer['operator_id'], 'name': layer['name'],
                      'status': 'RUNNING', 'full_size': True, 'input_shape': layer['input_shape'],
                      'output_shape': layer['output_shape'], 'output_bytes': words[21], 'macs': layer['macs'],
                      'directory': str(directory.relative_to(work))}
            iw, ih, ci, co, ow, oh, kernel, stride, pad, dw = words[5:15]
            valid_x = sum(0 <= ox*stride+kx-pad < iw for ox in range(ow) for kx in range(kernel))
            valid_y = sum(0 <= oy*stride+ky-pad < ih for oy in range(oh) for ky in range(kernel))
            valid_macs = co*(1 if dw else ci)*valid_x*valid_y
            record['valid_macs'] = valid_macs
            record['nominal_macs'] = layer['macs']
            started = time.monotonic()
            try:
                max_cycles = max(10000, layer['macs']*45 + (words[21]//(2 if words[16] == 3 else 1))*40 + words[8]*100 + 1000)
                record['max_cycles'] = max_cycles
                if args.simulator == 'modelsim':
                    output, actual = run_case_modelsim(backend, directory, max_cycles, args.negative,
                                                       guard, result['commands'], args.timeout)
                else:
                    actual_path = directory/'actual.bin'
                    output = execute([backend['binary'], directory, max_cycles, actual_path, int(args.negative)],
                                     directory, directory/'simulation.log', guard, result['commands'], args.timeout)
                    actual = actual_path.read_bytes() if actual_path.is_file() else b''
                matches = list(MARKER.finditer(output))
                if len(matches) != 1 or output.count('NPU_LAYER_PASS') != 1 or re.search(r'(Fatal:|NPU_LAYER_FAIL)', output):
                    raise RuntimeError('simulation lacks unique success: '+output[-5000:])
                if args.simulator == 'modelsim':
                    require(len(actual) == ((words[21]+15)//16)*16, 'actual output line count mismatch')
                    actual = actual[:words[21]]
                    (directory/'actual.bin').write_bytes(actual)
                expected = (directory/'expected.bin').read_bytes()
                require(actual == expected and len(actual) == words[21], 'actual binary differs from expected')
                values = [int(x) for x in matches[0].groups()]
                require(values[-1] == words[21], 'reported compared byte count mismatch')
                require(values[1] == valid_macs, 'reported non-padding MAC count mismatch')
                record.update(status='PASS', cycles=values[0], compute=values[1], reads=values[2],
                              writes=values[3], compared_bytes=values[4], actual_sha256=sha256(directory/'actual.bin'),
                              expected_sha256=sha256(directory/'expected.bin'))
                print('LAYER_PASS %s op%03d bytes=%d cycles=%d' %
                      (case_name, layer['operator_id'], words[21], values[0]), flush=True)
            except Exception as error:
                record.update(status='FAIL', error=str(error))
                print('LAYER_FAIL %s op%03d %s' % (case_name, layer['operator_id'], error), flush=True)
            record['elapsed_seconds'] = round(time.monotonic()-started, 6)
            write_json(directory/'result.json', record)
            return record

        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = [pool.submit(run_one, item) for item in prepared]
            for future in as_completed(futures):
                result['runs'].append(future.result())
                write_json(work/'progress.json', result)
        result['runs'].sort(key=lambda item: (item['case'], item['operator_id']))
        guard.verify()
        result['source_unchanged'] = True
        all_pairs = {(case['name'], layer['operator_id']) for case in manifest['cases'] for layer in case['layers']}
        selected_pairs = {(name, layer['operator_id']) for name, layer in selected}
        supported = {op['operator_id'] for op in manifest.get('operators', []) if op.get('rtl_supported')}
        full_suite = (len(manifest.get('operators', [])) == 79 and len(supported) == 47 and
                      {case['name'] for case in manifest['cases']} == {'zero', 'full255', 'pattern'} and
                      len(all_pairs) == 141 and selected_pairs == all_pairs and
                      all({layer['operator_id'] for layer in case['layers']} == supported for case in manifest['cases']))
        all_passed = all(item['status'] == 'PASS' for item in result['runs'])
        result['full_suite_qualified'] = full_suite and all_passed
        result['status'] = ('PASS' if full_suite else 'PARTIAL') if all_passed else 'FAIL'
        result['summary'] = {'requested_layers': len(selected), 'passed_layers': sum(r['status'] == 'PASS' for r in result['runs']),
                             'compared_bytes': sum(r.get('compared_bytes', 0) for r in result['runs']),
                             'full_graph_executed': False,
                             'non_convolution_operators_not_executed': len(manifest.get('operators', [])) - len({l['operator_id'] for c in manifest['cases'] for l in c['layers']})}
        result['tracked_simulation_inputs'] = guard.tracked
    except Exception as error:
        result.update(status='FAIL', error=str(error))
        print('LAYER_RUNNER_FAIL '+str(error), file=sys.stderr, flush=True)
    result['artifacts_sha256'] = {p.relative_to(work).as_posix(): sha256(p) for p in work.rglob('*')
                                 if p.is_file() and p != work/'result.json' and p.suffix not in ('.wlf',)}
    write_json(work/'result.json', result)
    write_json(latest, result)
    print('NPU_LAYERS_'+result['status']+' '+str(work/'result.json'), flush=True)
    return 0 if result['status'] in ('PASS', 'PARTIAL') else 1


if __name__ == '__main__':
    raise SystemExit(main())

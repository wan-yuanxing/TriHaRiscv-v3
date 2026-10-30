"""Freeze existing YuNet numeric assets and export full-shape RTL layer cases.

No calibration, retraining or quantization is performed. Expected tensors are
computed by the frozen upstream wire-reference implementation and checked
against its historical packed head hashes. This is a host asset preparation
result, never an RTL, system, board or five-point accuracy result.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
REVISION = '178c3ad1ba515d43725dd80ab19e20b50d471413'
PROGRAM = 'build/integration_audit/20261020/program.bin'
IMAGE = 'build/integration_audit/20261020/parameter_image.bin'
PACKAGE = 'yunet/baseline/program_package_manifest_v0_1.json'
NUMERICS = 'yunet/models/integer_numerics_v1.json'
GOLDEN = 'yunet/baseline/ptq_integer_golden_summary_v1.json'
DTYPES = {1: '|u1', 2: '|i1', 3: '<i2', 4: '<u2'}
OPS = {1: 'DenseConv', 2: 'DWConv', 3: 'Add', 4: 'MaxPool',
       5: 'NearestResize', 6: 'Transpose', 7: 'Reshape', 8: 'Sigmoid'}
HF = ['magic', 'format_id', 'header_bytes', 'logical_bytes', 'allocated_bytes',
      'tensor_count', 'param_count', 'op_count', 'tensor_offset', 'tensor_stride',
      'param_offset', 'param_stride', 'op_offset', 'op_stride', 'workspace_bytes',
      'model_package_version', 'numerics_id', 'required_ops', 'required_numeric_caps',
      'input_count', 'output_count', 'flags', 'max_rank', 'weight_block']
TF = ['id', 'dtype', 'rank', 'role', 'model_offset', 'logical_bytes', 'allocated_bytes',
      'element_count', 'dim0', 'dim1', 'dim2', 'dim3', 'qmin', 'qmax', 'producer', 'flags']
PF = ['id', 'kind', 'model_offset', 'logical_bytes', 'allocated_bytes', 'count', 'owner', 'flags']
OF = ['id', 'opcode', 'flags', 'input_count', 'input0', 'input1', 'output',
      'param0', 'param1', 'param2', 'param3'] + ['arg' + str(i) for i in range(16)]
BASES = [0x82800000, 0x82b00000, 0x82c00000, 0x82d00000, 0x83300000]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sha(path):
    return digest(Path(path).read_bytes())


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def tensor_shape(tensor):
    return [tensor['dim' + str(i)] for i in range(tensor['rank'])]


def decode_package(wire, image, manifest):
    """Digest-first, bounds-checked local decode; upstream validator also runs."""
    require(digest(wire) == manifest['program_sha256'], 'program SHA mismatch')
    require(digest(image) == manifest['parameter_image_sha256'], 'parameter image SHA mismatch')
    require(len(wire) >= 128, 'wire length is shorter than header')
    raw = struct.unpack_from('<32I', wire)
    h = dict(zip(HF, raw))
    require(h['magic'] == 0x5055504e and h['format_id'] == 1 and h['header_bytes'] == 128,
            'unsupported wire header')
    require(not any(raw[24:]), 'reserved header words')
    require(1 <= h['tensor_count'] <= 128 and 1 <= h['op_count'] <= 128 and h['param_count'] <= 256,
            'wire table count')
    expected = 128 + h['tensor_count'] * 64 + h['param_count'] * 32 + h['op_count'] * 128
    require(len(wire) == h['logical_bytes'] == expected, 'wire length/table mismatch')
    require((h['tensor_offset'], h['tensor_stride'], h['param_offset'], h['param_stride'],
             h['op_offset'], h['op_stride']) ==
            (128, 64, 128 + h['tensor_count'] * 64, 32,
             128 + h['tensor_count'] * 64 + h['param_count'] * 32, 128), 'wire table layout')
    if 'header' in manifest:
        require(h == manifest['header'], 'wire header differs from package manifest')
    tables = {}
    for label, fields, offset, count, stride in (
            ('tensors', TF, h['tensor_offset'], h['tensor_count'], 64),
            ('params', PF, h['param_offset'], h['param_count'], 32),
            ('ops', OF, h['op_offset'], h['op_count'], 128)):
        rows = []
        for i in range(count):
            values = struct.unpack_from('<' + str(stride // 4) + 'I', wire, offset + i * stride)
            require(not any(values[len(fields):]), 'reserved wire table words')
            row = dict(zip(fields, values))
            require(row['id'] == i, 'noncanonical wire id')
            if label == 'tensors':
                for key in ('qmin', 'qmax'):
                    if row[key] >= 1 << 31:
                        row[key] -= 1 << 32
                require(row['dtype'] in DTYPES and 1 <= row['rank'] <= 4, 'tensor dtype/rank')
                shape = tensor_shape(row)
                size = 1 if row['dtype'] in (1, 2) else 2
                require(all(0 < n <= 320 * 320 for n in shape) and
                        row['element_count'] == math.prod(shape) and
                        row['logical_bytes'] == math.prod(shape) * size and
                        row['allocated_bytes'] >= row['logical_bytes'], 'tensor length/shape mismatch')
            rows.append(row)
        tables[label] = rows
    require(len(manifest['tensor_names']) == len(tables['tensors']) and
            len(manifest['operator_names']) == len(tables['ops']), 'manifest name count')
    origin = manifest['parameter_image_model_offset']
    require(origin == min(p['model_offset'] for p in tables['params']) and
            origin + len(image) == h['workspace_bytes'], 'parameter image span')
    for p in tables['params']:
        a = p['model_offset'] - origin
        require(0 <= a <= len(image) and 0 < p['logical_bytes'] <= p['allocated_bytes'] and
                a + p['allocated_bytes'] <= len(image), 'parameter image range')
    inventory = []
    for op in tables['ops']:
        require(op['opcode'] in OPS, 'unsupported opcode')
        require(op['input0'] < len(tables['tensors']) and op['output'] < len(tables['tensors']),
                'operator tensor reference')
        x, y = tables['tensors'][op['input0']], tables['tensors'][op['output']]
        row = {'operator_id': op['id'], 'name': manifest['operator_names'][op['id']],
               'opcode': op['opcode'], 'op': OPS[op['opcode']], 'input_ids': [op['input0']],
               'output_id': op['output'], 'input_shape': tensor_shape(x), 'output_shape': tensor_shape(y),
               'input_dtype': DTYPES[x['dtype']], 'output_dtype': DTYPES[y['dtype']],
               'rtl_supported': op['opcode'] in (1, 2), 'no_crop': True, 'macs': 0}
        if op['input_count'] == 2:
            require(op['input1'] < len(tables['tensors']), 'second operator tensor reference')
            row['input_ids'].append(op['input1'])
        if row['rtl_supported']:
            xs, ys = tensor_shape(x), tensor_shape(y)
            require(len(xs) == len(ys) == 4 and xs[0] == ys[0] == 1,
                    'Conv batch/rank unsupported by RTL')
            require(max(xs[2:]) <= 320 and 0 < xs[1] <= 64 and 0 < ys[1] <= 64 and
                    op['arg0'] == op['arg1'] and op['arg0'] in (1, 3) and
                    op['arg2'] == op['arg3'] and op['arg2'] in (1, 2) and
                    len({op['arg' + str(i)] for i in range(4, 8)}) == 1 and op['arg4'] in (0, 1),
                    'Conv shape outside existing RTL contract')
            require(op['arg8'] == op['arg9'] == 1 and x['dtype'] in (1, 2) and y['dtype'] in (1, 2, 3),
                    'Conv dilation/dtype outside existing RTL contract')
            require(op['arg10'] == (xs[1] if op['opcode'] == 2 else 1) and
                    (op['opcode'] != 2 or xs[1] == ys[1]), 'Conv group outside existing RTL contract')
            k, stride, pad = op['arg0'], op['arg2'], op['arg4']
            require(ys[2:] == [(n + 2 * pad - k) // stride + 1 for n in xs[2:]], 'Conv output geometry')
            row['macs'] = y['element_count'] * k * k * (xs[1] if op['opcode'] == 1 else 1)
        inventory.append(row)
    return {'header': h, **tables, 'operators': inventory, 'manifest': manifest, 'image': image}


def config_words(package, operator_id):
    op = package['ops'][operator_id]
    require(op['opcode'] in (1, 2), 'operator has no convolution RTL configuration')
    x, y = (package['tensors'][op[key]] for key in ('input0', 'output'))
    xs, ys = tensor_shape(x), tensor_shape(y)
    params = [package['params'][op['param' + str(i)]] for i in range(3)]
    require([p['kind'] for p in params] == [1, 2, 3], 'Conv parameter kinds')
    words = [*BASES, xs[3], xs[2], xs[1], ys[1], ys[3], ys[2],
             op['arg0'], op['arg2'], op['arg4'], int(op['opcode'] == 2), int(x['dtype'] == 2), y['dtype'],
             x['logical_bytes'], *[p['logical_bytes'] for p in params], y['logical_bytes']]
    return words + [0] * (32 - len(words))


def verify_generated(output, result):
    """Seal only the bytes whose digests the reference worker actually checked."""
    require(result['status'] == 'PASS_HOST_ASSETS_ONLY', 'host reference did not pass')
    require([case['name'] for case in result['cases']] == ['zero', 'full255', 'pattern'],
            'host reference case set changed')
    files = {}
    for case in result['cases']:
        require(len(case['tensors']) == 80 and len(case['layers']) == 47 and
                case['historical_heads_checked'] == 9, 'host reference coverage changed')
        for tensor in case['tensors']:
            files[tensor['path']] = (tensor['sha256'], tensor['bytes'])
        for layer in case['layers']:
            files[layer['config']] = (layer['config_sha256'], None)
            files[layer['config_hex']] = (layer['config_hex_sha256'], None)
            for segment in layer['segments'].values():
                files[segment['path']] = (segment['sha256'], segment['bytes'])
    for name, (expected, count) in files.items():
        require(not name.startswith('/') and ':' not in name and '\\' not in name and
                all(part not in ('', '.', '..') for part in name.split('/')), 'unsafe generated asset path')
        path = output / name
        require(path.is_file() and sha(path) == expected and (count is None or path.stat().st_size == count),
                'generated asset changed: ' + name)


def _frozen_worker(output, frozen_root):
    require(__debug__, 'optimized Python disables upstream checks; PASS is prohibited')
    sys.path.insert(0, str(frozen_root / 'yunet/python'))
    import numpy as np
    import program_abi
    import threadpoolctl
    manifest = read_json(frozen_root / PACKAGE)
    package = decode_package((frozen_root / PROGRAM).read_bytes(), (frozen_root / IMAGE).read_bytes(), manifest)
    upstream = program_abi.unpack((frozen_root / PROGRAM).read_bytes())
    program_abi.validate(upstream)
    arrays = program_abi.parameter_arrays(upstream, package['image'], manifest['parameter_image_model_offset'])
    numeric = read_json(frozen_root / NUMERICS)
    numeric_path = frozen_root / numeric['parameters']['path']
    require(sha(numeric_path) == numeric['parameters']['sha256'], 'numeric NPZ SHA mismatch')
    comparisons = 0
    with np.load(numeric_path, allow_pickle=False) as packed:
        for op, row in zip(package['ops'], package['operators']):
            if op['opcode'] in (1, 2):
                values = {'weights': arrays[op['param0']], 'bias': arrays[op['param1']],
                          'multiplier': arrays[op['param2']][:, 0], 'shift': arrays[op['param2']][:, 1]}
            elif op['opcode'] == 8:
                values = {'lut': arrays[op['param1']]}
            else:
                continue
            for key, value in values.items():
                require(np.array_equal(value, packed[row['name'] + '__' + key]), 'NPZ parameter mismatch: ' + row['name'] + '/' + key)
                comparisons += 1
    # Bind loaded host implementation/library files before executing the reference.
    runtime_files = {str(Path(module.__file__).resolve()): sha(module.__file__)
                     for module in list(sys.modules.values())
                     if getattr(module, '__file__', None) and Path(module.__file__).is_file()}
    for p in (Path(np.__file__).parent.parent / 'numpy.libs').glob('*.dll'):
        runtime_files[str(p.resolve())] = sha(p)
    historical = {case['name']: case for case in read_json(frozen_root / GOLDEN)['cases']}
    cases = []
    grid = np.indices((1, 3, 320, 320))
    tensors = [('zero', np.zeros((1, 3, 320, 320), np.uint8)),
               ('full255', np.full((1, 3, 320, 320), 255, np.uint8)),
               ('pattern', ((grid[1] * 83 + grid[2] * 7 + grid[3] * 13) % 256).astype(np.uint8))]
    for name, tensor in tensors:
        require(digest(tensor.tobytes()) == historical[name]['input_sha256'], 'historical input SHA mismatch')
        values = program_abi.reference_from_wire(upstream, arrays, tensor)
        require(len(values) == len(package['tensors']), 'reference did not produce every tensor')
        folder = output / 'cases' / name
        records = []
        for t in package['tensors']:
            value = values[t['id']]
            require(list(value.shape) == tensor_shape(t) and np.all((value >= t['qmin']) & (value <= t['qmax'])),
                    'reference tensor shape/range')
            data = value.astype(DTYPES[t['dtype']]).tobytes()
            require(len(data) == t['logical_bytes'], 'reference tensor byte length')
            path = folder / 'tensors' / ('t%03d.bin' % t['id'])
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            records.append({'id': t['id'], 'name': manifest['tensor_names'][t['id']],
                            'path': path.relative_to(output).as_posix(), 'dtype': DTYPES[t['dtype']],
                            'shape': tensor_shape(t), 'bytes': len(data), 'sha256': digest(data)})
        for head in historical[name]['head_files']:
            record = records[manifest['tensor_names'].index(head['name'])]
            require(record['shape'] == head['shape'] and record['bytes'] == head['bytes'] and
                    record['sha256'] == head['sha256'], 'historical head mismatch: ' + name + '/' + head['name'])
        layers = []
        for op, row in zip(package['ops'], package['operators']):
            if not row['rtl_supported']:
                continue
            directory = folder / 'layers' / ('op%03d' % op['id'])
            directory.mkdir(parents=True)
            words = config_words(package, op['id'])
            raw_params = []
            for i in range(3):
                p = package['params'][op['param' + str(i)]]
                a = p['model_offset'] - manifest['parameter_image_model_offset']
                raw_params.append(package['image'][a:a + p['logical_bytes']])
            data = [(output / records[op['input0']]['path']).read_bytes(), *raw_params,
                    (output / records[op['output']]['path']).read_bytes()]
            segments = {}
            for i, (key, filename, content) in enumerate(zip(
                    ('input', 'weight', 'bias', 'requant', 'output'),
                    ('input.bin', 'weight.bin', 'bias.bin', 'requant.bin', 'expected.bin'), data)):
                path = directory / filename
                path.write_bytes(content)
                require(len(content) == words[17 + i], 'segment/config byte mismatch')
                segments[key] = {'address': BASES[i], 'path': path.relative_to(output).as_posix(),
                                 'bytes': len(content), 'sha256': digest(content)}
            config = directory / 'config.json'
            config_hex = directory / 'config.hex'
            layer = {**row, 'directory': directory.relative_to(output).as_posix(),
                     'config': config.relative_to(output).as_posix(),
                     'config_hex': config_hex.relative_to(output).as_posix(), 'segments': segments}
            write_json(config, {**layer, 'config_words': words})
            config_hex.write_text(''.join('%08x\n' % word for word in words), encoding='ascii')
            layer.update(config_sha256=sha(config), config_hex_sha256=sha(config_hex))
            layers.append(layer)
        cases.append({'name': name, 'directory': folder.relative_to(output).as_posix(),
                      'tensors': records, 'layers': layers, 'historical_heads_checked': len(historical[name]['head_files'])})
        print('LAYER_ASSETS_CASE_PASS ' + name + ' tensors=80 conv_layers=47 heads=9', flush=True)
    for path, expected in runtime_files.items():
        require(sha(path) == expected, 'host runtime input changed: ' + path)
    counts = Counter(op['opcode'] for op in package['ops'])
    result = {'status': 'PASS_HOST_ASSETS_ONLY', 'created_utc': datetime.now(timezone.utc).isoformat(),
              'scope': 'frozen upstream host numeric reference; no RTL execution, physical DDR, board or five-point proof',
              'operators': package['operators'], 'cases': cases,
              'summary': {'operators': len(package['ops']), 'tensors_per_input': len(package['tensors']),
                          'convolutions': counts[1] + counts[2], 'dense': counts[1], 'depthwise': counts[2],
                          'unsupported_operators': sum(v for k, v in counts.items() if k not in (1, 2)),
                          'operator_counts': {OPS[k]: v for k, v in counts.items()},
                          'macs_per_input': sum(row['macs'] for row in package['operators']),
                          'npz_parameter_array_comparisons': comparisons, 'historical_head_hashes_checked': 27},
              'runtime': {'python': sys.version, 'numpy': np.__version__, 'threadpoolctl': threadpoolctl.__version__,
                          'files_sha256': runtime_files}}
    write_json(output / 'worker_result.json', result)
    return result


def prepare(output, npu_root):
    """Export a fresh asset directory using the existing upstream Python runtime."""
    require(__debug__, 'optimized Python disables upstream checks; PASS is prohibited')
    output, npu_root = Path(output).resolve(), Path(npu_root).resolve()
    require(not output.exists(), 'output already exists; refusing to overwrite')
    executable = npu_root / '.venv/Scripts/python.exe'
    require(executable.is_file(), 'existing NPU Python runtime is missing')
    # Product identities are checked against exact baseline Git blobs. Generated
    # program/image bytes are separately bound by the committed package manifest.
    committed = [PACKAGE, NUMERICS, GOLDEN, 'yunet/models/model_manifest.json',
                 'yunet/models/face_detection_yunet_2023mar_original.onnx',
                 'yunet/models/yunet_2023mar_320_bbox.onnx', 'yunet/models/processing_contract_v1.json',
                 'yunet/models/yunet_int8_numeric_v1.npz', 'yunet/models/calibration_manifest_v1.json',
                 'yunet/baseline/ptq_calibration_ranges_v1.json']
    files = subprocess.check_output(['git', '-C', str(npu_root), 'ls-tree', '-r', '--name-only', REVISION,
                                     '--', 'yunet/python'], text=True, encoding='utf-8').splitlines()
    committed += [name for name in files if name.endswith('.py')]
    data_by_name = {}
    for name in committed:
        expected = subprocess.check_output(['git', '-C', str(npu_root), 'show', REVISION + ':' + name])
        data = (npu_root / name).read_bytes()
        require(data == expected, 'upstream file differs from pinned Git baseline: ' + name)
        data_by_name[name] = data
    numeric = json.loads(data_by_name[NUMERICS])
    identities = {numeric['parameters']['path']: numeric['parameters']['sha256'],
                  numeric['source_model']['path']: numeric['source_model']['sha256'],
                  'yunet/models/processing_contract_v1.json': numeric['processing_contract_sha256'],
                  'yunet/models/calibration_manifest_v1.json': numeric['calibration_manifest_sha256'],
                  'yunet/baseline/ptq_calibration_ranges_v1.json': numeric['calibration_ranges_sha256']}
    for name, expected in identities.items():
        require(digest(data_by_name[name]) == expected, 'numeric identity mismatch: ' + name)
    for name in (PROGRAM, IMAGE):
        data_by_name[name] = (npu_root / name).read_bytes()
    decode_package(data_by_name[PROGRAM], data_by_name[IMAGE], json.loads(data_by_name[PACKAGE]))
    output.mkdir(parents=True)
    source_sha256, frozen = {}, []
    for name, data in data_by_name.items():
        target = output / 'frozen_npu' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        original = npu_root / name
        source_sha256[str(original)] = digest(data)
        frozen.append({'source': str(original), 'snapshot': target.relative_to(output).as_posix(),
                       'bytes': len(data), 'sha256': digest(data)})
    driver = output / 'driver/layer_assets.py'
    driver.parent.mkdir()
    driver.write_bytes(Path(__file__).read_bytes())
    own_digest, python_digest = sha(driver), sha(executable)
    source_sha256[str(Path(__file__).resolve())] = own_digest
    frozen.append({'source': str(Path(__file__).resolve()), 'snapshot': driver.relative_to(output).as_posix(),
                   'bytes': driver.stat().st_size, 'sha256': own_digest})
    def verify_inputs():
        require(sha(executable) == python_digest, 'NPU Python executable changed')
        for row in frozen:
            require(sha(row['source']) == row['sha256'] == sha(output / row['snapshot']),
                    'frozen asset changed: ' + row['source'])
    try:
        verify_inputs()
        command = [str(executable), str(driver), '--worker', '--npu-root', str(output / 'frozen_npu'),
                   '--output', str(output)]
        with (output / 'host_reference.log').open('w', encoding='utf-8') as log:
            completed = subprocess.run(command, cwd=output, stdout=log, stderr=subprocess.STDOUT, timeout=300)
        verify_inputs()
        require(completed.returncode == 0, 'frozen upstream host reference failed: ' +
                (output / 'host_reference.log').read_text(encoding='utf-8', errors='replace')[-5000:])
        result = read_json(output / 'worker_result.json')
        verify_generated(output, result)
        result.update(source_sha256=source_sha256, frozen_inputs=frozen, source_unchanged=True,
                      upstream_revision=REVISION,
                      command={'argv': command, 'exit_code': completed.returncode,
                               'log': 'host_reference.log', 'log_sha256': sha(output / 'host_reference.log')},
                      tool={'path': str(executable), 'sha256': python_digest})
        result['artifacts_sha256'] = {path.relative_to(output).as_posix(): sha(path)
                                      for path in output.rglob('*') if path.is_file()}
        verify_inputs()
        verify_generated(output, result)
        write_json(output / 'manifest.json', result)
        return result
    except Exception as exc:
        write_json(output / 'result.json', {'status': 'FAIL', 'error': str(exc), 'source_sha256': source_sha256})
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--npu-root', type=Path, default=ROOT.parent / 'npu_zgtc')
    parser.add_argument('--worker', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    try:
        result = _frozen_worker(args.output, args.npu_root) if args.worker else prepare(args.output, args.npu_root)
        print('LAYER_ASSETS_PASS ' + str(args.output / ('worker_result.json' if args.worker else 'manifest.json')))
        return 0 if result['status'] == 'PASS_HOST_ASSETS_ONLY' else 1
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        print('LAYER_ASSETS_FAIL ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())

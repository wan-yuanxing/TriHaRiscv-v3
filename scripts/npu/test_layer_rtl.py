"""Independent tiny fixtures and genuine simulator rejection checks."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import unittest
from unittest import mock
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_layer_rtl as runner


def tiny_fixture(folder, bad_hash=False):
    layer_dir = folder / 'cases/probe/layers/op000'
    layer_dir.mkdir(parents=True)
    # Two channels, 2x2 input. Weight lanes 0/1 implement x and -x;
    # biases +1/-1 yield asymmetric signed data, independently calculated.
    blobs = {'input': bytes([1, 2, 3, 4]),
             'weight': bytes([1, 255] + [0] * 14),
             'bias': struct.pack('<2i', 1, -1),
             'requant': struct.pack('<4i', 1, 0, 1, 0),
             'output': bytes([2, 3, 4, 5, 254, 253, 252, 251])}
    bases = [0x82800000, 0x82B00000, 0x82C00000, 0x82D00000, 0x83300000]
    words = bases + [2, 2, 1, 2, 2, 2, 1, 1, 0, 0, 0, 2] + [len(b) for b in blobs.values()] + [0] * 10
    if len(words) != 32:
        raise RuntimeError('fixture config size')
    config = layer_dir / 'config.json'
    config.write_text(json.dumps({'config_words': words}) + '\n', encoding='utf-8')
    config_hex = layer_dir / 'config.hex'
    config_hex.write_text(''.join('%08x\n' % word for word in words), encoding='ascii')
    segments = {}
    for i, (name, data) in enumerate(blobs.items()):
        path = layer_dir / ('expected.bin' if name == 'output' else name + '.bin')
        path.write_bytes(data)
        segments[name] = dict(address=bases[i], path=path.relative_to(folder).as_posix(),
                              bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
    if bad_hash:
        segments['weight']['sha256'] = '0' * 64
    layer = dict(operator_id=0, name='IndependentTinyDense', directory=layer_dir.relative_to(folder).as_posix(),
                 config=config.relative_to(folder).as_posix(), config_hex=config_hex.relative_to(folder).as_posix(),
                 config_sha256=runner.sha256(config), config_hex_sha256=runner.sha256(config_hex),
                 input_shape=[1, 1, 2, 2], output_shape=[1, 2, 2, 2], macs=8,
                 no_crop=True, segments=segments)
    manifest = dict(cases=[dict(name='probe', layers=[layer])], operators=[dict(operator_id=0, rtl_supported=True)])
    path = folder / 'manifest.json'
    path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return path, layer


class LayerRtlTests(unittest.TestCase):
    def setUp(self):
        self.folder = ROOT / 'build/npu' / ('layer_runner_test_' + uuid.uuid4().hex[:8])
        self.folder.mkdir(parents=True)

    def test_hex_is_little_endian_and_padded(self):
        source = self.folder / 'data.bin'
        source.write_bytes(bytes(range(19)))
        target = self.folder / 'data.hex'
        runner.pack_lines(source, target)
        self.assertEqual(target.read_text(encoding='ascii').splitlines(),
                         ['0f0e0d0c0b0a09080706050403020100', '00000000000000000000000000121110'])

    def test_path_traversal_rejected(self):
        with self.assertRaisesRegex(ValueError, 'path'):
            runner.asset_path(self.folder, '../escape')

    def test_corrupted_asset_hash_rejected(self):
        path, layer = tiny_fixture(self.folder, bad_hash=True)
        with self.assertRaisesRegex(ValueError, 'hash'):
            runner.validate_layer(self.folder, layer)

    def test_cropped_case_rejected(self):
        path, layer = tiny_fixture(self.folder)
        layer['no_crop'] = False
        with self.assertRaisesRegex(ValueError, 'crop'):
            runner.validate_layer(self.folder, layer)

    def test_geometry_and_lengths_are_cross_checked(self):
        path, layer = tiny_fixture(self.folder)
        layer['output_shape'] = [1, 2, 1, 4]
        with self.assertRaisesRegex(ValueError, 'shape'):
            runner.validate_layer(self.folder, layer)

    def test_unknown_operator_selection_is_failure(self):
        path, layer = tiny_fixture(self.folder / 'assets')
        output = self.folder / 'unknown_operator'
        code = runner.main(['--manifest', str(path), '--ops', '999', '--output', str(output)])
        self.assertEqual(code, 1)
        value = json.loads((output/'result.json').read_text(encoding='utf-8'))
        self.assertEqual(value['status'], 'FAIL')
        self.assertIn('no cases/layers selected', value['error'])

    def test_manifest_is_frozen_before_validation(self):
        manifest, layer = tiny_fixture(self.folder / 'assets')
        output = self.folder / 'manifest_race'
        validate = runner.validate_manifest

        def replace_after_parse(path, **kwargs):
            self.assertNotEqual(path.resolve(), manifest.resolve())
            value = validate(path, **kwargs)
            manifest.write_text('{"cases":[]}', encoding='utf-8')
            return value

        with mock.patch.object(runner, 'validate_manifest', replace_after_parse):
            code = runner.main(['--manifest', str(manifest), '--output', str(output)])
        self.assertEqual(code, 1)
        value = json.loads((output/'result.json').read_text(encoding='utf-8'))
        self.assertIn('changed', value['error'])

    def test_segment_changed_during_freeze_is_rejected(self):
        manifest, layer = tiny_fixture(self.folder / 'assets')
        output = self.folder / 'segment_race'
        external = runner.FrozenInputs.external
        modified = []

        def replace_before_copy(guard, original, frozen):
            if original.name == 'weight.bin' and not modified:
                original.write_bytes(bytes([0])*original.stat().st_size)
                modified.append(str(original))
            return external(guard, original, frozen)

        with mock.patch.object(runner.FrozenInputs, 'external', replace_before_copy):
            code = runner.main(['--manifest', str(manifest), '--output', str(output)])
        self.assertEqual(code, 1)
        self.assertTrue(modified)
        value = json.loads((output/'result.json').read_text(encoding='utf-8'))
        self.assertIn('frozen segment hash mismatch', value['error'])

    def test_optimized_python_is_rejected(self):
        manifest, layer = tiny_fixture(self.folder / 'assets')
        output = self.folder / 'optimized'
        process = subprocess.run([sys.executable, '-O', str(ROOT/'scripts/npu/run_layer_rtl.py'),
                                  '--manifest', str(manifest), '--output', str(output)],
                                 capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(process.returncode, 1)
        value = json.loads((output/'result.json').read_text(encoding='utf-8'))
        self.assertIn('PASS prohibited', value['error'])

    def test_real_simulator_and_corruption_rejection(self):
        path, layer = tiny_fixture(self.folder / 'assets')
        for negative in (False, True):
            output = self.folder / ('negative' if negative else 'green')
            argv = ['--manifest', str(path), '--cases', 'probe', '--ops', '0', '--output', str(output)]
            if negative:
                argv += ['--negative']
            code = runner.main(argv)
            result = json.loads((output / 'result.json').read_text(encoding='utf-8'))
            self.assertEqual(code, 1 if negative else 0)
            self.assertEqual(result['status'], 'FAIL' if negative else 'PARTIAL')
            if negative:
                self.assertIn('NPU_LAYER_FAIL', result['runs'][0]['error'])
            else:
                self.assertEqual(result['runs'][0]['output_bytes'], 8)
                self.assertEqual(result['runs'][0]['compared_bytes'], 8)
                self.assertTrue(result['runs'][0]['full_size'])
                self.assertFalse(result['full_suite_qualified'])


if __name__ == '__main__':
    unittest.main()

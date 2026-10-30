"""Validate real full-shape layer assets and independent malformed wire fixtures."""
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import unittest
from unittest import mock
import uuid

import layer_assets

ROOT = Path(__file__).resolve().parents[2]
NPU = ROOT.parent / 'npu_zgtc'


def tiny_package():
    # One 1x1 dense operator: 1x1x2x2 -> 1x2x2x2, padded Co16 weights.
    header = [0x5055504e, 1, 128, 480, 480, 2, 3, 1, 128, 64, 256, 32,
              352, 128, 0x1060, 1, 1, 3, 1, 1, 1, 0, 4, 16] + [0] * 8
    tensors = [[0, 1, 4, 1, 0, 4, 32, 4, 1, 1, 2, 2, 0, 255, 0xffffffff, 0],
               [1, 2, 4, 2, 32, 8, 32, 8, 1, 2, 2, 2, -127, 127, 0, 0]]
    params = [[0, 1, 0x1000, 16, 32, 16, 0, 0],
              [1, 2, 0x1020, 8, 32, 2, 0, 0],
              [2, 3, 0x1040, 16, 32, 2, 0, 0]]
    op = [0, 1, 0, 1, 0, 0xffffffff, 1, 0, 1, 2, 0xffffffff,
          1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0] + [0] * 5
    wire = b''.join(struct.pack('<' + str(len(row)) + 'I', *(n & 0xffffffff for n in row))
                    for row in [header, *tensors, *params, op])
    image = bytearray(96)
    image[:2] = bytes([1, 255])
    struct.pack_into('<2i', image, 32, 7, -3)
    struct.pack_into('<4i', image, 64, 123, 30, 456, 31)
    manifest = {'program_sha256': hashlib.sha256(wire).hexdigest(),
                'parameter_image_sha256': hashlib.sha256(image).hexdigest(),
                'tensor_names': ['input', 'head'], 'operator_names': ['tinyConv'],
                'parameter_image_model_offset': 0x1000}
    return wire, bytes(image), manifest


class PackageTests(unittest.TestCase):
    def test_independent_fixture_shape_and_mac(self):
        wire, image, manifest = tiny_package()
        package = layer_assets.decode_package(wire, image, manifest)
        row = package['operators'][0]
        self.assertEqual(row['input_shape'], [1, 1, 2, 2])
        self.assertEqual(row['output_shape'], [1, 2, 2, 2])
        self.assertEqual(row['macs'], 8)
        self.assertTrue(row['no_crop'])
        self.assertTrue(row['rtl_supported'])
        words = layer_assets.config_words(package, 0)
        self.assertEqual(words[:17], [0x82800000, 0x82b00000, 0x82c00000,
                                     0x82d00000, 0x83300000, 2, 2, 1, 2, 2, 2,
                                     1, 1, 0, 0, 0, 2])
        self.assertEqual(words[17:22], [4, 16, 8, 16, 8])
        self.assertEqual(len(words), 32)

    def test_corrupted_program_hash_rejected(self):
        wire, image, manifest = tiny_package()
        bad = bytearray(wire)
        bad[-1] ^= 1
        with self.assertRaisesRegex(ValueError, 'program SHA'):
            layer_assets.decode_package(bytes(bad), image, manifest)

    def test_corrupted_parameter_hash_rejected(self):
        wire, image, manifest = tiny_package()
        with self.assertRaisesRegex(ValueError, 'parameter image SHA'):
            layer_assets.decode_package(wire, image[:-1], manifest)

    def test_unknown_opcode_rejected_after_digest_check(self):
        wire, image, manifest = tiny_package()
        bad = bytearray(wire)
        struct.pack_into('<I', bad, 356, 99)
        manifest['program_sha256'] = hashlib.sha256(bad).hexdigest()
        with self.assertRaisesRegex(ValueError, 'opcode'):
            layer_assets.decode_package(bytes(bad), image, manifest)

    def test_truncated_wire_rejected_after_digest_check(self):
        wire, image, manifest = tiny_package()
        wire = wire[:-4]
        manifest['program_sha256'] = hashlib.sha256(wire).hexdigest()
        with self.assertRaisesRegex(ValueError, 'wire length'):
            layer_assets.decode_package(wire, image, manifest)

    def test_tensor_span_mismatch_rejected(self):
        wire, image, manifest = tiny_package()
        bad = bytearray(wire)
        struct.pack_into('<I', bad, 128 + 20, 5)
        manifest['program_sha256'] = hashlib.sha256(bad).hexdigest()
        with self.assertRaisesRegex(ValueError, 'tensor length'):
            layer_assets.decode_package(bytes(bad), image, manifest)


class RealPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.output = ROOT / 'build/npu' / ('layer_assets_test_' + uuid.uuid4().hex[:8])
        cls.manifest = layer_assets.prepare(cls.output, NPU)

    def test_all_three_inputs_all_tensors_and_full_layers(self):
        manifest = self.manifest
        self.assertEqual(manifest['status'], 'PASS_HOST_ASSETS_ONLY')
        self.assertEqual(len(manifest['operators']), 79)
        self.assertEqual(manifest['summary']['convolutions'], 47)
        self.assertEqual(manifest['summary']['dense'], 30)
        self.assertEqual(manifest['summary']['depthwise'], 17)
        self.assertEqual(manifest['summary']['macs_per_input'], 84523000)
        self.assertEqual(manifest['summary']['unsupported_operators'], 32)
        self.assertEqual([case['name'] for case in manifest['cases']], ['zero', 'full255', 'pattern'])
        for case in manifest['cases']:
            self.assertEqual(len(case['tensors']), 80)
            self.assertEqual(len(case['layers']), 47)
            self.assertEqual(case['historical_heads_checked'], 9)
            conv0 = case['layers'][0]
            self.assertEqual(conv0['input_shape'], [1, 3, 320, 320])
            self.assertEqual(conv0['output_shape'], [1, 16, 160, 160])
            self.assertEqual(conv0['segments']['input']['bytes'], 307200)
            self.assertEqual(conv0['segments']['output']['bytes'], 409600)
            for layer in case['layers']:
                self.assertTrue(layer['no_crop'])
                words = [int(line, 16) for line in (self.output / layer['config_hex']).read_text().splitlines()]
                self.assertEqual(len(words), 32)
                for key, index in [('input', 17), ('weight', 18), ('bias', 19), ('requant', 20), ('output', 21)]:
                    segment = layer['segments'][key]
                    data = (self.output / segment['path']).read_bytes()
                    self.assertEqual(len(data), words[index])
                    self.assertEqual(hashlib.sha256(data).hexdigest(), segment['sha256'])

    def test_existing_output_is_never_overwritten(self):
        before = (self.output / 'manifest.json').read_bytes()
        with self.assertRaisesRegex(ValueError, 'exists'):
            layer_assets.prepare(self.output, NPU)
        self.assertEqual((self.output / 'manifest.json').read_bytes(), before)

    def test_changed_expected_output_before_seal_is_rejected(self):
        output = ROOT / 'build/npu' / ('layer_assets_output_race_' + uuid.uuid4().hex[:8])
        real_run = subprocess.run
        def run(*args, **kwargs):
            completed = real_run(*args, **kwargs)
            if '--worker' in args[0]:
                path = output / 'cases/pattern/layers/op042/expected.bin'
                data = bytearray(path.read_bytes())
                data[0] ^= 1
                path.write_bytes(data)
            return completed
        with mock.patch.object(subprocess, 'run', run):
            with self.assertRaisesRegex(ValueError, 'generated asset changed'):
                layer_assets.prepare(output, NPU)
        value = json.loads((output / 'result.json').read_text(encoding='utf-8'))
        self.assertEqual(value['status'], 'FAIL')
        self.assertFalse((output / 'manifest.json').exists())

    def test_changed_frozen_upstream_before_seal_is_rejected(self):
        output = ROOT / 'build/npu' / ('layer_assets_frozen_race_' + uuid.uuid4().hex[:8])
        real_run = subprocess.run
        def run(*args, **kwargs):
            completed = real_run(*args, **kwargs)
            if '--worker' in args[0]:
                path = output / 'frozen_npu/yunet/python/ptq_integer.py'
                path.write_bytes(path.read_bytes() + b'\n# frozen input edit probe\n')
            return completed
        with mock.patch.object(subprocess, 'run', run):
            with self.assertRaisesRegex(ValueError, 'frozen asset changed'):
                layer_assets.prepare(output, NPU)
        self.assertFalse((output / 'manifest.json').exists())

    def test_changed_original_driver_before_seal_is_rejected(self):
        output = ROOT / 'build/npu' / ('layer_assets_source_race_' + uuid.uuid4().hex[:8])
        source = ROOT / 'build/npu' / ('layer_assets_driver_' + uuid.uuid4().hex[:8] + '.py')
        source.write_bytes(Path(layer_assets.__file__).read_bytes())
        real_run = subprocess.run
        def run(*args, **kwargs):
            completed = real_run(*args, **kwargs)
            if '--worker' in args[0]:
                source.write_bytes(source.read_bytes() + b'\n# source input edit probe\n')
            return completed
        with mock.patch.object(layer_assets, '__file__', str(source)), mock.patch.object(subprocess, 'run', run):
            with self.assertRaisesRegex(ValueError, 'frozen asset changed'):
                layer_assets.prepare(output, NPU)
        self.assertFalse((output / 'manifest.json').exists())

    def test_optimized_python_has_no_pass_qualification(self):
        output = ROOT / 'build/npu' / ('layer_assets_optimized_' + uuid.uuid4().hex[:8])
        completed = subprocess.run([str(NPU / '.venv/Scripts/python.exe'), '-O', layer_assets.__file__,
                                    '--output', str(output)], capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(completed.returncode, 1)
        self.assertIn('PASS is prohibited', completed.stderr)
        self.assertFalse(output.exists())


if __name__ == '__main__': unittest.main()

"""TDD gates for real B03 frame runner evidence, not replacement RTL tests."""
import hashlib
import importlib
from pathlib import Path
import struct
import tempfile
import unittest
import zlib


class FrameRunnerTests(unittest.TestCase):
    def setUp(self):
        try:
            self.runner = importlib.import_module('run_b03_frame')
        except ModuleNotFoundError:
            self.runner = None
        self.assertIsNotNone(self.runner, 'B03 frame runner is missing')
        self.temp = tempfile.TemporaryDirectory(prefix='triha_b03_frame_')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_asset_tamper_rejected_before_use(self):
        (self.root / 'input.bin').write_bytes(b'tamper')
        with self.assertRaisesRegex(ValueError, 'asset SHA'):
            self.runner.checked_asset(self.root, 'input.bin', {'input.bin': hashlib.sha256(b'original').hexdigest()})

    def test_missing_asset_rejected(self):
        with self.assertRaisesRegex(ValueError, 'missing asset'):
            self.runner.checked_asset(self.root, 'missing.bin', {'missing.bin': '0' * 64})

    def test_log_requires_pass_and_clean_summary(self):
        clean = '# Errors: 0, Warnings: 0\n# PASS UNIT\n'
        self.runner.check_log(clean, ['PASS UNIT'])
        for bad in ['# Errors: 0, Warnings: 0\n', '# PASS UNIT\n',
                    clean + '# ** Warning: ignored input\n', clean + '# ** Fatal: stopped\n',
                    clean + '# Errors: 1, Warnings: 0\n']:
            with self.subTest(text=bad), self.assertRaises(ValueError):
                self.runner.check_log(bad, ['PASS UNIT'])

    def test_unknown_output_hex_rejected(self):
        p = self.root / 'out.hex'
        p.write_text('00\nxx\n', encoding='ascii')
        with self.assertRaisesRegex(ValueError, 'hex'):
            self.runner.read_hex_bytes(p)

    def make_result(self):
        record = struct.pack('<8I', 1, 2, 3, 4, 0x3f400000, 5, 8, 0)
        words = [0] * 32
        words[:16] = [0x3352504e, 1, 128, 1, 0, 0, 100, 77, 1000, 0, 1, 32,
                      zlib.crc32(record), 0x900080, 0x654dbb39, 0]
        words[16:22] = [200, 0, 150, 0, 40, 0]
        words[22:29] = [320, 320, 320, 320, 0, 0, 1]
        words[31] = zlib.crc32(struct.pack('<31I', *words[:31]))
        return bytes(26368), struct.pack('<32I', *words) + record, record

    def test_independent_result_validation(self):
        head, result, records = self.make_result()
        checked = self.runner.verify_result_bytes(head, result, head, records, 0)
        self.assertEqual(checked['faces'], 1)

    def test_head_difference_rejected(self):
        head, result, records = self.make_result()
        with self.assertRaisesRegex(ValueError, 'HEAD'):
            self.runner.verify_result_bytes(b'\x01' + head[1:], result, head, records, 0)

    def test_private_header_crc_rejected(self):
        head, result, records = self.make_result()
        result = bytearray(result)
        result[64] ^= 1
        with self.assertRaisesRegex(ValueError, 'header CRC'):
            self.runner.verify_result_bytes(head, result, head, records, 0)

    def test_records_difference_rejected(self):
        head, result, records = self.make_result()
        with self.assertRaisesRegex(ValueError, 'records'):
            self.runner.verify_result_bytes(head, result[:-1] + b'\x01', head, records, 0)

    def test_valid_crc_wrong_identity_rejected(self):
        head, result, records = self.make_result()
        words = list(struct.unpack('<32I', result[:128]))
        words[6] = 999
        words[31] = zlib.crc32(struct.pack('<31I', *words[:31]))
        with self.assertRaisesRegex(ValueError, 'identity'):
            self.runner.verify_result_bytes(head, struct.pack('<32I', *words) + records, head, records, 0)

    def test_existing_run_directory_rejected(self):
        with self.assertRaisesRegex(ValueError, 'fresh'):
            self.runner.run(self.root, 'control')


class TestImportTests(unittest.TestCase):
    def test_git_test_closure_preserves_payload_test_and_bridge(self):
        try:
            module = importlib.import_module('import_b03_tests')
        except ModuleNotFoundError:
            module = None
        self.assertIsNotNone(module, 'B03 test importer is missing')
        repo = Path('D:/FPGA/npu_zgtc')
        if not repo.is_dir():
            self.skipTest('local frozen source repository unavailable')
        manifest, blobs = module.plan(repo)
        self.assertEqual(manifest['source_commit'], '558280b30219acdcf9f962acd6e907e0f680ab52')
        self.assertEqual(len(blobs), 15)
        self.assertIn('Testbench/platform/b03_full_frame_payload_driver.svh', blobs)
        self.assertIn('rtl/platform/npu_session_mem_bridge_burst.v', blobs)
        self.assertNotIn('rtl/platform/b03_frame_exec_payload.v', blobs)
        with tempfile.TemporaryDirectory(prefix='triha_b03_testimport_') as temp:
            module.materialize(Path(temp), manifest, blobs)
            module.verify(Path(temp))
            path = Path(temp) / module.DESTINATION / 'Testbench/platform/tb_b03_full_frame_payload.sv'
            path.write_bytes(path.read_bytes() + b'//changed\n')
            with self.assertRaisesRegex(ValueError, 'SHA'):
                module.verify(Path(temp))


if __name__ == '__main__':
    unittest.main()

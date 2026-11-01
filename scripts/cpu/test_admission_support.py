"""Source and archive corruption must be rejected before running a simulator."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


class SupportTests(unittest.TestCase):
    def setUp(self):
        script = Path(__file__).with_name('admission_common.py')
        self.assertTrue(script.exists(), 'local admission helper is missing')
        spec = importlib.util.spec_from_file_location('admission_common', script)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'config').mkdir()
        (self.root / 'core.v').write_bytes(b'core bytes\r\n')
        self.manifest = {'files': [{'destination': 'core.v',
                                   'sha256': hashlib.sha256(b'core bytes\r\n').hexdigest()}],
                         'simulation_models': []}
        self.save()

    def save(self):
        (self.root / 'config/cpu_admission.json').write_text(json.dumps(self.manifest), encoding='utf-8')

    def test_validate_runs_without_source_checkout(self):
        self.assertEqual(self.module.validate(self.root)['files'], self.manifest['files'])

    def test_admitted_source_corruption_is_rejected(self):
        (self.root / 'core.v').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'admitted source hash mismatch'):
            self.module.validate(self.root)

    def test_vendor_primitive_corruption_is_rejected(self):
        model = self.root / 'model.v'
        model.write_bytes(b'changed')
        self.manifest['simulation_models'] = [{'path': str(model), 'sha256': '0' * 64}]
        self.save()
        with self.assertRaisesRegex(ValueError, 'primitive hash mismatch'):
            self.module.validate(self.root)

    def test_wrong_archive_hash_rejected_before_staging(self):
        archive = self.root / 'input.zip'
        archive.write_bytes(b'not the admitted archive')
        self.manifest['isa_archive'] = {'path': 'input.zip', 'sha256': '0' * 64}
        self.save()
        target = self.root / 'stage'
        with self.assertRaisesRegex(ValueError, 'ISA archive hash mismatch'):
            self.module.prepare_isa_inputs(self.root, target)
        self.assertFalse(target.exists())


if __name__ == '__main__':
    unittest.main()

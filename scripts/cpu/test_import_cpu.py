"""Exercise the source admission boundary using real temporary Git repositories."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('import_cpu.py')


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.destination = self.root / 'destination'
        self.source.mkdir()
        self.destination.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.email', 'cpu-test@example.invalid')
        self.git('config', 'user.name', 'CPU admission test')
        self.git('config', 'core.autocrlf', 'false')
        self.files = {'rtl/cpu/vendor/test.v': b'original\r\n\x00tail',
                      'rtl/cpu/triha_csr.v': b'old csr\n'}
        for name, data in self.files.items():
            target = self.source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        self.git('add', '--', 'rtl')
        self.git('commit', '-qm', 'fixture')
        self.revision = self.git('rev-parse', 'HEAD').strip()
        self.manifest = {'schema_version': 1, 'source_commit': self.revision,
                         'files': [self.entry(name, data) for name, data in self.files.items()]}

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.source), *args]).decode()

    def entry(self, name, data, **extra):
        return dict(source=name, destination=name, sha256=hashlib.sha256(data).hexdigest(),
                    source_kind='git', **extra)

    def run_import(self, apply=False):
        manifest = self.root / 'manifest.json'
        manifest.write_text(json.dumps(self.manifest), encoding='utf-8')
        command = [sys.executable, str(SCRIPT), '--source-root', str(self.source),
                   '--destination-root', str(self.destination), '--manifest', str(manifest)]
        if apply:
            command.append('--apply')
        return subprocess.run(command, capture_output=True, text=True)

    def rejected(self, reason):
        result = self.run_import(True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(reason, result.stdout + result.stderr)

    def test_dry_run_does_not_write(self):
        result = self.run_import()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_exact_git_bytes_and_idempotent_import(self):
        # Unreviewed source checkout changes must not contaminate Git admission.
        (self.source / 'rtl/cpu/vendor/test.v').write_bytes(b'dirty checkout')
        for _ in range(2):
            result = self.run_import(True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for name, data in self.files.items():
                self.assertEqual((self.destination / name).read_bytes(), data)

    def test_source_hash_failure_prevents_every_write(self):
        self.manifest['files'][1]['sha256'] = '0' * 64
        self.rejected('source hash mismatch')
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_collision_preserves_user_edit_and_prevents_partial_import(self):
        target = self.destination / 'rtl/cpu/triha_csr.v'
        target.parent.mkdir(parents=True)
        target.write_bytes(b'user edit')
        self.rejected('destination conflict')
        self.assertEqual(target.read_bytes(), b'user edit')
        self.assertFalse((self.destination / 'rtl/cpu/vendor/test.v').exists())

    def test_paths_cannot_escape_or_use_windows_ambiguous_names(self):
        for bad in ['../escape', '/absolute', 'C:/escape', 'rtl\\escape',
                    'rtl/cpu/../escape', 'rtl/cpu/file:stream', 'rtl/cpu/CON.v']:
            with self.subTest(path=bad):
                self.manifest['files'][0]['destination'] = bad
                self.rejected('unsafe path')

    def test_case_insensitive_duplicate_destinations_rejected(self):
        self.manifest['files'][1]['destination'] = 'RTL/CPU/VENDOR/TEST.V'
        self.rejected('duplicate destination')

    def test_reviewed_csr_delta_requires_accepted_base_hash(self):
        name = 'rtl/cpu/triha_csr.v'
        updated = b'corrected csr\n'
        (self.source / name).write_bytes(updated)
        row = self.manifest['files'][1]
        row.update(source_kind='reviewed_working_tree', sha256=hashlib.sha256(updated).hexdigest(),
                   base_sha256=hashlib.sha256(self.files[name]).hexdigest())
        result = self.run_import(True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.destination / name).read_bytes(), updated)

    def test_reviewed_csr_wrong_base_is_rejected(self):
        row = self.manifest['files'][1]
        row.update(source_kind='reviewed_working_tree', base_sha256='0' * 64)
        self.rejected('base hash mismatch')

    def test_unreviewed_production_delta_is_rejected(self):
        self.manifest['files'][0].update(source_kind='reviewed_working_tree',
                                        base_sha256=self.manifest['files'][0]['sha256'])
        self.rejected('unapproved production delta')

    def test_test_source_cannot_disguise_vendor_replacement(self):
        source = self.source / 'tb/cpu/fixture.v'
        source.parent.mkdir(parents=True)
        source.write_bytes(b'replacement')
        self.manifest['files'][0].update(source='tb/cpu/fixture.v',
                                        source_kind='reviewed_working_tree',
                                        sha256=hashlib.sha256(source.read_bytes()).hexdigest())
        self.rejected('unapproved production delta')

    def test_windows_case_cannot_disguise_production_delta(self):
        self.manifest['files'][0].update(source='RTL/CPU/VENDOR/TEST.V',
                                        destination='RTL/CPU/VENDOR/TEST.V',
                                        source_kind='reviewed_working_tree')
        self.rejected('unapproved production delta')


if __name__ == '__main__':
    unittest.main()

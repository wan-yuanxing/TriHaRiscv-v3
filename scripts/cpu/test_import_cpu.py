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

    def test_file_revision_overrides_global_without_dirty_checkout_bytes(self):
        name = 'rtl/cpu/vendor/test.v'
        updated = b'new pinned implementation\n'
        (self.source / name).write_bytes(updated)
        self.git('add', '--', name)
        self.git('commit', '-qm', 'new implementation')
        newer = self.git('rev-parse', 'HEAD').strip()
        self.manifest['files'][0].update(source_commit=newer,
                                        sha256=hashlib.sha256(updated).hexdigest())
        (self.source / name).write_bytes(b'unreviewed dirty source')
        result = self.run_import(True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.destination / name).read_bytes(), updated)
        self.assertEqual((self.destination / 'rtl/cpu/triha_csr.v').read_bytes(),
                         self.files['rtl/cpu/triha_csr.v'])

    def test_mutable_file_revision_prevents_all_writes(self):
        self.manifest['files'][1]['source_commit'] = 'HEAD'
        self.rejected('immutable file source commit')
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_reviewed_delta_base_uses_its_own_pinned_revision(self):
        name = 'rtl/cpu/triha_csr.v'
        base = b'new revision base\n'
        (self.source / name).write_bytes(base)
        self.git('add', '--', name)
        self.git('commit', '-qm', 'new csr base')
        newer = self.git('rev-parse', 'HEAD').strip()
        updated = b'main integration fix\n'
        (self.source / name).write_bytes(updated)
        self.manifest['files'][1].update(source_kind='reviewed_working_tree',
            source_commit=newer, base_sha256=hashlib.sha256(base).hexdigest(),
            sha256=hashlib.sha256(updated).hexdigest())
        result = self.run_import(True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.destination / name).read_bytes(), updated)

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

    def header_fixture(self, original, cleaned):
        name = 'rtl/cpu/vendor/test.v'
        (self.source / name).write_bytes(original)
        self.git('add', '--', name)
        self.git('commit', '-qm', 'header fixture')
        self.manifest['source_commit'] = self.git('rev-parse', 'HEAD').strip()
        self.manifest['files'] = [self.entry(name, cleaned, header_comment_cleanup={
            'algorithm': 'leading-notice-v1',
            'source_sha256': hashlib.sha256(original).hexdigest()})]
        return name

    def test_header_cleanup_replays_from_exact_original_git_bytes(self):
        original = (b'//-----\r\n// Copyright 2000 fixture\r\n'
                    b'// Licensed under the Apache License, Version 2.0\r\n//-----\r\n'
                    b'\r\n// Keep this functional description.\r\nmodule test; endmodule\r\n')
        cleaned = b'\r\n// Keep this functional description.\r\nmodule test; endmodule\r\n'
        name = self.header_fixture(original, cleaned)
        for _ in range(2):
            result = self.run_import(True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((self.destination / name).read_bytes(), cleaned)

    def test_mixed_header_preserves_function_description_and_encoding(self):
        original = (b'/*\r\n * @brief Keep byte \xff and the module description.\r\n'
                    b' * SPDX-License-Identifier: Apache-2.0\r\n'
                    b' * Copyright 2000 fixture\r\n */\r\nmodule test; endmodule\r\n')
        cleaned = (b'/*\r\n * @brief Keep byte \xff and the module description.\r\n'
                   b' */\r\nmodule test; endmodule\r\n')
        name = self.header_fixture(original, cleaned)
        result = self.run_import(True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.destination / name).read_bytes(), cleaned)

    def test_header_cleanup_rejects_wrong_original_hash_before_writing(self):
        self.header_fixture(b'// Copyright 2000 fixture\nmodule test; endmodule\n', b'module test; endmodule\n')
        self.manifest['files'][0]['header_comment_cleanup']['source_sha256'] = '0' * 64
        self.rejected('cleanup base hash mismatch')
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_header_cleanup_does_not_strip_strings_or_interior_comments(self):
        original = b'module test; initial $display("// Copyright fixture"); /* Copyright fixture */ endmodule\n'
        self.header_fixture(original, b'module test; endmodule\n')
        self.rejected('no supported leading notice')
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_secondary_module_header_notice_is_relocated(self):
        original = (b'module a;\nendmodule\n\n// Copyright 2000 fixture\n'
                    b'// Licensed under the Apache License, Version 2.0\n'
                    b'// SPDX-License-Identifier: Apache-2.0\n'
                    b'// Keep the mux description.\nmodule b; endmodule\n')
        cleaned = b'module a;\nendmodule\n\n// Keep the mux description.\nmodule b; endmodule\n'
        name = self.header_fixture(original, cleaned)
        result = self.run_import(True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.destination / name).read_bytes(), cleaned)

    def test_v2_relocates_full_secondary_notice_across_blank_lines(self):
        notice = (b'//-----------------------------------------------------------------\r\n'
                  b'//                         biRISC-V CPU\r\n'
                  b'// Copyright 2020 fixture\r\n'
                  b'// Licensed under the Apache License, Version 2.0\r\n'
                  b'// limitations under the License.\r\n'
                  b'//-----------------------------------------------------------------\r\n')
        original = (b'module a;\r\nendmodule\r\n\r\n'
                    b'// Keep functional description.\r\n' + notice +
                    b'\r\n// Keep interface description.\r\nmodule b; endmodule\r\n')
        cleaned = original.replace(notice, b'')
        name = self.header_fixture(original, cleaned)
        self.manifest['files'][0]['header_comment_cleanup']['algorithm'] = 'module-notice-v2'
        result = self.run_import(True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.destination / name).read_bytes(), cleaned)


if __name__ == '__main__':
    unittest.main()

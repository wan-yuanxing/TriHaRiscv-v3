"""Fail-closed tests for B03 historical-asset recovery (host evidence only)."""
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


def sha(data):
    return hashlib.sha256(data).hexdigest()


class B03AssetsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='triha_b03_')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.assets = self.root / 'assets'
        self.assets.mkdir()
        names = ['program.bin', 'parameter_image.bin', 'post_table.bin']
        for case in ('zero', 'full255', 'pattern', 'calibration_image_000', 'wider_stress_0', 'wider_stress_1'):
            names += [f'cases/{case}/{leaf}' for leaf in ('input.bin', 'heads_golden.bin', 'records_golden.bin', 'task.bin')]
        names += [f'evidence/file{i}.json' for i in range(68 - len(names))]
        self.manifest = {'version': 'b03-runtime-assets-v1', 'passed': True,
                         'files_sha256': {}, 'source_sha256': {'yunet/python/compiler.py': sha(b'source')}}
        for i, name in enumerate(names):
            data = ('original ' + str(i)).encode()
            p = self.assets / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
            self.manifest['files_sha256'][name] = sha(data)
        self.manifest_path = self.root / 'historical.json'

    def module(self, name):
        try:
            module = importlib.import_module(name)
        except ModuleNotFoundError:
            module = None
        self.assertIsNotNone(module, f'{name} recovery implementation is missing')
        return module

    def audit(self):
        raw = json.dumps(self.manifest).encode()
        self.manifest_path.write_bytes(raw)
        return self.module('audit_b03_assets').audit_assets(
            self.assets, self.manifest_path, expected_manifest_sha256=sha(raw))

    def test_complete_byte_set_is_host_only(self):
        report = self.audit()
        self.assertEqual(report['status'], 'PASS_HOST_ASSETS_ONLY')
        self.assertEqual(report['matched_count'], 68)
        self.assertFalse(report['RTL_executed'])
        self.assertFalse(report['board_verified'])
        self.assertEqual(report['runtime_ready_cases'], ['zero', 'full255', 'pattern', 'calibration_image_000', 'wider_stress_0', 'wider_stress_1'])

    def test_missing_natural_input_is_partial_not_success(self):
        (self.assets / 'cases/wider_stress_1/input.bin').unlink()
        report = self.audit()
        self.assertEqual(report['status'], 'PARTIAL')
        self.assertIn('cases/wider_stress_1/input.bin', report['missing'])
        self.assertNotIn('wider_stress_1', report['runtime_ready_cases'])

    def test_changed_bytes_are_failure_even_with_missing_assets(self):
        (self.assets / 'program.bin').write_bytes(b'tampered')
        (self.assets / 'cases/wider_stress_1/input.bin').unlink()
        report = self.audit()
        self.assertEqual(report['status'], 'FAIL')
        self.assertEqual(report['mismatches'][0]['path'], 'program.bin')
        self.assertEqual(report['runtime_ready_cases'], [])

    def test_wrong_schema_rejected(self):
        self.manifest['version'] = 'b02-assets'
        with self.assertRaisesRegex(ValueError, 'version'):
            self.audit()

    def test_required_case_entry_cannot_be_dropped(self):
        entry = self.manifest['files_sha256'].pop('cases/zero/input.bin')
        self.manifest['files_sha256']['other.bin'] = entry
        with self.assertRaisesRegex(ValueError, 'required'):
            self.audit()

    def test_untrusted_manifest_cannot_redefine_identity(self):
        self.manifest_path.write_text(json.dumps(self.manifest), encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'manifest SHA'):
            self.module('audit_b03_assets').audit_assets(self.assets, self.manifest_path,
                                                        expected_manifest_sha256='0' * 64)

    def test_path_escape_rejected(self):
        entry = self.manifest['files_sha256'].pop('evidence/file0.json')
        self.manifest['files_sha256']['../outside.bin'] = entry
        with self.assertRaisesRegex(ValueError, 'unsafe'):
            self.audit()

    def test_bad_digest_rejected(self):
        self.manifest['files_sha256']['program.bin'] = 'not a digest'
        with self.assertRaisesRegex(ValueError, 'digest'):
            self.audit()

    def test_incomplete_historical_inventory_rejected(self):
        self.manifest['files_sha256'].pop('evidence/file0.json')
        with self.assertRaisesRegex(ValueError, '68'):
            self.audit()

    def test_cli_invalidates_old_pass_when_manifest_is_broken(self):
        self.audit()
        self.manifest_path.write_bytes(b'{}')
        report = self.root / 'audit.json'
        report.write_text('{"status":"PASS_HOST_ASSETS_ONLY"}', encoding='utf-8')
        script = Path(__file__).with_name('audit_b03_assets.py')
        result = subprocess.run([sys.executable, str(script), '--assets', str(self.assets),
                                 '--manifest', str(self.manifest_path), '--output', str(report)],
                                capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(report.read_bytes())['status'], 'FAIL')

    def test_cli_report_cannot_overwrite_historical_manifest(self):
        self.audit()
        before = self.manifest_path.read_bytes()
        script = Path(__file__).with_name('audit_b03_assets.py')
        result = subprocess.run([sys.executable, str(script), '--assets', str(self.assets),
                                 '--manifest', str(self.manifest_path), '--output', str(self.manifest_path)],
                                capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.manifest_path.read_bytes(), before)


class B03FreezeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='triha_b03_freeze_')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        try:
            self.impl = importlib.import_module('prepare_b03_assets')
        except ModuleNotFoundError:
            self.impl = None
        self.assertIsNotNone(self.impl, 'prepare_b03_assets recovery implementation is missing')

    def test_freeze_rejects_bad_source_before_writing(self):
        src, dst = self.root / 'source.bin', self.root / 'frozen.bin'
        src.write_bytes(b'tamper')
        with self.assertRaisesRegex(ValueError, 'SHA'):
            self.impl.freeze_file(src, dst, sha(b'original'))
        self.assertFalse(dst.exists())

    def test_frozen_copy_survives_source_change_but_detects_own_tamper(self):
        src, dst = self.root / 'source.bin', self.root / 'frozen.bin'
        src.write_bytes(b'original')
        self.impl.freeze_file(src, dst, sha(b'original'))
        src.write_bytes(b'later mutable checkout')
        self.impl.verify_frozen(self.root, {'frozen.bin': sha(b'original')})
        dst.write_bytes(b'tampered snapshot')
        with self.assertRaisesRegex(ValueError, 'frozen'):
            self.impl.verify_frozen(self.root, {'frozen.bin': sha(b'original')})

    def test_freeze_refuses_overwrite(self):
        src, dst = self.root / 'source.bin', self.root / 'frozen.bin'
        src.write_bytes(b'original')
        dst.write_bytes(b'prior evidence')
        with self.assertRaisesRegex(ValueError, 'exists'):
            self.impl.freeze_file(src, dst, sha(b'original'))
        self.assertEqual(dst.read_bytes(), b'prior evidence')

    def test_git_freeze_uses_commit_object_not_dirty_checkout(self):
        repo = self.root / 'repo'
        repo.mkdir()
        def git(*args):
            return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.DEVNULL)
        git('init', '-q')
        (repo / 'reference.py').write_bytes(b'original\n')
        git('add', 'reference.py')
        git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture')
        revision = git('rev-parse', 'HEAD').decode().strip()
        (repo / 'reference.py').write_bytes(b'dirty checkout\n')
        dest = self.root / 'snapshot'
        records = self.impl.freeze_git_inputs(repo, revision, ['reference.py'], dest,
                                             {'reference.py': sha(b'original\n')})
        self.assertEqual((dest / 'reference.py').read_bytes(), b'original\n')
        self.assertEqual(records['reference.py'], sha(b'original\n'))
        self.assertEqual((repo / 'reference.py').read_bytes(), b'dirty checkout\n')

    def test_mutable_git_ref_rejected(self):
        with self.assertRaisesRegex(ValueError, 'full commit'):
            self.impl.freeze_git_inputs(self.root, 'HEAD', [], self.root / 'snapshot', {})

    def test_generator_never_writes_nonmatching_historical_output(self):
        target = self.root / 'assets'
        target.mkdir()
        writer = getattr(self.impl, 'write_historical', None)
        self.assertTrue(callable(writer), 'historical-byte guarded writer is missing')
        with self.assertRaisesRegex(ValueError, 'historical'):
            writer(target, 'program.bin', b'wrong', {'program.bin': sha(b'original')})
        self.assertFalse((target / 'program.bin').exists())
        writer(target, 'program.bin', b'original', {'program.bin': sha(b'original')})
        self.assertEqual((target / 'program.bin').read_bytes(), b'original')

    def test_search_accepts_hash_identity_not_similar_filename(self):
        good, bad = self.root / 'different_name.bin', self.root / 'program.bin'
        good.write_bytes(b'original')
        bad.write_bytes(b'wrong')
        finder = getattr(self.impl, 'find_historical_files', None)
        self.assertTrue(callable(finder), 'historical asset discovery is missing')
        found = finder([self.root], {sha(b'original')}, suffixes={'.bin'})
        self.assertEqual(found[sha(b'original')], good.resolve())

    def test_recovery_refuses_existing_output(self):
        prepare = getattr(self.impl, 'prepare', None)
        self.assertTrue(callable(prepare), 'B03 recovery orchestration is missing')
        with self.assertRaisesRegex(ValueError, 'output already exists'):
            prepare(self.root, self.root)


class B03RealRecoveryTests(unittest.TestCase):
    @unittest.skipUnless(Path('D:/FPGA/npu_zgtc/.venv/Scripts/python.exe').is_file(),
                         'existing local numeric runtime unavailable')
    def test_frozen_upstream_recovers_exact_core_and_synthetic_cases(self):
        import uuid
        module = importlib.import_module('prepare_b03_assets')
        prepare = getattr(module, 'prepare', None)
        self.assertTrue(callable(prepare), 'B03 recovery orchestration is missing')
        out = Path(__file__).resolve().parents[2] / 'build/npu' / ('b03_assets_test_' + uuid.uuid4().hex[:8])
        report = prepare(out, Path('D:/FPGA/npu_zgtc'), search_roots=[])
        self.assertEqual(report['status'], 'PARTIAL')
        self.assertTrue(report['core_ready'])
        self.assertEqual(report['runtime_ready_cases'], ['zero', 'full255', 'pattern'])
        self.assertEqual(report['mismatches'], [])
        self.assertTrue((out / 'assets/ops.hex').is_file())
        self.assertEqual(report['host_reference']['tensor_comparisons'], 237)
        self.assertFalse(report['RTL_executed'])
        # Current sources must remain bound when the result is re-audited.
        module.verify_frozen(out / 'frozen_upstream', report['frozen_sources_sha256'])


if __name__ == '__main__':
    unittest.main()

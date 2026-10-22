"""Preflight must reject drift and invalid memory attributes before EDA starts."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from check_cache import validate

ROOT = Path(__file__).resolve().parents[2]


class CachePreflightTests(unittest.TestCase):
    def copy(self):
        temporary = tempfile.TemporaryDirectory(prefix='cache-preflight-', dir=ROOT/'build/cpu')
        target = Path(temporary.name)
        assert target.resolve().is_relative_to((ROOT/'build/cpu').resolve())
        self.addCleanup(temporary.cleanup)
        for name in validate(ROOT)['validated_paths']:
            path = target/name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/name, path)
        return target

    def test_real_tree_is_bound(self):
        row = validate(ROOT)
        self.assertEqual(row['status'], 'PASS')
        self.assertEqual(row['original_counts'], [28, 9, 7])

    def test_derived_byte_change_is_rejected(self):
        target = self.copy()
        with (target/'rtl/cpu/triha_dcache.v').open('ab') as stream:
            stream.write(b'\n// changed\n')
        with self.assertRaisesRegex(ValueError, 'derived'):
            validate(target)

    def test_original_byte_change_is_rejected(self):
        target = self.copy()
        (target/'rtl/cpu/vendor/src/icache/icache.v').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'original'):
            validate(target)

    def test_shared_region_cannot_be_cacheable(self):
        target = self.copy()
        path = target/'config/cpu_cache.json'
        cfg = json.loads(path.read_text(encoding='utf-8'))
        cfg['private_ddr_bytes'] = 0x8000000
        path.write_text(json.dumps(cfg), encoding='utf-8', newline='\n')
        with self.assertRaisesRegex(ValueError, 'address'):
            validate(target)

    def test_writeback_policy_is_explicitly_bound(self):
        target = self.copy()
        path = target/'config/cpu_cache.json'
        cfg = json.loads(path.read_text(encoding='utf-8'))
        cfg['dcache']['write_policy'] = 'write_back'
        cfg['dcache']['write_allocate'] = True
        path.write_text(json.dumps(cfg), encoding='utf-8', newline='\n')
        self.assertEqual(validate(target)['status'], 'PASS')

    def test_writeback_requires_write_allocate(self):
        target = self.copy()
        path = target/'config/cpu_cache.json'
        cfg = json.loads(path.read_text(encoding='utf-8'))
        cfg['dcache']['write_policy'] = 'write_back'
        cfg['dcache']['write_allocate'] = False
        path.write_text(json.dumps(cfg), encoding='utf-8', newline='\n')
        with self.assertRaisesRegex(ValueError, 'policy'):
            validate(target)

    def test_filelist_cannot_escape_project(self):
        target = self.copy()
        (target/'config/cpu_cache_sources.f').write_text('../other.v\n', encoding='utf-8', newline='\n')
        with self.assertRaisesRegex(ValueError, 'path'):
            validate(target)


if __name__ == '__main__':
    unittest.main()

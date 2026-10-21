"""Pinned DDR review rejects an altered dependency or a different epoch contract."""
from pathlib import Path
import tempfile
import unittest
from run_cache import sha
from review_ddr import verify_binding


class DdrReviewTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix='cpu-ddr-review-')
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name)/'bridge.v'
        path.write_bytes(b'pinned bytes')
        spec = dict(revision='a'*40, files={'bridge.v':sha(path)})
        row = dict(pinned_unchanged=True, binding=dict(revision='a'*40,
            files={'bridge.v':dict(path=str(path), sha256=sha(path))}))
        return path, spec, row

    def test_actual_dependency_bytes_are_checked(self):
        path, spec, row = self.fixture()
        verify_binding(row, spec)

    def test_pinned_file_change_is_rejected(self):
        path, spec, row = self.fixture()
        path.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'pinned'):
            verify_binding(row, spec)

    def test_different_revision_is_rejected(self):
        path, spec, row = self.fixture()
        row['binding']['revision'] = 'b'*40
        with self.assertRaisesRegex(ValueError, 'revision'):
            verify_binding(row, spec)

    def test_omitting_a_bound_dependency_is_rejected(self):
        path, spec, row = self.fixture()
        row['binding']['files'] = {}
        with self.assertRaisesRegex(ValueError, 'dependency'):
            verify_binding(row, spec)


if __name__ == '__main__':
    unittest.main()

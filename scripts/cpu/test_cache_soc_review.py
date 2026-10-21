"""Evidence review must catch output drift, source drift and failed native tools."""
import json
from pathlib import Path
import tempfile
import unittest

from run_cache import sha
from review_cache_soc import verify_run


class ReviewTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix='cache-soc-review-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        work = root/'run'
        (work/'src').mkdir(parents=True)
        (root/'design.v').write_text('original', encoding='utf-8')
        (work/'src/design.v').write_bytes((root/'design.v').read_bytes())
        (work/'simulation.log').write_text('real result', encoding='utf-8')
        row = dict(status='PASS', source_unchanged=True, external_unchanged=True,
                   runner_return_code=0, commands=[dict(return_code=0, timed_out=False)],
                   input_hashes={'design.v':sha(root/'design.v')}, external_hashes={},
                   output_hashes={'simulation.log':sha(work/'simulation.log')})
        (work/'result.json').write_text(json.dumps(row), encoding='utf-8')
        return root, work, row

    def test_bound_result_is_readable(self):
        root, work, row = self.fixture()
        self.assertEqual(verify_run(work, root)['status'], 'PASS')

    def test_output_change_is_rejected(self):
        root, work, row = self.fixture()
        (work/'simulation.log').write_text('changed', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'output'):
            verify_run(work, root)

    def test_frozen_copy_change_is_rejected(self):
        root, work, row = self.fixture()
        (work/'src/design.v').write_text('changed', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'frozen'):
            verify_run(work, root)

    def test_failed_native_command_is_rejected(self):
        root, work, row = self.fixture()
        row['commands'][0]['return_code'] = 1
        (work/'result.json').write_text(json.dumps(row), encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'command'):
            verify_run(work, root)


if __name__ == '__main__':
    unittest.main()

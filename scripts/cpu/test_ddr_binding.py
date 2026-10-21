"""DDR dependencies must come from immutable reviewed Git objects."""
import json
from pathlib import Path
import tempfile
import unittest
from prepare_ddr import materialize

ROOT = Path(__file__).resolve().parents[2]


class BindingTests(unittest.TestCase):
    def work(self):
        temporary = tempfile.TemporaryDirectory(prefix='cpu-ddr-binding-', dir=ROOT/'build/cpu')
        self.addCleanup(temporary.cleanup)
        return Path(temporary.name)

    def spec(self, work, change):
        spec = json.loads((ROOT/'config/cpu_ddr.json').read_text(encoding='utf-8'))
        change(spec)
        path = work/'changed.json'
        path.write_text(json.dumps(spec), encoding='utf-8')
        return path

    def test_pinned_bridge_and_fifo_materialize_exactly(self):
        work = self.work()
        result = materialize(work)
        self.assertEqual(len(result['files']), 4)
        self.assertEqual(result['revision'], '8635a91626d87eb7573beba5ea805a5f6043bb8a')
        self.assertIn('collect_phase_poisoned', (work/'pinned/rtl/video/axi128_hmic256.sv').read_text(encoding='utf-8'))

    def test_wrong_git_content_hash_is_rejected(self):
        work = self.work()
        config = self.spec(work, lambda s:s['files'].update({'rtl/video/axi128_hmic256.sv':'0'*64}))
        with self.assertRaisesRegex(ValueError, 'hash'):
            materialize(work, config)

    def test_existing_frozen_file_cannot_be_silently_replaced(self):
        work = self.work()
        materialize(work)
        (work/'pinned/rtl/video/axi128_hmic256.sv').write_text('changed', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'frozen'):
            materialize(work)

    def test_independent_reset_is_rejected(self):
        work = self.work()
        config = self.spec(work, lambda s:s.update(reset='independent_domains'))
        with self.assertRaisesRegex(ValueError, 'reset'):
            materialize(work, config)


if __name__ == '__main__':
    unittest.main()

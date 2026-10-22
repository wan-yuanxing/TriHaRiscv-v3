"""Archived release programming may advance the workspace, never its snapshot."""
from pathlib import Path
import tempfile
import unittest

from review_ddr_board import verify_sources
from run_cache import sha


class ArchiveSources(unittest.TestCase):
    def test_snapshot_is_always_required_and_current_gate_is_explicit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'current'
            route = Path(temporary) / 'route'
            root.mkdir(); (route / 'src').mkdir(parents=True)
            (root / 'source.v').write_text('frozen')
            (route / 'src/source.v').write_text('frozen')
            entries = {'source.v': sha(root / 'source.v')}
            (root / 'source.v').write_text('new workspace version')
            with self.assertRaises(ValueError):
                verify_sources(route, entries, root, require_current=True)
            verify_sources(route, entries, root, require_current=False)
            (route / 'src/source.v').write_text('damaged snapshot')
            with self.assertRaises(ValueError):
                verify_sources(route, entries, root, require_current=False)


if __name__ == '__main__':
    unittest.main()

"""Ensure volatile CPU programming uses a complete, unchanged CPU package."""
import json
from pathlib import Path
import tempfile
import unittest

import program_board
from run import sha


class ProgramPackage(unittest.TestCase):
    def test_rejects_modified_mask_or_unapproved_target(self):
        self.assertTrue(hasattr(program_board, 'validate_package'), 'package validation is missing')
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            for name in ('triha_cpu_board_top.sbit', 'triha_cpu_board_top.smsk', 'review.json', 'result.json'):
                (work / name).write_bytes(b'package-fixture')
            manifest = dict(status='PASS', target='cpu_coremark', timing_closed=True,
                            bitstream_sha256=sha(work / 'triha_cpu_board_top.sbit'),
                            verify_mask_sha256=sha(work / 'triha_cpu_board_top.smsk'),
                            files={p.name: sha(p) for p in work.iterdir()})
            (work / 'manifest.json').write_text(json.dumps(manifest))
            self.assertEqual(program_board.validate_package(work), manifest)
            (work / 'triha_cpu_board_top.smsk').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                program_board.validate_package(work)
            manifest['target'] = 'other'
            (work / 'manifest.json').write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                program_board.validate_package(work)


if __name__ == '__main__':
    unittest.main()

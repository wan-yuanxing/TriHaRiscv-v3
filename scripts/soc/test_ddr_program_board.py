"""The DDR target must retain the same volatile-program package checks."""
import json
from pathlib import Path
import tempfile
import unittest

import program_board
from run import sha


class DdrProgramPackage(unittest.TestCase):
    def test_ddr_package_and_matching_mask(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ('triha_cpu_ddr_board_top.sbit', 'triha_cpu_ddr_board_top.smsk',
                         'review.json', 'route-result.json'):
                (directory / name).write_bytes(b'ddr-package-fixture')
            manifest = dict(status='PASS', target='cpu_ddr_board', timing_closed=True,
                bitstream_sha256=sha(directory / 'triha_cpu_ddr_board_top.sbit'),
                verify_mask_sha256=sha(directory / 'triha_cpu_ddr_board_top.smsk'),
                files={p.name: sha(p) for p in directory.iterdir()})
            (directory / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
            self.assertEqual(program_board.validate_package(directory), manifest)
            (directory / 'triha_cpu_ddr_board_top.smsk').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                program_board.validate_package(directory)


if __name__ == '__main__':
    unittest.main()

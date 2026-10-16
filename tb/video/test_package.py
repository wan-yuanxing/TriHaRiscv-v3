import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/video'))
import package_board


class PackageTests(unittest.TestCase):
    def make_build(self, root):
        build=root/'build'
        work=build/'pds'
        work.mkdir(parents=True)
        bitstream=work/'video_board_smoke_top.sbit'
        bitstream.write_bytes(b'bitstream')
        mask=bitstream.with_suffix('.smsk')
        mask.write_bytes(b'verify mask')
        timing=work/'timing.rtr'
        timing.write_text('All Constraints Met')
        (work/'message_review.json').write_text('{}')
        result={'status':'pass','target':'video_board_smoke','stage':'bitstream',
                'internal_timing_met':True,'directory':str(work.relative_to(root)),
                'artifact':str(bitstream.relative_to(root)),
                'artifact_sha256':package_board.sha256(bitstream),
                'verify_mask':str(mask.relative_to(root)),
                'verify_mask_sha256':package_board.sha256(mask),
                'timing_report':str(timing.relative_to(root)), 'inputs':{}}
        (build/'latest_pds_video_board_smoke.json').write_text(json.dumps(result))
        return build,mask

    def test_package_includes_matching_verification_mask(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            build,mask=self.make_build(root)
            with patch.object(package_board,'BUILD',build),patch.object(package_board,'ROOT',root):
                self.assertEqual(package_board.main(),0)
            result=json.loads((build/'latest_package.json').read_text())
            copied=root/result['directory']/mask.name
            self.assertTrue(copied.is_file(),'PDS Verify needs sibling .smsk in release package')
            self.assertEqual(copied.read_bytes(),mask.read_bytes())
            self.assertEqual(result['verify_mask_sha256'],package_board.sha256(mask))

    def test_missing_or_changed_verification_mask_prevents_package_success(self):
        for missing in (False,True):
            with self.subTest(missing=missing),tempfile.TemporaryDirectory() as directory:
                root=Path(directory)
                build,mask=self.make_build(root)
                if missing: mask.unlink()
                else: mask.write_bytes(b'corrupted mask')
                with patch.object(package_board,'BUILD',build),patch.object(package_board,'ROOT',root),contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(package_board.main(),1)
                self.assertEqual(json.loads((build/'latest_package.json').read_text())['status'],'fail')
                self.assertFalse((build/'releases').exists())

    def test_failed_package_invalidates_previous_success(self):
        with tempfile.TemporaryDirectory() as directory:
            build=Path(directory)
            (build/'latest_package.json').write_text('{"status":"pass","directory":"old"}')
            (build/'latest_package_video_board_smoke.json').write_text('{"status":"pass","directory":"old"}')
            # A failed PDS result must invalidate, not preserve, the prior package.
            (build/'latest_pds.json').write_text('{"status":"fail"}')
            with patch.object(package_board,'BUILD',build), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(package_board.main(),1)
            result=json.loads((build/'latest_package.json').read_text())
            self.assertEqual(result['status'],'fail')
            self.assertNotIn('directory',result)
            self.assertEqual(json.loads((build/'latest_package_video_board_smoke.json').read_text())['status'],'fail')


if __name__=='__main__': unittest.main()

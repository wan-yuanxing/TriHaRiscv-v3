import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/video'))
from gen_ddr import verify_dependencies, verify_generated_sources
from common import sha256


class DdrGenerationTests(unittest.TestCase):
    def test_missing_or_changed_protected_dependency_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            item={'path':'rtl/model.vp','sha256':'0'*64}
            with self.assertRaises((FileNotFoundError,ValueError)):
                verify_dependencies(root,[item])
            p=root/item['path'];p.parent.mkdir();p.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError,'hash'):
                verify_dependencies(root,[item])

    def test_manifest_has_complete_unique_hardware_dependencies(self):
        root=Path(__file__).resolve().parents[2]
        m=json.loads((root/'fpga/pg2l100h/ip/video_ddr_manifest.json').read_text(encoding='utf-8'))
        self.assertEqual(len(m['dependencies']),71)
        self.assertEqual(len({i['path'] for i in m['dependencies']}),71)
        self.assertEqual(len(m['generated_sources']),3)

    def test_generator_cannot_change_dependencies_or_duplicate_filelist(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            dependency=root/'rtl/model.vp';dependency.parent.mkdir();dependency.write_bytes(b'protected')
            wrapper=root/'wrapper.v';wrapper.write_bytes(b'wrapper')
            manifest={'dependencies':[{'path':'rtl/model.vp','sha256':sha256(dependency)}],
                      'generated_sources':['wrapper.v']}
            self.assertEqual(set(verify_generated_sources(root,manifest,['rtl/model.vp','wrapper.v'])),
                             {'rtl/model.vp','wrapper.v'})
            with self.assertRaisesRegex(ValueError,'filelist'):
                verify_generated_sources(root,manifest,['rtl/model.vp','rtl/model.vp'])
            dependency.write_bytes(b'overwritten by generator')
            with self.assertRaisesRegex(ValueError,'hash'):
                verify_generated_sources(root,manifest,['rtl/model.vp','wrapper.v'])


if __name__=='__main__':unittest.main()

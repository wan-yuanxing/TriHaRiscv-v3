import copy,hashlib,importlib.util,json,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('capture_v2_gen',ROOT/'scripts/video/gen_capture_v2.py')
gen=importlib.util.module_from_spec(spec);spec.loader.exec_module(gen)
class CaptureV2ABI(unittest.TestCase):
    def setUp(self):
        self.raw=(ROOT/'config/video_capture_v2.json').read_bytes();self.cfg=json.loads(self.raw)
    def test_generated_exact_bytes(self):
        for p,text in gen.generated_files(self.cfg,hashlib.sha256(self.raw).hexdigest()).items():
            self.assertEqual((ROOT/p).read_bytes(),text.encode())
        self.assertNotIn(b'\r',self.raw)
    def test_drift_rejected(self):
        for key in ('abi_version','base','region_bytes'):
            cfg=copy.deepcopy(self.cfg);cfg[key]+=1
            with self.assertRaises(ValueError):gen.validate(cfg)
        for cfg in ({},None,[],{'schema_version':True}):
            with self.assertRaises(ValueError):gen.validate(cfg)
        cfg=copy.deepcopy(self.cfg);cfg['registers'][0]['offset']=4
        with self.assertRaises(ValueError):gen.validate(cfg)
    def test_duplicate_json_and_bad_digest(self):
        with self.assertRaises(ValueError):json.loads('{"x":1,"x":2}',object_pairs_hook=gen.unique_object)
        with self.assertRaises(ValueError):gen.generated_files(self.cfg,'z'*64)
    def test_missing_output_fails_check(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(gen.main(['--root',tmp,'--check']),1)
            self.assertEqual(gen.main(['--root',tmp]),0)
            self.assertEqual(gen.main(['--root',tmp,'--check']),0)
if __name__=='__main__':unittest.main()

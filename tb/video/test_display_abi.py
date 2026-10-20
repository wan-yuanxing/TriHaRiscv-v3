import copy,hashlib,json,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'scripts/video'))
import gen_display_abi as gen
class DisplayABI(unittest.TestCase):
    def setUp(self):self.raw=(ROOT/'config/video_display.json').read_bytes();self.cfg=json.loads(self.raw)
    def test_published_literals(self):
        self.assertEqual(self.raw.count(b'\r'),0,
            'display JSON must use LF so the raw digest survives Git checkout')
        gen.validate(self.cfg);out=gen.generated_files(self.cfg,hashlib.sha256(self.raw).hexdigest())
        self.assertEqual(set(out),{'rtl/video/include/video_display.vh','sw/include/video_display_abi.h'})
        for key,value in {'BASE':0x20011000,'REG_ACK':0x18,'REG_SUBMIT':0x20,'SHADOW_OFFSET':0x100,
                          'RECORD_WORDS':160,'RECORD_BYTES':640,'HEADER_WORDS':32,'BOX_WORDS':8,'BOX_COUNT':16,
                          'FIELD_RAW_BASE':5,'FIELD_FLAGS':9,'FIELD_AVATAR_XY1':22}.items():
            self.assertIn(f'#define VDISP_{key} 0x{value:08x}u\n',out['sw/include/video_display_abi.h'])
            self.assertIn(f"`define VDISP_{key} 32'h{value:08x}\n",out['rtl/video/include/video_display.vh'])
    def test_reject_profile_drift_and_types(self):
        for key in self.cfg:
            for value in (True,None,{},-1):
                c=copy.deepcopy(self.cfg);c[key]=value
                with self.subTest(key=key,value=value),self.assertRaises(ValueError):gen.validate(c)
        for table in ('registers','fields','flags'):
            for key in self.cfg[table]:
                c=copy.deepcopy(self.cfg);c[table][key]+=4
                with self.subTest(table=table,key=key),self.assertRaises(ValueError):gen.validate(c)
        c=copy.deepcopy(self.cfg);c['extra']=1
        with self.assertRaises(ValueError):gen.validate(c)
    def test_duplicate_keys_rejected(self):
        with self.assertRaises(ValueError):json.loads('{"base":1,"base":2}',object_pairs_hook=gen.unique_object)
    def test_determinism_and_stale(self):
        digest=hashlib.sha256(self.raw).hexdigest()
        self.assertEqual(gen.generated_files(self.cfg,digest),gen.generated_files(json.loads(json.dumps(self.cfg,sort_keys=True)),digest))
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp);cfg=path/'cfg.json';cfg.write_bytes(self.raw)
            self.assertEqual(gen.main(['--root',tmp,'--config',str(cfg)]),0)
            self.assertEqual(gen.main(['--root',tmp,'--config',str(cfg),'--check']),0)
            (path/'sw/include/video_display_abi.h').write_text('stale')
            self.assertEqual(gen.main(['--root',tmp,'--config',str(cfg),'--check']),1)
if __name__=='__main__':unittest.main()

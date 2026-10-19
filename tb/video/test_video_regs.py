"""ABI generation and invalid input guards; expectations follow the published spec."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/video'))
import gen_regs


class VideoRegisters(unittest.TestCase):
    def setUp(self):
        self.source=(ROOT/'config/video_regs.json').read_bytes()
        self.config=json.loads(self.source)

    def reject(self,config):
        with self.assertRaises(ValueError):gen_regs.validate(config)

    def test_valid_profile_and_generated_contract(self):
        gen_regs.validate(self.config)
        generated=gen_regs.generated_files(self.config,hashlib.sha256(self.source).hexdigest())
        self.assertEqual(set(generated),{'rtl/video/include/video_regs.vh','sw/include/video_regs.h'})
        c=generated['sw/include/video_regs.h']; rtl=generated['rtl/video/include/video_regs.vh']
        for name,value in {'VIDEO_MMIO_BASE':0x20010000,'VIDEO_MMIO_BYTES':65536,
                           'VIDEO_ABI_VERSION':65536,'VIDEO_CAPABILITIES':7,
                           'VIDEO_REG_CAPTURE_REQUEST':0x20,'VIDEO_REG_CAPTURE_STATUS':0x24,
                           'VIDEO_REG_REQUEST_SLOT':0x100,'VIDEO_REG_COMPLETED_FIFO_PEAK':0x1bc,
                           'VIDEO_COMPLETED_RESULT_ERROR_CODE_MASK':0xff00}.items():
            self.assertIn(f'#define {name} 0x{value:08x}u\n',c)
            self.assertIn(f'`define {name} 32\'h{value:08x}\n',rtl)
        self.assertNotIn('VIDEO_REG_DISPLAY_SUBMIT',c)
        self.assertEqual(len(self.config['registers']),46)

    def test_deterministic_generation(self):
        digest=hashlib.sha256(self.source).hexdigest()
        a=gen_regs.generated_files(self.config,digest)
        reordered=json.loads(json.dumps(self.config,sort_keys=True))
        reordered['registers'].reverse()
        for reg in reordered['registers']:reg['fields'].reverse()
        self.assertEqual(a,gen_regs.generated_files(reordered,digest))
        self.assertIn(digest,a['sw/include/video_regs.h'])

    def test_reject_wrong_fixed_header(self):
        for key,values in {'base':[0x20000000,0x20010001,True,-1,2**32],
                           'region_bytes':[0,4096,True], 'schema_version':[0,True,2],
                           'abi_version':[0,True,0x20000,'65536']}.items():
            for value in values:
                with self.subTest(key=key,value=value):
                    c=copy.deepcopy(self.config);c[key]=value;self.reject(c)

    def test_reject_missing_or_extra_top_keys(self):
        c=copy.deepcopy(self.config);c['extra']=0;self.reject(c)
        for name in self.config:
            c=copy.deepcopy(self.config);del c[name];self.reject(c)

    def test_reject_invalid_register_table(self):
        for value in [None,{},[],True]:
            c=copy.deepcopy(self.config);c['registers']=value;self.reject(c)
        for key,value in [('name','bad-name'),('name',42),('offset',3),('offset',-4),
                          ('offset',0x10000),('offset',True),('offset',0x30),
                          ('access','readwrite'),('access',None)]:
            c=copy.deepcopy(self.config);c['registers'][0][key]=value;self.reject(c)
        c=copy.deepcopy(self.config);c['registers'][1]['offset']=0;self.reject(c)
        c=copy.deepcopy(self.config);c['registers'][1]['name']='VERSION';self.reject(c)
        c=copy.deepcopy(self.config);c['registers'][2]['access']='RO';self.reject(c)
        c=copy.deepcopy(self.config);c['registers'][0]['extra']=1;self.reject(c)

    def test_reject_invalid_capabilities(self):
        for value in [{},{'CAPTURE':0}, {'CAPTURE':0,'HELD_EVENTS':0,'IRQ':2},
                      {'CAPTURE':True,'HELD_EVENTS':1,'IRQ':2},
                      {'CAPTURE':0,'HELD_EVENTS':1,'IRQ':32}]:
            c=copy.deepcopy(self.config);c['capabilities']=value;self.reject(c)

    def test_reject_invalid_fields(self):
        for key,value in [('lsb',-1),('lsb',32),('lsb',True),('width',0),
                          ('width',33),('width',True),('name','bad-field')]:
            c=copy.deepcopy(self.config);c['registers'][2]['fields'][0][key]=value;self.reject(c)
        c=copy.deepcopy(self.config);c['registers'][2]['fields'].append({'name':'OVERLAP','lsb':0,'width':1});self.reject(c)
        c=copy.deepcopy(self.config);c['registers'][2]['fields'].append({'name':'ENABLE','lsb':1,'width':1});self.reject(c)
        c=copy.deepcopy(self.config);c['registers'][2]['fields'][0]['extra']=1;self.reject(c)
        c=copy.deepcopy(self.config);c['registers'][2]['fields']=None;self.reject(c)

    def test_reject_invalid_resets(self):
        for value in [-1,2**32,True,2]:
            c=copy.deepcopy(self.config);c['registers'][2]['reset']=value;self.reject(c)
        c=copy.deepcopy(self.config);del c['registers'][2]['reset'];self.reject(c)
        c=copy.deepcopy(self.config);c['registers'][0]['reset']=0;self.reject(c)

    def test_same_version_semantic_changes_are_rejected(self):
        c=copy.deepcopy(self.config)
        c['registers'][0]['offset'],c['registers'][1]['offset']=c['registers'][1]['offset'],c['registers'][0]['offset']
        self.reject(c)
        c=copy.deepcopy(self.config);c['registers'][2]['fields'][0]['lsb']=1;self.reject(c)
        c=copy.deepcopy(self.config);c['registers'][13]['reset']=2;self.reject(c)
        c=copy.deepcopy(self.config);c['registers'][12]['reset']=1;self.reject(c)

    def test_generate_check_and_stale_refusal(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); config=root/'registers.json';config.write_bytes(self.source)
            args=['--root',str(root),'--config',str(config)]
            with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(gen_regs.main(args),0)
                self.assertEqual(gen_regs.main(args+['--check']),0)
                target=root/'sw/include/video_regs.h';target.write_bytes(target.read_bytes()+b'\n')
                self.assertEqual(gen_regs.main(args+['--check']),1)
                target.unlink();self.assertEqual(gen_regs.main(args+['--check']),1)

    def test_cli_bad_json_and_profile_fail_without_writes(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);config=root/'bad.json'
            for raw in [b'{',b'[]',b'true',b'{"schema_version":1}']:
                config.write_bytes(raw)
                with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(gen_regs.main(['--root',str(root),'--config',str(config)]),1)
                self.assertFalse((root/'rtl').exists());self.assertFalse((root/'sw').exists())

    def test_cli_duplicate_json_keys_rejected_recursively(self):
        mutations=[(b'"base": 536936448',b'"base": 1, "base": 536936448'),
                   (b'"offset": 0,',b'"offset": 3, "offset": 0,'),
                   (b'"lsb": 0,',b'"lsb": 32, "lsb": 0,')]
        for before,after in mutations:
            with self.subTest(key=before),tempfile.TemporaryDirectory() as temp:
                root=Path(temp);config=root/'duplicate.json'
                self.assertIn(before,self.source)
                config.write_bytes(self.source.replace(before,after,1))
                args=['--root',str(root),'--config',str(config)]
                for mode in [[],['--check']]:
                    errors=io.StringIO()
                    with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(errors):
                        self.assertEqual(gen_regs.main(args+mode),1)
                    self.assertIn('duplicate JSON key',errors.getvalue())
                self.assertFalse((root/'rtl').exists());self.assertFalse((root/'sw').exists())


if __name__=='__main__':unittest.main()

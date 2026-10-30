"""Contract tests for the frozen bbox package and TriHa host preparation."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = ROOT.parent / 'npu_zgtc'
spec = importlib.util.spec_from_file_location('prepare_integration', Path(__file__).with_name('prepare_integration.py'))
if Path(spec.origin).is_file():
    prep = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(prep)
else:
    prep = None


class ToolExists(unittest.TestCase):
    def test_tool_is_implemented(self):
        self.assertIsNotNone(prep, 'host preparation tool is not implemented yet')


@unittest.skipIf(prep is None, 'tool not implemented')
class IntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((UPSTREAM/'yunet/baseline/program_package_manifest_v0_1.json').read_text(encoding='utf-8'))
        cls.blob = (UPSTREAM/'build/integration_audit/20261020/program.bin').read_bytes()
        cls.program = prep.decode_program(cls.blob, cls.manifest)
        cls.video = json.loads((ROOT/'config/video_cfg.json').read_text(encoding='utf-8'))
        cls.fixture = json.loads((ROOT/'config/npu_integration_fixture.json').read_text(encoding='utf-8'))

    def bind(self, fixture=None, video=None, program=None):
        return prep.bind_program(program or self.program, self.manifest,
                                 video or self.video, fixture or self.fixture)

    def test_frozen_counts(self):
        self.assertEqual([len(self.program[k]) for k in ('tensors','params','ops')], [80,150,79])

    def test_independent_parameter_free_pool_program(self):
        # Literal wire layout from format-1, independent of the producer's field lists.
        header=struct.pack('<32I',0x5055504E,1,128,384,384,2,0,1,128,64,256,32,256,128,
                           512,1,1,8,127,1,1,0,4,16,*([0]*8))
        first=struct.pack('<16I',0,1,4,1,0,4,256,4,1,1,2,2,0,255,0xFFFFFFFF,0)
        last=struct.pack('<16I',1,1,4,2,256,1,256,1,1,1,1,1,0,255,0,0)
        op=struct.pack('<32I',0,4,0,1,0,0xFFFFFFFF,1,*([0xFFFFFFFF]*4),
                       2,2,2,2,0,0,0,0,1,1,*([0]*11))
        blob=header+first+last+op
        m={'program_sha256':hashlib.sha256(blob).hexdigest(),
           'tensor_names':['input','pooled'],'parameter_names':[],'operator_names':['pool'],
           'parameter_image_model_offset':512,'parameter_image_bytes':0,
           'header':{'magic':0x5055504E,'format_id':1,'header_bytes':128,'logical_bytes':384,
                     'allocated_bytes':384,'tensor_count':2,'param_count':0,'op_count':1,
                     'tensor_offset':128,'tensor_stride':64,'param_offset':256,'param_stride':32,
                     'op_offset':256,'op_stride':128,'workspace_bytes':512,'model_package_version':1,
                     'numerics_id':1,'required_ops':8,'required_numeric_caps':127,'input_count':1,
                     'output_count':1,'flags':0,'max_rank':4,'weight_block':16}}
        decoded=prep.decode_program(blob,m)
        self.assertEqual(decoded['params'],[])
        self.assertEqual(decoded['tensors'][1]['logical_bytes'],1)
        self.assertEqual(decoded['ops'][0]['opcode'],4)

    def test_three_direct_inputs(self):
        p = self.bind()
        self.assertEqual([s['tensor_addresses'][0] for s in p['slots']], [0x82800000,0x82850000,0x828A0000])
        self.assertEqual(p['input_copy_bytes'], 0)

    def test_heads_are_slot_local_and_compact(self):
        p = self.bind()
        self.assertEqual(p['head_logical_bytes'], 25200)
        self.assertEqual(p['head_allocated_bytes'], 26368)
        for slot in p['slots']:
            self.assertEqual(slot['heads'][0]['address'], slot['output_base'])
            self.assertEqual(len(slot['heads']), 9)
            self.assertTrue(all(h['address'] % 256 == 0 for h in slot['heads']))
            self.assertLessEqual(slot['heads'][-1]['address']+slot['heads'][-1]['allocated_bytes'], slot['output_base']+131072)

    def test_parameter_region_is_model_not_workspace(self):
        p = self.bind()
        for raw, relocated in zip(self.program['params'], p['parameters']):
            self.assertEqual(relocated['address'],0x82B00000+raw['model_offset']-4768256)
            self.assertLess(relocated['address'],0x83300000)

    def test_internal_tensor_offsets_preserved(self):
        p = self.bind()
        for t in self.program['tensors']:
            if t['role']==0:
                for slot in p['slots']:
                    self.assertEqual(slot['tensor_addresses'][t['id']],0x83300000+t['model_offset'])

    def test_hardware_and_final_scope_remain_open(self):
        p = self.bind()
        self.assertFalse(p['hardware_ready'])
        self.assertFalse(p['final_model_compatible'])
        self.assertTrue(p['final_landmarks_required'])

    def test_resource_arithmetic_does_not_sign_off(self):
        r=prep.resource_scenarios(73.5,64,100.5,self.fixture['resource_budget'])
        self.assertEqual([x['drm'] for x in r],[174,128,144])
        self.assertEqual([x['margin_drm'] for x in r],[-19,27,11])
        self.assertTrue(all(x['hardware_ready'] is False for x in r))

    def test_overbudget_raw_is_reported(self):
        cfg={**self.fixture['resource_budget'],'fabric_extra_drm':40}
        self.assertFalse(prep.resource_scenarios(73.5,64,100.5,cfg)[1]['arithmetic_fits'])

    def test_corrupt_program_hash_rejected(self):
        bad=bytearray(self.blob); bad[-1]^=1
        with self.assertRaisesRegex(ValueError,'SHA256'):
            prep.decode_program(bytes(bad),self.manifest)

    def reject_wire(self,offset,value,pattern):
        bad=bytearray(self.blob); struct.pack_into('<I',bad,offset,value)
        m=copy.deepcopy(self.manifest); m['program_sha256']=hashlib.sha256(bad).hexdigest()
        with self.assertRaisesRegex(ValueError,pattern): prep.decode_program(bytes(bad),m)

    def test_reserved_header_rejected(self):
        self.reject_wire(96,1,'reserved')

    def test_noncontiguous_tensor_id_rejected(self):
        self.reject_wire(128,1,'tensor')

    def test_read_before_producer_rejected(self):
        self.reject_wire(self.manifest['header']['op_offset']+16,79,'producer')

    def test_wrong_parameter_owner_rejected(self):
        self.reject_wire(self.manifest['header']['param_offset']+24,78,'owner')

    def test_duplicate_operator_output_rejected(self):
        self.reject_wire(self.manifest['header']['op_offset']+24,0,'output')

    def test_short_binary_rejected(self):
        bad=self.blob[:-1]; m={**self.manifest,'program_sha256':hashlib.sha256(bad).hexdigest()}
        with self.assertRaisesRegex(ValueError,'length'): prep.decode_program(bad,m)

    def test_regions_must_cover_spec_without_alias(self):
        f=copy.deepcopy(self.fixture); f['shared_regions'][4]['base']='0x82600000'
        with self.assertRaisesRegex(ValueError,'region'): self.bind(fixture=f)

    def test_small_ddr_window_rejected(self):
        f=copy.deepcopy(self.fixture); f['ddr_bytes']=67108864
        with self.assertRaisesRegex(ValueError,'DDR'): self.bind(fixture=f)

    def test_output_slot_alias_rejected(self):
        f=copy.deepcopy(self.fixture); f['output_bases'][1]=f['output_bases'][0]
        with self.assertRaisesRegex(ValueError,'overlap'): self.bind(fixture=f)

    def test_output_slot_capacity_rejected(self):
        f=copy.deepcopy(self.fixture); f['output_slot_bytes']=16384
        with self.assertRaisesRegex(ValueError,'capacity'): self.bind(fixture=f)

    def test_video_input_alias_rejected(self):
        v=copy.deepcopy(self.video); v['input_slots']['bases'][1]=v['input_slots']['bases'][0]
        with self.assertRaisesRegex(ValueError,'input'): self.bind(video=v)

    def test_wrong_pixel_format_rejected(self):
        v=copy.deepcopy(self.video); v['detector']['layout']='NHWC'
        with self.assertRaisesRegex(ValueError,'input format'): self.bind(video=v)

    def test_weights_table_collision_rejected(self):
        f=copy.deepcopy(self.fixture); f['table_base']=f['weights_base']
        with self.assertRaisesRegex(ValueError,'overlap'): self.bind(fixture=f)

    def test_address_wrap_rejected(self):
        f=copy.deepcopy(self.fixture); f['workspace_base']='0xFFFFFFE0'
        with self.assertRaisesRegex(ValueError,'workspace'): self.bind(fixture=f)

    def test_boolean_address_rejected(self):
        f=copy.deepcopy(self.fixture); f['weights_base']=True
        with self.assertRaisesRegex(ValueError,'integer'): self.bind(fixture=f)

    def test_cannot_switch_to_graph_hardware(self):
        f=copy.deepcopy(self.fixture); f['control']='hardware_graph'
        with self.assertRaisesRegex(ValueError,'control'): self.bind(fixture=f)

    def test_cannot_remove_final_landmark_requirement(self):
        f=copy.deepcopy(self.fixture); f['final_landmarks_required']=False
        with self.assertRaisesRegex(ValueError,'landmark'): self.bind(fixture=f)

    def test_cpu_table_has_exact_original_operator_words(self):
        p=self.bind()
        blob,parts=prep.table_binary(self.program,p)
        self.assertEqual(len(blob)%32,0)
        self.assertEqual(blob[:4],b'TNCT')
        offset=parts['operators']['offset']
        raw_offset=self.manifest['header']['op_offset']
        self.assertEqual(blob[offset:offset+79*128],self.blob[raw_offset:raw_offset+79*128])
        addresses=struct.unpack_from('<240I',blob,parts['tensor_addresses']['offset'])
        self.assertEqual([addresses[i*80] for i in range(3)], [0x82800000,0x82850000,0x828A0000])
        c=prep.render_c(blob,p,parts)
        import re
        array=c.split('triha_npu_cpu_table[',1)[1].split('= {',1)[1]
        rendered=[int(s,16) for s in re.findall(r'UINT32_C\(0x([0-9A-F]{8})\)',array)]
        self.assertEqual(struct.pack('<'+str(len(rendered))+'I',*rendered),blob)

    def test_table_capacity_is_enforced(self):
        p=self.bind(); p['table_reserved_bytes']=1024
        with self.assertRaisesRegex(ValueError,'table capacity'): prep.table_binary(self.program,p)

    def test_default_c_table_uses_ddr_not_small_boot_rom(self):
        p=self.bind(); blob,parts=prep.table_binary(self.program,p)
        c=prep.render_c(blob,p,parts)
        self.assertTrue('#ifdef TRIHA_NPU_EMBED_HOST_TABLE' in c)
        self.assertTrue('((const uint32_t *)(uintptr_t)TRIHA_NPU_TABLE_BASE)' in c)

    def test_corrupt_parameters_leave_fail_not_pass(self):
        with tempfile.TemporaryDirectory() as temp:
            image=Path(temp)/'parameters.bin'
            image.write_bytes(b'bad image')
            out=Path(temp)/'trial'
            cmd=[sys.executable,str(Path(prep.__file__)),'--npu-root',str(UPSTREAM),
                 '--program',str(UPSTREAM/'build/integration_audit/20261020/program.bin'),
                 '--parameters',str(image),'--output-dir',str(out)]
            run=subprocess.run(cmd,capture_output=True,text=True)
            self.assertEqual(run.returncode,1)
            result=json.loads((out/'result.json').read_text(encoding='utf-8'))
            self.assertEqual(result['preparation_status'],'FAIL')
            self.assertFalse(result['hardware_ready'])
            self.assertFalse((out/'npu_cpu_table.bin').exists())

    def test_cli_refuses_hardware_gate_and_existing_output(self):
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp)/'trial'
            cmd=[sys.executable,str(Path(prep.__file__)),'--npu-root',str(UPSTREAM),
                 '--program',str(UPSTREAM/'build/integration_audit/20261020/program.bin'),
                 '--parameters',str(UPSTREAM/'build/integration_audit/20261020/parameter_image.bin'),
                 '--output-dir',str(out),'--require-hardware-ready']
            first=subprocess.run(cmd,capture_output=True,text=True)
            self.assertEqual(first.returncode,2,first.stdout+first.stderr)
            result=json.loads((out/'result.json').read_text(encoding='utf-8'))
            self.assertEqual(result['preparation_status'],'PASS')
            self.assertFalse(result['hardware_ready'])
            original=(out/'result.json').read_bytes()
            second=subprocess.run(cmd,capture_output=True,text=True)
            self.assertEqual(second.returncode,1)
            self.assertEqual((out/'result.json').read_bytes(),original)


if __name__=='__main__': unittest.main()

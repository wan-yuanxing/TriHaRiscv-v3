"""Independent SoC address/descriptor checks; no RTL or DDR proof."""
import copy
import importlib
import json
from pathlib import Path
import struct
import sys
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))


class FrameConfigTests(unittest.TestCase):
    def setUp(self):
        self.gen = importlib.import_module('gen_config')
        self.task = importlib.import_module('b03_task')
        self.memory = json.loads((ROOT / 'config/soc_memory.json').read_bytes())
        self.regs = json.loads((ROOT / 'config/npu_frame_regs.json').read_bytes())
        self.program = (ROOT / 'build/npu/b03_assets_20261030/assets/program.bin').read_bytes()

    def test_generated_outputs_are_current(self):
        for name, data in self.gen.generate(ROOT).items():
            self.assertEqual((ROOT / name).read_bytes(), data)

    def test_same_frame_slot_rebind_all_three(self):
        for slot in range(3):
            words = struct.unpack('<32I', self.task.build_task(self.memory, self.program,
                slot=slot, cmd_id=9, frame_id=11, epoch=7, addr_version=1))
            self.assertEqual(words[:4], (0x33444d42, 1, 128, 1))
            self.assertEqual(words[8], 0x800000 + slot*0x50000)
            self.assertEqual(words[9], 307200)
            self.assertEqual(words[10], 0x900000 + slot*0x40000 + 0x8000)
            self.assertEqual(words[28], 0x900000 + slot*0x40000)
            self.assertEqual(words[14:19], (9,11,0,7,1))
            self.assertEqual(words[19:26], (800,600,320,240,0,40,2100))
            self.assertEqual(words[26], zlib.crc32(self.program))
            self.assertEqual(words[11], 67328)
            # Controller address is relative to DDR, not already a CPU address.
            self.assertEqual(self.memory['window_base'] + words[8], 0x02800000 + slot*0x50000)

    def test_identity_exhaustion_and_slot_bounds_rejected(self):
        base = dict(slot=0, cmd_id=1, frame_id=1, epoch=1, addr_version=1)
        for key, bad in [('slot',-1),('slot',3),('slot',True),('cmd_id',0),('cmd_id',2**32),
                         ('frame_id',0),('frame_id',0xffffffff),('epoch',0),('epoch',0xffffffff),
                         ('addr_version',0)]:
            with self.subTest(key=key,bad=bad), self.assertRaises(ValueError):
                self.task.build_task(self.memory,self.program,**{**base,key:bad})

    def test_memory_overlap_and_private_input_rejected(self):
        for key, value in [('input_bases',[0x80000000,0x82850000,0x828a0000]),
                           ('output_bases',[0x82800000,0x82940000,0x82980000]),
                           ('post_table_base',0x82b00000),('workspace_base',0xffffffe0)]:
            m=copy.deepcopy(self.memory)
            m['b03'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):
                self.gen.validate_memory(m)

    def test_header_and_program_corruption_rejected(self):
        for offset in (0,128,len(self.program)-1):
            broken=bytearray(self.program);broken[offset]^=1
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                self.task.build_task(self.memory,bytes(broken),slot=0,cmd_id=1,frame_id=1,epoch=1,addr_version=1)

    def test_new_abi_does_not_alias_operator_version(self):
        self.assertEqual(self.regs['base'],0x20000000)
        self.assertEqual(self.regs['id_version'],0x4e460001)
        self.assertNotEqual(self.regs['id_version'],json.loads((ROOT/'config/npu_regs.json').read_bytes())['id_version'])


if __name__ == '__main__':
    unittest.main()

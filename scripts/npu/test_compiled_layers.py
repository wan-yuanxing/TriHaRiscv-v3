"""Exercise the compiled real RTL with a small independent numeric fixture."""
from pathlib import Path
import struct
import subprocess
import unittest
import uuid
import compiled_layers

ROOT = Path(__file__).resolve().parents[2]


class CompiledLayerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = ROOT / 'build/npu' / ('compiled_test_' + uuid.uuid4().hex[:8])
        cls.work.mkdir(parents=True)
        cls.build = compiled_layers.build(cls.work / 'compile', ROOT / 'rtl/npu/npu_scalar_conv.v',
                                         ROOT / 'tb/npu/npu_layer_main.cpp',
                                         compiled_layers.tool_root(ROOT),
                                         Path('D:/Xilinx/Vivado/2018.3/msys64/mingw64/bin/g++.exe'))

    def fixture(self):
        folder = self.work / uuid.uuid4().hex[:8]
        folder.mkdir()
        cfg = [0x82800000,0x82B00000,0x82C00000,0x82D00000,0x83300000,
               1,1,1,1,1,1,1,1,0,0,0,2,1,16,4,8,1]+[0]*10
        (folder/'config.hex').write_text(''.join(f'{v:08x}\n' for v in cfg),encoding='ascii')
        for name,data in [('input',b'\x03'),('weight',b'\xfe'+b'\x00'*15),
                          ('bias',struct.pack('<i',1)),('requant',struct.pack('<ii',1,0)),('expected',b'\xfb')]:
            (folder/(name+'.bin')).write_bytes(data)
        return folder

    def run_fixture(self, folder, limit=10000, corrupt=0):
        result = subprocess.run([str(self.build['binary']),str(folder),str(limit),str(folder/'actual.bin'),str(corrupt)],
                                capture_output=True,text=True,timeout=30)
        (folder/'simulation.log').write_text(result.stdout+result.stderr,encoding='utf-8')
        return result

    def test_full_output(self):
        folder=self.fixture();result=self.run_fixture(folder)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(result.stdout.count('NPU_LAYER_PASS'),1)
        self.assertEqual((folder/'actual.bin').read_bytes(),b'\xfb')

    def test_corrupted_output_is_rejected(self):
        result=self.run_fixture(self.fixture(),corrupt=1)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('output mismatch',result.stderr)

    def test_truncated_parameter_is_rejected(self):
        folder=self.fixture();(folder/'bias.bin').write_bytes(b'\x00')
        result=self.run_fixture(folder)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('file size',result.stderr)

    def test_timeout_is_rejected(self):
        result=self.run_fixture(self.fixture(),limit=1)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('timeout',result.stderr)


if __name__=='__main__':unittest.main()

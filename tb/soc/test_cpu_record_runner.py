"""Tool failures and altered inputs must be rejected even with Python -O."""
from pathlib import Path
import importlib.util,subprocess,sys,tempfile,unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/soc'))
import run_cpu_record as cpu
spec=importlib.util.spec_from_file_location('control_decode_runner',ROOT/'scripts/soc/test_control_decode.py')
decoder=importlib.util.module_from_spec(spec);spec.loader.exec_module(decoder)

class RunnerFailureTests(unittest.TestCase):
    def test_decoder_rejects_nonzero_simulator_without_pass(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build/video') as directory:
            with patch.object(decoder,'fresh_run',return_value=Path(directory)),patch.object(decoder,'run_logged'),patch.object(decoder,'write_json'),patch.object(decoder.subprocess,'run',return_value=subprocess.CompletedProcess([],7,stdout=b'INTENTIONAL_SIMULATOR_FAILURE\n',stderr=b'')):
                self.assertNotEqual(decoder.main(),0)

    def test_incomplete_or_wrong_cpu_signature_is_rejected(self):
        valid=[0x43505246,99,3,2,3,1,1]+[0]*9
        self.assertTrue(cpu.signature_valid(valid,False))
        for index in range(6):
            wrong=list(valid);wrong[index]^=1
            self.assertFalse(cpu.signature_valid(wrong,False),index)
        self.assertFalse(cpu.signature_valid(valid[:-1],False))
        self.assertFalse(cpu.signature_valid(valid,True))

    def test_changed_rom_digest_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build/video') as directory:
            p=Path(directory)/'rom.bin';p.write_bytes(b'ORIGINAL_ROM')
            digest=cpu.sha256(p)
            cpu.verify_digests({str(p):digest})
            p.write_bytes(b'ALTERED_ROM')
            with self.assertRaises(RuntimeError):cpu.verify_digests({str(p):digest})

if __name__=='__main__':unittest.main()

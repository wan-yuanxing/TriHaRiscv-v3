from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/video'))
from program_board import classify_log


class ProgramLogTests(unittest.TestCase):
    def test_zero_shell_exit_does_not_hide_verify_failure(self):
        log='PG2L100H\nThe ID value is:0x00602899\nExecuting : cfg_program -device_index 0 successfully.\nE: Missing mask\n'
        result=classify_log(log,0)
        self.assertTrue(result['programmed'])
        self.assertFalse(result['verified'])
        self.assertEqual(result['status'],'fail')

    def test_requires_both_success_markers_and_matching_device(self):
        log='PG2L100H\nThe ID value is:0x00602899\nExecuting : cfg_program -device_index 0 successfully.\nExecuting : cfg_verify -device_index 0 successfully.\n'
        self.assertEqual(classify_log(log,0)['status'],'pass')
        self.assertEqual(classify_log(log.replace('00602899','ffffffff'),0)['status'],'fail')
        self.assertEqual(classify_log(log,1)['status'],'fail')


if __name__=='__main__':unittest.main()

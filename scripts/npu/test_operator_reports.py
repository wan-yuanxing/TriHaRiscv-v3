import unittest
import build_operator


class MappingMarkerTests(unittest.TestCase):
    def test_acceptance_gate_survives_optimized_python(self):
        with self.assertRaisesRegex(RuntimeError, 'rejected'):
            build_operator.require(False, 'rejected')

    def test_pds_detailed_completion_marker(self):
        check=getattr(build_operator,'mapping_completed',lambda text:False)
        self.assertTrue(check('Executing : dev_map -detail successfully.\n'))

    def test_pds_plain_completion_marker(self):
        check=getattr(build_operator,'mapping_completed',lambda text:False)
        self.assertTrue(check('Executing : dev_map successfully.\n'))

    def test_started_or_failed_is_not_completion(self):
        check=getattr(build_operator,'mapping_completed',lambda text:False)
        for text in ('Executing : dev_map -detail\n','Executing : dev_map failed.\n','not Executing : dev_map successfully.\n'):
            self.assertFalse(check(text))

if __name__=='__main__':unittest.main()

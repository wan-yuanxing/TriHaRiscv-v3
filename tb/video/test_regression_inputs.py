import sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/video'))
import run
import common


class RegressionInputTests(unittest.TestCase):
    def test_later_suite_cannot_relabel_earlier_suite_with_changed_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            source=root/'rtl.sv';source.write_text('old',encoding='utf-8')
            with patch.object(common,'ROOT',root):
                result={'inputs':common.input_hashes([source])}
                recorded=dict(result['inputs'])
                source.write_text('new',encoding='utf-8')
                with self.assertRaisesRegex(RuntimeError,'changed'):
                    run.add_inputs(result,[source])
                self.assertEqual(result['inputs'],recorded)


if __name__=='__main__':unittest.main()

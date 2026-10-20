"""Area denominators must come from the CPU hierarchy, with frozen RTL binding."""
import unittest
import cpu_area


class CpuHierarchy(unittest.TestCase):
    def test_elaborated_predictor_profile_rejects_other_capacity(self):
        self.assertTrue(hasattr(cpu_area, 'review_predictor'), 'elaborated predictor profile check is missing')
        text = ''
        parameters = dict(NUM_BTB_ENTRIES=512, NUM_BTB_ENTRIES_W=9, NUM_BHT_ENTRIES=512,
                          NUM_BHT_ENTRIES_W=9, NUM_RAS_ENTRIES=4, NUM_RAS_ENTRIES_W=2, GSHARE_ENABLE=0, BTB_DIRECT_MAPPED=1)
        for tail in ('', '/u_frontend', '/u_frontend/u_npc'):
            text += 'I: Module instance {triha_cpu_board_top/u_soc/u_core/u_cpu' + tail + '} parameter value:\n'
            text += ''.join(f'    {key} = 32\'b{value:032b}\n' for key, value in parameters.items())
        cpu_area.review_predictor(text)
        with self.assertRaises(ValueError):
            cpu_area.review_predictor(text.replace('00000000000000000000001000000000', '00000000000000000000000000100000', 1))

    def test_uses_core_hierarchy_instead_of_whole_system(self):
        self.assertTrue(hasattr(cpu_area, 'parse_resources'), 'CPU area parser is missing')
        text = '| triha_cpu_board_top | 15000 | 12000 | 64 | 4 | 8.0 |\n| + u_core | 12345 | 11000 | 64 | 4 | 0.0 |\n'
        self.assertEqual(cpu_area.parse_resources(text)['lut'], 12345)

    def test_missing_duplicate_or_wrong_scope_is_rejected(self):
        self.assertTrue(hasattr(cpu_area, 'parse_resources'), 'CPU area parser is missing')
        row = '| + u_core | 12345 | 11000 | 64 | 4 | 0.0 |\n'
        for text in ('', row + row, row.replace('u_core', 'u_soc')):
            with self.subTest(text=text), self.assertRaises(ValueError):
                cpu_area.parse_resources(text)


if __name__ == '__main__':
    unittest.main()

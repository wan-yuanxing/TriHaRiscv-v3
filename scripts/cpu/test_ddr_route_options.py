"""A bounded placement comparison may change only the requested seed."""
import unittest
from run_ddr_board_route import pnr_command


class RouteOptions(unittest.TestCase):
    def test_seed_is_the_only_command_difference(self):
        first = pnr_command(20, 1)
        second = pnr_command(20, 2)
        self.assertEqual(first.replace('-gplace_seed 1 ', '-gplace_seed 2 '), second)
        for value in ('-action_timeout 20', '-optimize_multi_corner_timing',
                      '-fix_hold_violation ', '-fix_hold_violation_iterations 5'):
            self.assertIn(value, second)

    def test_seed_validation_cannot_inject_tool_options(self):
        for seed in (0, -1, 21, True, '2 -fix_hold_violation FALSE'):
            with self.subTest(seed=seed), self.assertRaises(ValueError):
                pnr_command(20, seed)


if __name__ == '__main__':
    unittest.main()

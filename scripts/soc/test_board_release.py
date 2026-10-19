"""Release identity checks: matching bytes alone cannot identify the routed run."""
from pathlib import Path
import tempfile
import unittest

import review_board
from run import sha


class RoutedDatabaseBinding(unittest.TestCase):
    def setUp(self):
        self.assertTrue(hasattr(review_board, "review_routed_database"),
                        "release review must bind the selected routed database")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name).resolve()

    def routed(self, seed=None):
        folder = self.work / "place_route"
        if seed is not None:
            folder /= f"seed_{seed}"
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / "triha_cpu_board_top_pnr.adf"
        path.write_bytes(b"routed-database-test-fixture")
        return path

    def result(self, path):
        return dict(bitstream_input_db=str(path), bitstream_input_db_sha256=sha(path))

    def test_single_run_database(self):
        path = self.routed()
        self.assertEqual(review_board.review_routed_database(self.work, self.result(path), 8, False), path)

    def test_selected_multiseed_database(self):
        path = self.routed(8)
        self.assertEqual(review_board.review_routed_database(self.work, self.result(path), 8, True), path)

    def test_other_seed_with_identical_bytes_is_rejected(self):
        expected = self.routed(8)
        other = self.routed(7)
        self.assertEqual(sha(expected), sha(other))
        with self.assertRaisesRegex(ValueError, "selected routed"):
            review_board.review_routed_database(self.work, self.result(other), 8, True)

    def test_other_run_with_identical_bytes_is_rejected(self):
        self.routed()
        other = self.work / "unselected_pnr.adf"
        other.write_bytes(b"routed-database-test-fixture")
        with self.assertRaisesRegex(ValueError, "selected routed"):
            review_board.review_routed_database(self.work, self.result(other), 8, False)


if __name__ == "__main__":
    unittest.main()

"""Cached CPU mode must be explicit and cannot leak into component-only tests."""
import contextlib
import io
import unittest

import run_cache


class CachedIssueModeTests(unittest.TestCase):
    def parse(self, *arguments):
        self.assertTrue(hasattr(run_cache, 'parse_args'), 'mode-aware Cache argument parser is missing')
        return run_cache.parse_args(list(arguments))

    def test_default_retains_single_issue(self):
        self.assertEqual(self.parse().issue_mode, 'single')

    def test_real_cpu_and_coremark_accept_explicit_dual(self):
        for target in ('cpu', 'coremark'):
            with self.subTest(target=target):
                args = self.parse('--test', target, '--issue-mode', 'dual')
                self.assertEqual(args.issue_mode, 'dual')
                self.assertEqual(args.test, target)

    def test_component_cases_reject_dual_without_running_tools(self):
        for target in ('components', 'writeback', 'overlap', 'transport', 'joint'):
            with self.subTest(target=target), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as rejected:
                    self.parse('--test', target, '--issue-mode', 'dual')
                self.assertEqual(rejected.exception.code, 2)

    def test_snapshot_requires_cpu_boundary(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            self.parse('--cpu-snapshot', 'build/cpu/candidate/rtl/cpu')
        args = self.parse('--test', 'coremark', '--issue-mode', 'dual',
                          '--cpu-snapshot', 'build/cpu/candidate/rtl/cpu')
        self.assertEqual(str(args.cpu_snapshot).replace('\\', '/'), 'build/cpu/candidate/rtl/cpu')

    def test_snapshot_preserves_non_cpu_sources_and_requires_candidate_file(self):
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            candidate = root / 'candidate'
            candidate.mkdir()
            (candidate / 'triha_issue.v').write_text('candidate', encoding='utf-8')
            self.assertEqual(run_cache.source_origin(root, 'rtl/cpu/triha_issue.v', candidate),
                             candidate / 'triha_issue.v')
            self.assertEqual(run_cache.source_origin(root, 'rtl/cpu/triha_cached_core.v', candidate),
                             root / 'rtl/cpu/triha_cached_core.v')
            self.assertEqual(run_cache.source_origin(root, 'rtl/soc/triha_cpu_cache_axi.v', candidate),
                             root / 'rtl/soc/triha_cpu_cache_axi.v')
            self.assertEqual(run_cache.source_origin(root, 'rtl/cpu/vendor/src/core/biriscv_alu.v', candidate),
                             root / 'rtl/cpu/vendor/src/core/biriscv_alu.v')
            with self.assertRaises(FileNotFoundError):
                run_cache.source_origin(root, 'rtl/cpu/triha_decode.v', candidate)

    def test_invalid_mode_is_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as rejected:
                self.parse('--test', 'cpu', '--issue-mode', 'automatic')
        self.assertEqual(rejected.exception.code, 2)


if __name__ == '__main__':
    unittest.main()

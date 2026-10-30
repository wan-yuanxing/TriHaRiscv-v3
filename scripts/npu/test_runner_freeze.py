"""Real simulator regression: editing an input during a run must reject PASS."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import unittest
from unittest import mock
import uuid

ROOT = Path(__file__).resolve().parents[2]


class RunnerFreezeTests(unittest.TestCase):
    def exercise(self, runner, mutation):
        fixture = ROOT / 'build/npu' / ('freeze_test_' + uuid.uuid4().hex[:8])
        for relative in ('scripts/npu', 'scripts/video/common.py', 'rtl/npu', 'tb/npu',
                         'config/npu_regs.json', 'sw/include/npu_regs.h'):
            source, target = ROOT / relative, fixture / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                shutil.copytree(source, target, ignore=shutil.ignore_patterns('__pycache__'))
            else:
                shutil.copy2(source, target)
        script = fixture / 'scripts/npu' / runner
        spec = importlib.util.spec_from_file_location('fixture_' + uuid.uuid4().hex, script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        real_run = module.subprocess.run if hasattr(module, 'subprocess') else None
        if real_run is None:
            import subprocess
            real_run = subprocess.run
        mutated = []

        def run(*args, **kwargs):
            result = real_run(*args, **kwargs)
            argv = [str(value) for value in args[0]]
            if not mutated and Path(argv[0]).stem.lower() in ('vvp', 'vsim') and not any(
                    value in ('-V', '-version') for value in argv):
                if mutation == 'original':
                    target = fixture / 'rtl/npu' / {
                        'run_scalar.py': 'npu_scalar_conv.v',
                        'test_mmio_runner.py': 'npu_operator_mmio.v',
                        'test_dma_runner.py': 'npu_axi128_single.v',
                    }[runner]
                else:
                    target = next((fixture / 'build/npu').rglob('inputs/rtl/npu/*.v'))
                target.write_bytes(target.read_bytes() + b'\n// concurrent edit probe\n')
                mutated.append(str(target))
            return result

        import subprocess
        arguments = [str(script)]
        if runner == 'run_scalar.py':
            arguments += ['--case', 'positive_tie']
        if runner == 'test_mmio_runner.py':
            arguments += ['--sim-only']
        with mock.patch.object(sys, 'argv', arguments), mock.patch.object(subprocess, 'run', run), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = module.main()
        self.assertTrue(mutated)
        self.assertEqual(code, 1, 'runner falsely accepted changed simulation input')
        results = list((fixture / 'build/npu').rglob('result.json'))
        self.assertEqual(len(results), 1)
        value = json.loads(results[0].read_text(encoding='utf-8'))
        self.assertIn('changed', value['error'])
        self.assertFalse(value.get('source_unchanged', False))

    def test_scalar_original(self): self.exercise('run_scalar.py', 'original')
    def test_mmio_original(self): self.exercise('test_mmio_runner.py', 'original')
    def test_dma_original(self): self.exercise('test_dma_runner.py', 'original')
    def test_scalar_frozen(self): self.exercise('run_scalar.py', 'frozen')
    def test_mmio_frozen(self): self.exercise('test_mmio_runner.py', 'frozen')
    def test_dma_frozen(self): self.exercise('test_dma_runner.py', 'frozen')


if __name__ == '__main__': unittest.main()

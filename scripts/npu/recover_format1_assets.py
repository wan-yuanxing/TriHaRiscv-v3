"""Recover missing format1 inputs from the pinned B03 integer model.

Writes only to a fresh build directory. The final bytes must match the
committed B03 manifest; this is asset recovery, not RTL validation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
REVISION = '558280b30219acdcf9f962acd6e907e0f680ab52'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def recover(upstream, out):
    import numpy as np
    upstream, out = upstream.resolve(), out.resolve()
    if not out.is_relative_to(ROOT/'build'):
        raise ValueError('Recovery outputs must remain under build/')
    if subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', 'HEAD']).decode().strip() != REVISION:
        raise ValueError('Expected the pinned B03 upstream revision')
    subprocess.run(['git', '-C', str(upstream), 'diff', '--exit-code', REVISION, '--',
                    'yunet/python', 'yunet/models', 'yunet/baseline'], check=True, capture_output=True)
    out.mkdir(parents=True, exist_ok=False)
    numeric = out/'numeric'; numeric.mkdir()
    sys.path.insert(0, str(upstream/'yunet/python'))
    from ptq_integer import IntegerModel
    import program_abi
    shutil.copyfile(upstream/'yunet/baseline/ptq_calibration_ranges_v1.json', numeric/'calibration_ranges.json')
    plan = IntegerModel(numeric/'calibration_ranges.json', 'bbox16').export(numeric/'bbox16')
    frozen = upstream/'yunet/models/yunet_int8_numeric_v1.npz'
    with np.load(frozen, allow_pickle=False) as expected, np.load(numeric/'bbox16/parameters.npz', allow_pickle=False) as generated:
        if set(expected.files) != set(generated.files):
            raise ValueError('Numeric array inventory differs')
        for name in expected.files:
            if not np.array_equal(expected[name], generated[name]):
                raise ValueError('Numeric array differs: '+name)
        checked = len(expected.files)
    # NPZ container encoding can vary by NumPy version. After every array
    # matches, use the immutable admitted container required by the compiler.
    shutil.copyfile(frozen, numeric/'bbox16/parameters.npz')
    plan['parameters_sha256'] = sha(frozen)
    (numeric/'bbox16/integer_plan.json').write_text(json.dumps(plan, indent=2)+'\n', encoding='utf-8')
    program_abi.DEFAULT = numeric  # redirect generated inputs, not numerical rules
    program, parameters, _, _ = program_abi.compile_program()
    manifest = json.loads((ROOT/'model/yunet/upstream/b03_558280b/package_manifest.json').read_bytes())
    data = {'program.bin': program_abi.pack(program), 'parameter_image.bin': parameters}
    digests = {}
    for name, payload in data.items():
        digests[name] = hashlib.sha256(payload).hexdigest()
        if digests[name] != manifest['source_sha256']['yunet/reports/program_abi_v0_1_checked/'+name]:
            raise ValueError('Recovered byte hash differs: '+name)
    for name, payload in data.items():
        (out/name).write_bytes(payload)
    result = dict(status='PASS_PINNED_BYTES', upstream_commit=REVISION,
                  numeric_arrays_compared=checked, numpy_version=np.__version__, files=digests,
                  generator_sha256=sha(__file__), board_verified=False)
    (out/'result.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--npu-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(recover(args.npu_root, args.output), indent=2))


if __name__ == '__main__':
    main()

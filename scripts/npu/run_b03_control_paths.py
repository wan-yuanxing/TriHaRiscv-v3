"""Frozen graph admission and gather equivalence checks; no physical claim."""
import argparse
from pathlib import Path
import subprocess
import sys
from frozen_inputs import FrozenInputs
from run_b03_frame import ROOT, VENDOR, VENDOR_FILES, common, check_log, need
import import_b03


def run(output, graph_source=None, gather_source=None):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    result = {'status': 'RUNNING', 'board_verified': False}
    common.write_json(output/'result.json', result)
    try:
        import_b03.verify_import(ROOT)
        sources = (ROOT/'config/npu_b03_sources.f').read_text(encoding='utf-8').splitlines()
        tests = [('tb_b03_graph_regions', 'GRAPH_PAIR_PASS cases=1024'),
                 ('tb_b03_graph_cancel', 'GRAPH_PAIR_PASS cases=80'),
                 ('tb_b03_gather_address', 'GATHER_ADDRESS_PASS cases=50000')]
        names = sources + ['tb/npu/'+name+'.sv' for name, _ in tests]
        names += ['tb/npu/fixtures/b03_gather_before_parallel_check.v',
                  'scripts/npu/run_b03_control_paths.py', 'scripts/npu/frozen_inputs.py',
                  'scripts/npu/run_b03_frame.py', 'scripts/npu/import_b03.py',
                  'scripts/video/common.py', 'config/npu_b03_sources.f',
                  'rtl/npu/upstream/b03/UPSTREAM.json']
        frozen = FrozenInputs(ROOT, output/'inputs', names)
        overrides = {}
        for leaf, source in [('b03_graph_engine_cap.v', graph_source),
                             ('b03_gather_lean.v', gather_source)]:
            if source is not None:
                destination = output/'candidate'/leaf
                frozen.external(source.resolve(), destination)
                overrides['rtl/npu/upstream/b03/rtl/platform/'+leaf] = destination
        vendors = []
        for name in VENDOR_FILES:
            destination = output/'vendor'/name
            frozen.external(VENDOR/name, destination)
            vendors.append(destination)
        files = vendors + [overrides.get(name, frozen.directory/name)
                           for name in names if name.endswith(('.v', '.sv'))]
        filelist = output/'sources.f'
        filelist.write_text(''.join('"'+p.as_posix()+'"\n' for p in files), encoding='utf-8')
        frozen.track(filelist)
        vsim = common.tool('vsim')
        frozen.track(vsim)
        diagnostics = {}
        for index, (name, expected) in enumerate(tests):
            script = output/(name+'.do')
            compile_step = 'vlib work\nvlog -sv -f sources.f\n' if index == 0 else ''
            script.write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\n'
                              +compile_step+'vsim -voptargs=+acc -t 1ps work.'+name
                              +'\nrun -all\nquit -code 0 -force\n', encoding='utf-8')
            frozen.track(script)
            with (output/(name+'.log')).open('wb') as stream:
                process = subprocess.run([str(vsim), '-c', '-do', script.name], cwd=output,
                                         stdout=stream, stderr=subprocess.STDOUT, timeout=120,
                                         creationflags=subprocess.CREATE_NO_WINDOW)
            frozen.verify()
            need(process.returncode == 0, name+' simulation failed')
            log = (output/(name+'.log')).read_text(encoding='utf-8', errors='replace')
            diagnostics[name] = check_log(log, [expected])
        result.update(status='PASS', diagnostics=diagnostics,
                      inputs_unchanged=True, source_sha256=frozen.inputs,
                      external_sha256=frozen.external_inputs, tracked_sha256=frozen.tracked,
                      isolated_overrides=sorted(overrides), graph_region_cases=1024,
                      graph_cancel_cases=80, gather_cycle_cases=50000)
    except Exception as error:
        result.update(status='FAIL', error=str(error))
    common.write_json(output/'result.json', result)
    print(result['status'], result.get('error', ''), flush=True)
    return int(result['status'] != 'PASS')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--graph-source', type=Path)
    parser.add_argument('--gather-source', type=Path)
    args = parser.parse_args()
    sys.exit(run(args.output, args.graph_source, args.gather_source))

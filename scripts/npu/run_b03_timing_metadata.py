"""Frozen vector stage-boundary and opt-in graph admission regression."""
import argparse
from pathlib import Path
import subprocess
import sys
from frozen_inputs import FrozenInputs
from run_b03_frame import ROOT, VENDOR, VENDOR_FILES, common, check_log, need


def run(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    result = {'status': 'RUNNING', 'board_verified': False}
    common.write_json(output/'result.json', result)
    try:
        test = 'tb_b03_input_plan' if args.input_plan else 'tb_b03_graph_multiply' if args.multiply else 'tb_b03_layer_control' if args.layer else 'tb_b03_graph_layout' if args.graph else 'tb_b03_vector_metadata'
        expected = 'INPUT_PLAN_PASS cases=4096' if args.input_plan else 'GRAPH_MULTIPLY_PASS numeric=512 abort=5' if args.multiply else 'LAYER_CONTROL_PASS cases=8416' if args.layer else 'GRAPH_LAYOUT_PASS cases=48' if args.graph else 'VECTOR_METADATA_PASS terminal=8192 quant=2048'
        names = (ROOT/'config/npu_b03_sources.f').read_text(encoding='utf-8').splitlines()
        names += ['tb/npu/'+test+'.sv', 'scripts/npu/run_b03_timing_metadata.py',
                  'scripts/npu/frozen_inputs.py', 'scripts/npu/run_b03_frame.py', 'scripts/video/common.py']
        frozen = FrozenInputs(ROOT, output/'inputs', names)
        vendors = []
        for name in VENDOR_FILES:
            destination = output/'vendor'/name
            frozen.external(VENDOR/name, destination)
            vendors.append(destination)
        sources = vendors+[frozen.directory/n for n in names if n.endswith(('.v', '.sv'))]
        if args.source:
            leaf = 'b03_model_input_payload.v' if args.input_plan else 'b03_layer_exec_payload.v' if args.layer else 'b03_graph_engine_cap.v' if (args.graph or args.multiply) else 'b03_vector_exec_compact.v'
            destination = output/'candidate'/leaf
            frozen.external(args.source.resolve(), destination)
            original = frozen.directory/'rtl/npu/upstream/b03/rtl/platform'/leaf
            sources = [destination if p == original else p for p in sources]
        filelist = output/'sources.f'
        filelist.write_text(''.join('"'+p.as_posix()+'"\n' for p in sources), encoding='utf-8')
        script = output/'run.do'
        define = '+define+LAYOUT_OPT_IN ' if args.opt_in else ''
        script.write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nvlib work\n'
                          +'vlog -sv '+define+'-f sources.f\nvsim -voptargs=+acc -t 1ps work.'+test
                          +'\nrun -all\nquit -code 0 -force\n', encoding='utf-8')
        frozen.track(filelist); frozen.track(script)
        vsim = common.tool('vsim'); frozen.track(vsim)
        with (output/'console.log').open('wb') as stream:
            process = subprocess.run([str(vsim), '-c', '-do', 'run.do'], cwd=output,
                                     stdout=stream, stderr=subprocess.STDOUT, timeout=120,
                                     creationflags=subprocess.CREATE_NO_WINDOW)
        frozen.verify()
        need(process.returncode == 0, 'Simulation failed: '+str(output/'console.log'))
        diagnostics = check_log((output/'console.log').read_text(encoding='utf-8', errors='replace'), [expected])
        result.update(status='PASS', inputs_unchanged=True, diagnostics=diagnostics,
                      source_sha256=frozen.inputs, external_sha256=frozen.external_inputs,
                      tracked_sha256=frozen.tracked)
    except Exception as exc:
        result.update(status='FAIL', error=str(exc))
    common.write_json(output/'result.json', result)
    print(result['status'], result.get('error', ''), flush=True)
    return int(result['status'] != 'PASS')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--graph', action='store_true')
    parser.add_argument('--multiply', action='store_true')
    parser.add_argument('--input-plan', action='store_true')
    parser.add_argument('--layer', action='store_true')
    parser.add_argument('--opt-in', action='store_true')
    sys.exit(run(parser.parse_args()))

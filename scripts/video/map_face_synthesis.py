"""Continue a frozen face synthesis in a new directory without resynthesizing."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import time

from build_pds import prepare_physical_constraints, tcl_path, verify_build_inputs, review_messages
from common import ROOT, sha256, tool, write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--synthesis', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source, out = args.synthesis.resolve(), args.output.resolve()
    if not out.is_relative_to(ROOT / 'build/video'):
        parser.error('Output must be a new directory under build/video')
    out.mkdir(parents=True, exist_ok=False)
    record = dict(status='running', target='triha_face_board', stage='map', physical_board=False)
    try:
        original = json.loads((source / 'result.json').read_text(encoding='utf-8'))
        if (original['status'] != 'pass' or original['stage'] != 'synth'
                or original['target'] != 'triha_face_board'
                or original['face_profile'] not in ('box', 'avatar')):
            raise ValueError('Expected a completed face synthesis')
        verify_build_inputs(source, original)
        for name in ('src', 'ip', 'vendor'):
            shutil.copytree(source / name, out / name)
        for name in ('rom.hex', 'sram.hex', 'firmware.elf', 'synth.log',
                     'compile/triha_face_board_top_comp.adf',
                     'synthesize/triha_face_board_top_syn.adf',
                     'synthesize/triha_face_board_top.snr'):
            target = out / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / name, target)
        record.update(original)
        record.update(status='running', stage='map', directory=str(out.relative_to(ROOT)),
                      source_synthesis=dict(path=str(source), result_sha256=sha256(source/'result.json')))
        write_json(out / 'result.json', record)
        script = out / 'map.tcl'
        script.write_text('set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676\n'
                          + 'dev_map -force_to_run -input_db_file '
                          + tcl_path(out / 'synthesize/triha_face_board_top_syn.adf') + '\n', encoding='utf-8')
        pds = tool('pds_shell')
        start = time.monotonic()
        with (out / 'map.log').open('wb') as log:
            proc = subprocess.run([str(pds), '-file', str(script), '-work_dir', str(out),
                                   '-project_name', 'face_map'], cwd=out, stdout=log,
                                  stderr=subprocess.STDOUT, timeout=900,
                                  creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        log_text = (out / 'map.log').read_text(encoding='utf-8', errors='replace')
        reference = (ROOT/'build/video/vendor/hdmi/HDMI_IN_DDR3_HDMI_OUT_top.fdc').read_text(encoding='utf-8')
        reference += '\n' + (out/'src/fpga/pg2l100h/constraints/triha_face_board.fdc').read_text(encoding='utf-8')
        reviewed, rejected = review_messages(log_text, reference)
        if proc.returncode or rejected:
            raise ValueError('Mapping failed or emitted unreviewed critical messages: ' + str(rejected[:3]))
        project = json.loads((out/'src/fpga/pg2l100h/project/triha_face_board.json').read_text(encoding='utf-8'))
        physical = prepare_physical_constraints(out, 'triha_face_board_top', project['post_map_constraints'])
        verify_build_inputs(source, original)
        verify_build_inputs(out, record)
        mapped = out/'device_map/triha_face_board_top_map.adf'
        record.update(status='pass', artifact=str(mapped.relative_to(ROOT)), artifact_sha256=sha256(mapped),
                      physical_constraints=dict(path=physical.name, sha256=sha256(physical)),
                      mapping_seconds=time.monotonic()-start, mapping_inputs={str(p):sha256(p) for p in
                          (source/'result.json', source/'synthesize/triha_face_board_top_syn.adf', script, pds, Path(__file__))},
                      reviewed_mapping_messages=reviewed, mapping_log_sha256=sha256(out/'map.log'))
    except Exception as error:
        record.update(status='fail', error=str(error))
    finally:
        write_json(out / 'result.json', record)
    print('FACE_MAP_' + record['status'].upper(), out, record.get('error', ''), flush=True)
    return int(record['status'] != 'pass')


if __name__ == '__main__':
    raise SystemExit(main())

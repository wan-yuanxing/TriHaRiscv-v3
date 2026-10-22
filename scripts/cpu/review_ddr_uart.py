"""Review saved physical DDR UART plus matching volatile Program/Verify evidence."""
import argparse
import json
from pathlib import Path

from run_cache import sha, save


def review_uart(data, expect_reboot=False):
    text = data.decode('ascii', errors='strict')
    if 'CPU_TRAP' in text or 'CPU_DDR_FAIL' in text:
        raise ValueError('physical DDR software failure or trap')
    pending = False
    complete = 0
    for line in text.splitlines():
        if not line:
            continue
        if line == 'CPU_DDR_BOOT' and not pending:
            pending = True
        elif line == 'CPU_DDR_PASS private=8192 shared=8192 fence_i=1' and pending:
            complete += 1
            pending = False
        else:
            raise ValueError('unexpected or incomplete DDR UART sequence: ' + line)
    if pending or complete < (2 if expect_reboot else 1):
        raise ValueError('missing complete DDR boot/self-test or reboot')
    return dict(complete_boots=complete, private_bytes_per_boot=8192,
        shared_bytes_per_boot=8192, fence_i=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--uart', type=Path, required=True)
    parser.add_argument('--program-record', type=Path, required=True)
    parser.add_argument('--key0-confirmed', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    program = json.loads(args.program_record.read_text(encoding='utf-8'))
    if (program['status'] != 'PASS' or program['native_return_code'] != 0 or
            not all(program[k] for k in ['device_found', 'programmed', 'verified']) or program['flash_written']):
        raise ValueError('missing successful volatile Program/Verify')
    package = Path(program['package'])
    if sha(package / 'manifest.json') != program['manifest_sha256']:
        raise ValueError('package manifest drift')
    manifest = json.loads((package / 'manifest.json').read_text(encoding='utf-8'))
    if (manifest['target'] != 'cpu_ddr_board' or not manifest['timing_closed'] or
            manifest['bitstream_sha256'] != program['bitstream_sha256'] or
            manifest['verify_mask_sha256'] != program['verify_mask_sha256']):
        raise ValueError('wrong physical DDR image')
    for name, digest in manifest['files'].items():
        if Path(name).name != name or sha(package / name) != digest:
            raise ValueError('release file drift: ' + name)
    for name, digest in program['output_hashes'].items():
        if sha(args.program_record.parent / name) != digest:
            raise ValueError('program log drift: ' + name)
    observed = review_uart(args.uart.read_bytes(), expect_reboot=args.key0_confirmed)
    row = dict(status='PASS', operation='physical_ddr_software_acceptance',
        observation=observed, physical_key0_confirmed=args.key0_confirmed,
        programmed=True, verified=True, flash_written=False,
        uart=dict(path=str(args.uart.resolve()), sha256=sha(args.uart)),
        program_record=dict(path=str(args.program_record.resolve()), sha256=sha(args.program_record)),
        package_manifest_sha256=program['manifest_sha256'], bitstream_sha256=program['bitstream_sha256'],
        reviewer_sha256=sha(__file__),
        scope='Physical standalone CPU/private-shared 8KiB/FENCE.I boots; not full DDR address coverage, electrical AC signoff, shared fabric or CoreMark')
    save(args.output, row)
    print('CPU_DDR_PHYSICAL_PASS', observed['complete_boots'], args.output)


if __name__ == '__main__':
    main()

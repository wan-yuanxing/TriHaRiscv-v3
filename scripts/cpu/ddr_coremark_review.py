"""Bind a full board workload to a successful short native DDR preflight."""
import json
from pathlib import Path

from run_cache import ROOT, sha
from ddr_coremark_firmware import payload_image


def load_verified(directory, full=False):
    directory = Path(directory).resolve()
    row = json.loads((directory / 'result.json').read_text(encoding='utf-8'))
    if (row['status'] != ('BUILT' if full else 'PASS') or row['runner_return_code'] != 0 or
            row['test'] != 'coremark' or row['fault'] != 'none' or row['build_only'] != full or
            row['iterations'] != (5000 if full else 1) or
            not all(row[k] for k in ['source_unchanged', 'external_unchanged', 'pinned_unchanged'])):
        raise ValueError('need matching unchanged full build / one-iteration DDR preflight')
    if '-O2' not in row['compiler_flags'] or any('lto' in v for v in row['compiler_flags']):
        raise ValueError('CoreMark must use O2 without LTO')
    for name, digest in row['input_hashes'].items():
        if sha(ROOT / name) != digest or sha(directory / 'src' / name) != digest:
            raise ValueError('DDR CoreMark source drift: ' + name)
    for name, digest in row['external_hashes'].items():
        if sha(name) != digest:
            raise ValueError('DDR CoreMark external drift: ' + name)
    for name, digest in row['output_hashes'].items():
        if sha(directory / name) != digest:
            raise ValueError('DDR CoreMark output drift: ' + name)
    if any(c['return_code'] != 0 or c.get('timed_out') for c in row['commands']):
        raise ValueError('DDR CoreMark native failure')
    if payload_image((directory / 'payload/firmware.elf').read_bytes(), row.get('placement_base', 0x80000000)) != (directory / 'payload/firmware.bin').read_bytes():
        raise ValueError('payload differs from linked loadable program')
    if not full:
        measurement = row['measurement']
        if measurement['crc'] != ['e9f5', 'e714', '1fd7', '8e3a']:
            raise ValueError('preflight CRC mismatch')
        text = (directory / 'simulation.log').read_text(encoding='utf-8')
        if ('CPU_DDR_COREMARK_PAYLOAD_PASS' not in text or 'CPU_DDR_COREMARK_SIM_PASS' not in text or
                'Errors: 0, Warnings: 0' not in text):
            raise ValueError('preflight did not execute the complete DDR path')
    return row


def pair(full_directory, preflight_directory):
    full = load_verified(full_directory, full=True)
    short = load_verified(preflight_directory)
    if (full['cache_enable'] != short['cache_enable'] or full['compiler_version'] != short['compiler_version'] or
            full.get('placement_base', 0x80000000) != short.get('placement_base', 0x80000000)):
        raise ValueError('CoreMark preflight configuration differs')
    for name, digest in full['input_hashes'].items():
        if name in short['input_hashes'] and short['input_hashes'][name] != digest:
            raise ValueError('CoreMark full/preflight source differs')
    return full, short

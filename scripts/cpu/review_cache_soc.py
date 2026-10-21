"""Independently re-read the cached local-SoC simulation and native area evidence."""
import argparse
import json
from pathlib import Path
import re

from check_cache import ROOT
from run_cache import sha, save
from compare_cache_runs import elf_sections


def verify_run(directory, root=ROOT, negative=False):
    directory, root = Path(directory).resolve(), Path(root).resolve()
    row = json.loads((directory/'result.json').read_text(encoding='utf-8'))
    wanted = 'FAIL' if negative else 'PASS'
    if (row['status'] != wanted or row['runner_return_code'] != int(negative) or
            not row['source_unchanged'] or not row['external_unchanged']):
        raise ValueError('invalid terminal evidence status: '+str(directory))
    for name, digest in row['input_hashes'].items():
        if sha(root/name) != digest:
            raise ValueError('current source drift: '+name)
        if sha(directory/'src'/name) != digest:
            raise ValueError('frozen source drift: '+name)
    for name, digest in row['external_hashes'].items():
        if sha(name) != digest:
            raise ValueError('external tool drift: '+name)
    for name, digest in row['output_hashes'].items():
        if sha(directory/name) != digest:
            raise ValueError('output drift: '+name)
    for name, digest in row.get('firmware_hashes', {}).items():
        if sha(name) != digest:
            raise ValueError('firmware binding drift: '+name)
    commands = row.get('commands', row.get('native_commands', []))
    if not commands or any(c['return_code'] != 0 or c.get('timed_out') for c in commands):
        raise ValueError('native command failure: '+str(directory))
    return row


def hierarchy(text, name):
    rows = re.findall(r'(?m)^\|[ +]*'+re.escape(name)+r'\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+([\d.]+)', text)
    if len(rows) != 1:
        raise ValueError('missing/duplicate area hierarchy: '+name)
    lut, ff, ram, apm, drm = rows[0]
    return dict(lut=int(lut), registers=int(ff), distributed_ram=int(ram), apm=int(apm), drm=float(drm))


def review(args):
    bound = {}
    evidence = {}
    for name in ['runtime', 'bypass_runtime', 'router', 'bypass_router', 'area']:
        directory = Path(getattr(args, name)).resolve()
        row = verify_run(directory)
        bound[str(directory/'result.json')] = sha(directory/'result.json')
        evidence[name] = row
        if name != 'area':
            text = (directory/'simulation.log').read_text(encoding='utf-8')
            marker = 'CPU_CACHE_SOC_PASS' if 'runtime' in name else 'CPU_CACHE_ROUTER_PASS'
            if marker not in text or any(s in text for s in ['CPU_CACHE_FAIL', '** Fatal', '** Error']):
                raise ValueError('missing real simulation success: '+name)
            if row['fault'] != 'none' or row['cache_enable'] != (not name.startswith('bypass')):
                raise ValueError('wrong actual comparison mode: '+name)
            if 'runtime' in name:
                expected = 'CACHE_ENABLE=0' if name.startswith('bypass') else 'CACHE_ENABLE=1'
                commands = ' '.join(' '.join(c['command']) for c in row['commands'])
                if '-g'+expected not in commands or 'traps=3' not in text:
                    raise ValueError('missing real mode/fault coverage')
    runtime, bypass = Path(args.runtime), Path(args.bypass_runtime)
    enabled_sections, _ = elf_sections(runtime/'firmware.elf')
    bypass_sections, _ = elf_sections(bypass/'firmware.elf')
    differences = [n for n in enabled_sections if enabled_sections[n] != bypass_sections.get(n)]
    if set(enabled_sections) != set(bypass_sections) or any(
            n != '.strtab' or enabled_sections[n]['flags'] != 0 for n in differences):
        raise ValueError('cache on/off ELF differs beyond non-loaded assembler temporary names')
    for name in ['rom.hex', 'sram.hex']:
        if (runtime/name).read_bytes() != (bypass/name).read_bytes():
            raise ValueError('cache on/off loaded image bytes differ')
    negatives = []
    for name in args.negative:
        directory = Path(name).resolve()
        row = verify_run(directory, negative=True)
        text = (directory/'simulation.log').read_text(encoding='utf-8')
        expected = 'transport watchdog' if row['fault'] == 'watchdog' else (
            'real firmware success exit' if row['test'] == 'runtime' else 'I returned instruction pair')
        if row['fault'] not in ['data', 'watchdog'] or 'CPU_CACHE_FAIL '+expected not in text:
            raise ValueError('negative rejected for unexpected reason')
        bound[str(directory/'result.json')] = sha(directory/'result.json')
        negatives.append(dict(directory=str(directory), test=row['test'], fault=row['fault'], expected_failure=expected))
    area_dir = Path(args.area)
    area = evidence['area']
    report = area_dir/'synthesize/triha_cached_soc_map_top.snr'
    text = report.read_text(encoding='utf-8')
    total = hierarchy(text, 'u_system')
    splits = {name:hierarchy(text, name) for name in ['u_core', 'u_cache', 'u_memory']}
    if total != area['resources'] or splits != area['hierarchy_resources'] or area['timing_closed']:
        raise ValueError('native area summary/scope mismatch')
    for stage in ['compile', 'synthesize', 'dev_map']:
        output = (area_dir/'pds.stdout.log').read_text(encoding='utf-8')
        if not re.search(r'(?m)^Executing : '+stage+r'(?: [^\r\n]*)? successfully\.\s*$', output):
            raise ValueError('native mapping stage missing: '+stage)
    compile_text = (area_dir/'compile/run.log').read_text(encoding='utf-8')
    expected = {'u_system':{'CACHE_ENABLE':1}, 'u_system/u_core':{'DUAL_ISSUE':0},
                'u_system/u_core/u_cpu':{'SUPPORT_DUAL_ISSUE':0, 'NUM_BTB_ENTRIES':512,
                    'NUM_BHT_ENTRIES':512, 'NUM_RAS_ENTRIES':4, 'GSHARE_ENABLE':0},
                'u_system/u_router/u_cache':{'ICACHE_ENABLE':1, 'DCACHE_ENABLE':1}}
    for scope, parameters in expected.items():
        blocks = re.findall(r'(?ms)^I: Module instance \{triha_cached_soc_map_top/'+re.escape(scope)+r'\} parameter value:\r?\n(.*?)(?=^I:|\Z)', compile_text)
        if len(blocks) != 1:
            raise ValueError('missing actual elaboration scope: '+scope)
        for key, value in parameters.items():
            fields = re.findall(r'(?m)^\s*'+key+r" = (?:1|32)'b([01]+)\s*$", blocks[0])
            if len(fields) != 1 or int(fields[0], 2) != value:
                raise ValueError('wrong actual elaboration parameter: '+scope+'/'+key)
    residual = {key:total[key]-sum(row[key] for row in splits.values()) for key in total}
    return dict(status='PASS', bound_results=bound, negative_checks=negatives,
        synthesis_hierarchy_resources=dict(total=total, **splits, router_logic=residual),
        identical_loaded_images=True, differing_nonloaded_elf_sections=differences,
        cache_100mhz_verified=False, physical_ddr_validated=False,
        programmed=False, scope='Local/cache routing functional and native mapping checkpoint; not deployment acceptance')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ['runtime', 'bypass-runtime', 'router', 'bypass-router', 'area']:
        parser.add_argument('--'+name, required=True, type=Path)
    parser.add_argument('--negative', action='append', default=[])
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = review(args)
    result['reviewer_sha256'] = sha(Path(__file__))
    save(args.output, result)
    print('CPU_CACHE_SOC_REVIEW_PASS', args.output)

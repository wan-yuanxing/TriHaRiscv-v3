"""Compare frozen write-through/write-back native-DDR RTL measurements.

This is a digital-model comparison. It never substitutes for board scoring or
actual post-route timing. Only the absolute initial timestamp may differ in the
architectural observation stream.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil

from run_cache import ROOT, sha
from compare_cache_runs import compare_traces, verify_outputs
from ddr_profile import parse_profile


def review(baseline, candidate, work):
    directories = [Path(p).resolve() for p in (baseline, candidate)]
    rows = [verify_outputs(p) for p in directories]
    if not all(r['test'] == 'coremark' and r['iterations'] == 5 and r['cache_enable'] == 1
               and r['pinned_unchanged'] and r['runner_return_code'] == 0 for r in rows):
        raise ValueError('need successful five-iteration native DDR profiles')
    if (directories[0]/'payload/firmware.bin').read_bytes() != (directories[1]/'payload/firmware.bin').read_bytes():
        raise ValueError('different loaded CoreMark programs')
    if rows[0]['compiler_version'] != rows[1]['compiler_version']:
        raise ValueError('compiler mismatch')
    allowed_rtl = {'rtl/cpu/triha_dcache.v', 'rtl/cpu/triha_dcache_tag_ram.v',
                   'rtl/cpu/triha_cache_subsystem.v', 'rtl/cpu/CACHE_ADAPTATIONS.json'}
    changed = []
    for name, digest in rows[0]['input_hashes'].items():
        if name.startswith(('sw/', 'rtl/')):
            if rows[1]['input_hashes'].get(name) != digest:
                if name not in allowed_rtl:
                    raise ValueError('unexpected program/RTL change: '+name)
                changed.append(name)
    profiles = []
    for row, directory in zip(rows, directories):
        if '-O2' not in row['compiler_flags'] or any('lto' in f or f == '-O3' for f in row['compiler_flags']):
            raise ValueError('optimization contract mismatch')
        profile = parse_profile((directory/'simulation.log').read_text(encoding='utf-8'), row['measurement']['cycles'])
        # The parser now explicitly labels legacy write-through evidence.
        recorded = dict(row['profile'])
        recorded.setdefault('write_policy', 'write_through')
        if recorded != profile:
            raise ValueError('recorded profile differs from actual transcript')
        profiles.append(profile)
        for entry in row['binding']['files'].values():
            if sha(entry['path']) != entry['sha256']:
                raise ValueError('pinned DDR input drift')
    if [p['write_policy'] for p in profiles] != ['write_through', 'write_back']:
        raise ValueError('need distinct actual policies')
    work = Path(work)
    work.mkdir(parents=True, exist_ok=False)
    aliases = []
    for label, source in zip(['baseline', 'candidate'], directories):
        folder = work/label
        folder.mkdir()
        for original, alias in [('ddr-profile.wb.log', 'cpu-cache.wb.log'),
                                ('ddr-profile.store.log', 'cpu-cache.store.log'),
                                ('payload/firmware.elf', 'firmware.elf')]:
            shutil.copyfile(source/original, folder/alias)
        aliases.append(folder)
    traces = compare_traces(*aliases)
    before, after = [r['measurement']['cycles'] for r in rows]
    if after >= before or profiles[1]['dcache']['lower_writes'] >= profiles[0]['dcache']['lower_writes']:
        raise ValueError('writeback did not improve modeled cycles and lower write traffic')
    row = dict(status='PASS_DIGITAL_DIAGNOSTIC',
        scope='Same-payload five-iteration RTL/native DDR model; no official or physical board score',
        reviewer_sha256=sha(__file__),
        results=[dict(path=str(p/'result.json'), sha256=sha(p/'result.json')) for p in directories],
        changed_rtl=sorted(changed),
        loaded_payload_sha256=sha(directories[0]/'payload/firmware.bin'),
        measurements=[r['measurement'] for r in rows], profiles=profiles,
        trace_comparison=traces, same_loaded_payload=True,
        cycles_reduced=before-after, cycles_reduced_percent=(1-after/before)*100,
        throughput_gain_percent=(before/after-1)*100,
        dirty_data_remains_cached_at_timer_stop=True,
        maintenance_and_eviction_validated_separately=True,
        uart_lut_denominator_is_prior_metadata=True,
        actual_postroute_100mhz=False, board_score_improvement_proven=False,
        programmed=False)
    (work/'result.json').write_text(json.dumps(row,indent=2)+'\n',encoding='utf-8',newline='\n')
    return row


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline',type=Path,required=True)
    parser.add_argument('--candidate',type=Path,required=True)
    args = parser.parse_args()
    work = ROOT/'build/cpu'/('ddr-writeback-review-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    row = review(args.baseline,args.candidate,work)
    print('CPU_DDR_WRITEBACK_REVIEW',row['status'],work/'result.json')

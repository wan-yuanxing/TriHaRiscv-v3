"""Read-only source, policy and address-attribute preflight for CPU Cache work."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]


def validate(root=ROOT):
    root = Path(root).resolve()
    checked = set()

    def path(name):
        if not isinstance(name, str) or '\\' in name or ':' in name or '..' in PurePosixPath(name).parts or PurePosixPath(name).is_absolute():
            raise ValueError('unsafe Cache input path')
        target = root/name
        if not target.resolve().is_relative_to(root):
            raise ValueError('Cache path escapes project')
        checked.add(name)
        return target

    def load(name):
        return json.loads(path(name).read_text(encoding='utf-8'))

    def bind(name, expected, label):
        if hashlib.sha256(path(name).read_bytes()).hexdigest() != expected:
            raise ValueError(label + ' byte/hash mismatch: ' + name)

    cfg = load('config/cpu_cache.json')
    if cfg['schema_version'] != 1 or cfg['clock_hz'] != 100000000 or cfg['icache'] != dict(bytes=16384, ways=2, line_bytes=32):
        raise ValueError('Cache geometry/clock mismatch')
    if cfg['dcache'] != dict(bytes=16384, ways=2, line_bytes=32, write_policy='write_through', write_allocate=False, posted_writes=False):
        raise ValueError('D Cache policy mismatch')
    if (cfg['private_ddr_base'],cfg['private_ddr_bytes'],cfg['shared_ddr_base'],cfg['shared_ddr_bytes']) != (0x80000000,0x2000000,0x82000000,0x6000000):
        raise ValueError('Cache private/shared address contract mismatch')
    if cfg['lower_axi_data_bits'] != 128 or cfg['lower_axi_id_bits'] != 4:
        raise ValueError('Cache lower AXI geometry mismatch')
    counts = []
    for manifest, folder, count in [
        ('rtl/cpu/vendor/UPSTREAM.json','rtl/cpu/vendor',28),
        ('sw/benchmarks/coremark/UPSTREAM.json','sw/benchmarks/coremark/src',9),
        ('rtl/cpu/vendor/CACHE_UPSTREAM.json','rtl/cpu/vendor',7),
    ]:
        row = load(manifest)
        if len(row['files']) != count:
            raise ValueError('original manifest file count mismatch')
        for name, digest in row['files'].items():
            bind(folder+'/'+name,digest,'original')
        counts.append(count)
    upstream = load('rtl/cpu/vendor/CACHE_UPSTREAM.json')
    if upstream['revision'] != '6af9c4be5a0807d368eaad5e49af52322e31d073':
        raise ValueError('original Cache revision mismatch')
    for name, expected in upstream['git_blobs'].items():
        data = path('rtl/cpu/vendor/'+name).read_bytes()
        digest = hashlib.sha1(b'blob '+str(len(data)).encode('ascii')+b'\0'+data).hexdigest()
        if digest != expected:
            raise ValueError('original Cache Git blob mismatch')
    adaptations = load('rtl/cpu/CACHE_ADAPTATIONS.json')
    if adaptations['schema_version'] != 1 or len(adaptations['files']) != 6:
        raise ValueError('Cache adaptation schema mismatch')
    for name, entry in adaptations['files'].items():
        bind(entry['base'],entry['base_sha256'],'original')
        bind(name,entry['derived_sha256'],'derived')
    for name,digest in adaptations['new_files'].items():
        bind(name,digest,'derived new module')
    sources = [s.strip() for s in path('config/cpu_cache_sources.f').read_text(encoding='utf-8').splitlines() if s.strip() and not s.startswith('#')]
    for name in sources:
        path(name)
    expected = set(adaptations['files']) | {'rtl/cpu/triha_ifetch_uncached.v'}
    if len(sources) != len(expected) or set(sources) != expected:
        raise ValueError('Cache explicit source list mismatch')
    project = load('fpga/pg2l100h/project/cpu_cache.json')
    extra = {'rtl/soc/triha_cpu_cache_axi.v','rtl/cpu/triha_cache_subsystem.v','fpga/pg2l100h/rtl/triha_cache_map_top.v'}
    if set(project['sources']) != expected | extra or len(project['sources']) != len(expected | extra):
        raise ValueError('Cache PDS source list mismatch')
    if project['top'] != 'triha_cache_map_top' or project['cache_instance'] != 'u_cache':
        raise ValueError('Cache mapping fixture scope mismatch')
    for name in project['sources'] + project['constraints']:
        path(name)
    path('scripts/cpu/check_cache.py')
    return dict(status='PASS', original_counts=counts, sources=sources, validated_paths=sorted(checked),
                cache_100mhz_verified=False, programmed=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    result = validate()
    print(json.dumps(result,indent=2) if args.json else 'CPU_CACHE_PREFLIGHT_PASS originals=28+9+7 private_ddr_only=1')

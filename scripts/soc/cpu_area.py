"""CPU hierarchy LUT count and unchanged native synthesis evidence binding."""
import json
from pathlib import Path
import re

from gen_board import ROOT
from run import sha


def review_predictor(text):
    expected = dict(NUM_BTB_ENTRIES=512, NUM_BTB_ENTRIES_W=9, NUM_BHT_ENTRIES=512,
                    NUM_BHT_ENTRIES_W=9, NUM_RAS_ENTRIES=4, NUM_RAS_ENTRIES_W=2, GSHARE_ENABLE=0, BTB_DIRECT_MAPPED=1)
    base = 'triha_cpu_board_top/u_soc/u_core/u_cpu'
    for tail in ('', '/u_frontend', '/u_frontend/u_npc'):
        blocks = re.findall(r'(?ms)^I: Module instance \{' + re.escape(base + tail) +
                            r'\} parameter value:\r?\n(.*?)(?=^I:|\Z)', text)
        if len(blocks) != 1:
            raise ValueError('missing or duplicate elaborated predictor scope: ' + base + tail)
        for key, value in expected.items():
            fields = re.findall(r'(?m)^\s*' + key + r" = (1|32)'b([01]+)\s*$", blocks[0])
            if len(fields) != 1 or len(fields[0][1]) != int(fields[0][0]) or int(fields[0][1], 2) != value:
                raise ValueError('wrong elaborated predictor parameter: ' + key)
    return dict(btb=512, bht=512, ras=4, gshare=False)


def parse_resources(text):
    rows = re.findall(r'(?m)^\|[ +]*u_core\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+([\d.]+)', text)
    if len(rows) != 1 or int(rows[0][0]) <= 0:
        raise ValueError('missing, duplicate or invalid CPU hierarchy LUT count')
    row = rows[0]
    return dict(lut=int(row[0]), ff=int(row[1]), distributed_ram=int(row[2]), apm=int(row[3]),
                drm36k_equivalent=float(row[4]))


def load(directory):
    directory = Path(directory).resolve()
    result_path = directory / 'result.json'
    result = json.loads(result_path.read_text(encoding='utf-8'))
    if result.get('status') != 'PASS' or not result.get('source_unchanged') or result.get('stage') != 'map':
        raise ValueError('need unchanged successful native CPU area map evidence')
    for name, digest in result['input_hashes'].items():
        if sha(ROOT / name) != digest or sha(directory / 'src' / name) != digest:
            raise ValueError('CPU area source drift: ' + name)
    for name, digest in result['external_hashes'].items():
        if sha(name) != digest:
            raise ValueError('CPU area external drift: ' + name)
    for name, digest in result['output_hashes'].items():
        if sha(directory / name) != digest:
            raise ValueError('CPU area output drift: ' + name)
    if not result['commands'] or any(row['return_code'] != 0 for row in result['commands']):
        raise ValueError('CPU area native tool failed')
    report = directory / 'synthesize/triha_cpu_board_top.snr'
    review_predictor((directory / 'compile/run.log').read_text(encoding='utf-8'))
    resources = parse_resources(report.read_text(encoding='utf-8'))
    if sha(report) != result['synthesis_report_sha256'] or resources != result['cpu_only_resources']:
        raise ValueError('CPU area report/summary mismatch')
    return dict(directory=str(directory), cpu_core_luts=resources['lut'], resources=resources,
                bound_hashes={str(result_path): sha(result_path), str(report): sha(report)})

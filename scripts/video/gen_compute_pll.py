"""Generate the face-board 125 -> 50 MHz compute PLL from pinned vendor IDF."""
import argparse
from fractions import Fraction
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from common import ROOT, run_logged, sha256, tool, write_json


def create_idf(config, output):
    if (config['schema_version'], config['instance'], config['reference_hz'],
            config['compute_hz']) != (1, 'triha_compute_pll', 125_000_000, 50_000_000):
        raise ValueError('unsupported compute clock contract')
    for key in ('input_divider', 'feedback_multiplier', 'feedback_divider', 'output_divider'):
        if type(config[key]) is not int or not 1 <= config[key] <= 128:
            raise ValueError('invalid divider: ' + key)
    pfd = Fraction(config['reference_hz'], config['input_divider'])
    vco = pfd * config['feedback_multiplier'] * config['feedback_divider']
    if not (10_000_000 <= pfd <= 450_000_000 and 600_000_000 <= vco <= 1_200_000_000):
        raise ValueError('PFD/VCO outside documented range')
    if vco != config['vco_hz'] or vco / config['output_divider'] != config['compute_hz']:
        raise ValueError('actual compute PLL frequency mismatch')
    source = ROOT / config['source']
    manifest = json.loads((ROOT / 'fpga/pg2l100h/ip/video_reference_manifest.json').read_text())
    expected = next(x['sha256'] for x in manifest['references']['hdmi']['files']
                    if x['path'] == 'ipcore/pll/pll.idf')
    if sha256(source) != expected:
        raise ValueError('source PLL IDF hash mismatch')
    tree = ET.parse(source)
    tree.find('header/instance').text = config['instance']
    updates = {'STATIC_RATIOI': config['input_divider'],
               'STATIC_RATIOM': config['feedback_multiplier'],
               'STATIC_RATIO7': config['feedback_divider'],
               'STATIC_DUTY7': config['feedback_divider'],
               'STATIC_RATIO0': config['output_divider'],
               'STATIC_DUTY0': config['output_divider'],
               'CLKOUT0_REQ_FREQ_basicPage': f"{config['compute_hz']/1_000_000:.8f}"}
    for suffix in ('', '_basicPage', '_advancedPage'):
        updates['CLKIN_FREQ' + suffix] = '125.00000000'
        updates['CLKOUT0_EN' + suffix] = 'true'
    updates.update(CLKOUT0_BUFG_EN='true', CLKOUT0_NOBUF_EN='false')
    seen = set()
    for param in tree.findall('./param_list/param'):
        name = param.findtext('name')
        if name in updates:
            param.find('value').text = str(updates[name])
            seen.add(name)
    if seen != set(updates):
        raise ValueError('missing PLL IDF fields: ' + str(set(updates) - seen))
    for file in tree.findall('./file_list/*/file'):
        file.set('pathname', file.get('pathname').replace('pll', config['instance']))
    output.parent.mkdir(parents=True, exist_ok=True)
    tree.write(output, encoding='utf-8', xml_declaration=True)


def generate(output):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False)
    recipe = ROOT / 'fpga/pg2l100h/ip/triha_compute_pll.json'
    config = json.loads(recipe.read_text())
    write_json(output / 'provenance.json', {'status': 'running'})
    try:
        idf = output / 'triha_compute_pll.idf'
        create_idf(config, idf)
        log = run_logged([tool('pds_shell').with_name('ip_generate.exe'), '-i', idf, '-disable-syn'],
                         output / 'generate.log', cwd=output)
        summaries = re.findall(r'\bDone:\s*(\d+) error\(s\),\s*\d+ warning\(s\)', log)
        if not summaries or any(int(n) for n in summaries):
            raise ValueError('compute PLL generator did not report zero errors')
        wrapper = output / 'triha_compute_pll.v'
        text = wrapper.read_text()
        for name, value in {'CLKIN_FREQ': 125, 'STATIC_RATIOI': config['input_divider'],
                            'STATIC_RATIOM': config['feedback_multiplier'],
                            'STATIC_RATIOF': config['feedback_divider'],
                            'STATIC_RATIO0': config['output_divider']}.items():
            match = re.search(r'\b' + name + r'\s*=\s*([0-9.]+)', text)
            if not match or float(match[1]) != value:
                raise ValueError('generated divider mismatch: ' + name)
        write_json(output / 'provenance.json', dict(status='pass', compute_hz=config['compute_hz'],
                   vco_hz=config['vco_hz'], recipe_sha256=sha256(recipe),
                   source_sha256=sha256(ROOT/config['source']), generated_wrapper_sha256=sha256(wrapper),
                   physical_board=False))
        return idf, wrapper
    except Exception as exc:
        write_json(output / 'provenance.json', dict(status='fail', error=str(exc)))
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(generate(args.output.resolve()))

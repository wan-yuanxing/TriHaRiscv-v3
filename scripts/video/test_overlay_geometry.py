"""Cycle-exact overlay geometry regression against a frozen pre-optimization RTL.

The independent Python oracle checks geometry; the miter additionally compares
every output (including reset, blanking and avatar requests) with four-state !==.
All generated inputs, tools, reference and outputs are bound into result.json.
"""
import copy
import importlib.util
import json
import re
import subprocess
import sys

from common import ROOT, BUILD, fresh_run, input_hashes, run_logged, tool, sha256, write_json

REFERENCE = '2463d01adbcb468d4953a4d98628a8d4235035f4'
LEAF = 'rtl/video/display_overlay.sv'


def interface(source):
    header = source.split(');', 1)[0]
    header = header[header.index(')(\n')+3:]
    pattern = r'\b(input|output)\s+(wire|reg)\s*(signed\s+)?(\[\d+:0\])?\s*(.*?)(?=\b(?:input|output)\s+(?:wire|reg)\b|$)'
    found = []
    for m in re.finditer(pattern, header, re.S):
        direction, _, signed, width, names = m.groups()
        for name in names.strip().strip(',').split(','):
            name = name.strip()
            if not re.fullmatch(r'\w+', name):
                raise ValueError('Unparsed port: '+name)
            found.append((direction, (signed or '')+(width or ''), name))
    if len(found) != len(set(n for _, _, n in found)) or not found:
        raise ValueError('Missing/duplicate overlay ports')
    if len(re.findall(r'\b(?:input|output|inout)\b', header)) != len(list(re.finditer(pattern, header, re.S))):
        raise ValueError('Unparsed overlay declaration')
    return found


def miter(source):
    ports = interface(source)
    text = source.split(');', 1)[0].replace('output reg', 'output wire')+');\n'
    for direction, width, name in ports:
        if direction == 'output':
            text += f'wire {width} ref_{name};\n'
    params = ','.join(f'.{n}({n})' for n in
                     ('LINE_WIDTH', 'POINT_RADIUS', 'BOX_COLOR', 'PRIMARY_COLOR', 'POINT_COLOR'))
    for suffix in ('candidate', 'reference'):
        text += f'display_overlay_{suffix} #({params}) u_{suffix}(\n'
        text += ',\n'.join('.'+name+'('+('ref_' if suffix == 'reference' and d == 'output' else '')+name+')'
                           for d, _, name in ports)+');\n'
    text += 'integer cycles=0; always @(posedge clk) begin #1;\n'
    for direction, _, name in ports:
        if direction == 'output':
            text += f'if ({name} !== ref_{name}) $fatal(1,"OVERLAY_MITER_MISMATCH {name} cycle=%0d",cycles);\n'
    return text+'cycles=cycles+1; end\nendmodule\n`default_nettype wire\n'


def geometry_vectors(oracle, line_width, radius):
    configs, events = [], []

    def add_config(c, xs, ys):
        idx = len(configs)
        configs.append(c)
        for y in sorted(set(v for v in ys if 0 <= v <= 2047)):
            for x in sorted(set(v for v in xs if 0 <= v <= 2047)):
                n = len(events)
                events.append((0, idx, 7, x, y, (n*104729) & 0xffffff,
                               1, n % 2, (n//2) % 2, int(n % 97 == 0), 3))

    centers = (-32768, -32, -31, -1, 0, 1, 31, 400, 768, 798, 799, 800, 830, 32767)
    # Isolate each of the 80 point lanes, including all five points on lane 15.
    for lane in range(80):
        c = oracle.base_config()
        face, point = divmod(lane, 5)
        c['boxes'][face] = [0, 0, 800, 600]
        c['points_enable'] = 1
        cx, cy = centers[lane % len(centers)], centers[(lane*3+4) % len(centers)]
        c['points'][face][point] = [cx, cy]
        offsets = (-radius-1, -radius, -1, 0, 1, radius, radius+1)
        add_config(c, [0, 1, 399, 798, 799, 800, 2047]+[cx+d for d in offsets],
                   [0, 1, 299, 598, 599, 600, 2047]+[cy+d for d in offsets])
    boxes = ([-32768, -32768, 32767, 32767], [32767, 0, -32768, 600],
             [-32768, 0, -1, 600], [800, 0, 32767, 600], [0, 600, 800, 32767],
             [-31, -31, 32, 32], [798, 598, 32767, 32767], [10, 10, 11, 11],
             [20, 30, 20, 50], [30, 50, 20, 30], [1, 1, 799, 599], [0, 0, 800, 600])
    for lane in range(16):
        for rect in (boxes[lane % len(boxes)], [0, 0, 800, 600], [20, 30, 760, 570]):
            c = oracle.base_config()
            c['boxes'][lane] = list(rect)
            c['primary'] = lane
            c['points_enable'] = 1
            c['points'][lane] = [[0, 0], [799, 599], [20, 30], [400, 300], [-32768, 32767]]
            x0, y0, x1, y1 = rect
            xs = [0, 1, 2, 399, 400, 798, 799, 800, 2047]
            ys = [0, 1, 2, 299, 300, 598, 599, 600, 2047]
            xs += [x+d for x in (x0, x1) for d in (-line_width-1, -line_width, -1, 0, 1, line_width-1, line_width)]
            ys += [y+d for y in (y0, y1) for d in (-line_width-1, -line_width, -1, 0, 1, line_width-1, line_width)]
            add_config(c, xs, ys)
    for primary in range(16):
        c = oracle.base_config()
        c['boxes'] = [[0, 0, 800, 600] for _ in range(16)]
        c['primary'] = primary
        c['points_enable'] = 1
        c['points'][primary][4] = [799, 599]
        add_config(c, [0, 1, line_width-1, line_width, 799-line_width, 798, 799],
                   [0, 1, line_width-1, line_width, 599-line_width, 598, 599])
    # In-flight resets interrupt different positions within the thirteen stages.
    for phase in range(13):
        events.insert((phase+1)*29, (1, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0))
    return configs, events


def sweep_vectors(oracle, batch):
    configs, events = [], []
    # Four batches cover every possible signed16 value on both coordinate axes.
    for start in range(-32768+batch*16400, min(-32768+(batch+1)*16400, 32768), 80):
        c = oracle.base_config()
        c['boxes'] = [[0, 0, 800, 600] for _ in range(16)]
        c['points_enable'] = 1
        for lane in range(80):
            value = min(start+lane, 32767)
            # Alternate the swept axis; the second configuration swaps axes.
            c['points'][lane//5][lane % 5] = [value, 299]
        for swap in (False, True):
            if swap:
                c = copy.deepcopy(c)
                c['points'] = [[[p[1], p[0]] for p in row] for row in c['points']]
            idx = len(configs)
            configs.append(c)
            values = {0, 1, 2, 30, 31, 32, 298, 299, 300, 598, 599, 600, 767, 768, 798, 799, 800, 2047}
            values.update(v for v in range(start-3, start+83) if 0 <= v <= 800)
            for value in sorted(values):
                x, y = (299, value) if swap else (value, 299)
                n = len(events)
                events.append((0, idx, 7, x, y, n*991 & 0xffffff, 1, n % 2, 0, 0, 0))
    # The existing driver allows 256 records; each half-batch stays below that.
    return configs, events


def write_vectors(directory, oracle, configs, events, name):
    directory.mkdir()
    events.insert(0, (1, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0))
    if len(configs) > 256:
        raise ValueError('Too many file-driver configs')
    (directory/'configs.hex').write_text(''.join(f'{oracle.encode_config(c):0947x}\n' for c in configs), encoding='ascii')
    (directory/'events.hex').write_text(''.join(f'{oracle.encode_event(e):024x}\n' for e in events), encoding='ascii')
    write_json(directory/'vectors.json', dict(case=name, configs=configs, count=len(events), latency_edges=12))


def main():
    work = fresh_run('overlay_geometry')
    latest = BUILD/'latest_overlay_geometry.json'
    result = dict(status='running', directory=work.relative_to(ROOT).as_posix(), reference_commit=REFERENCE,
                  cases=[], mutations=[], physical_board=False, timing_closed=False)
    write_json(latest, result)
    try:
        names = [LEAF, 'rtl/video/avatar_sample_map.sv', 'tb/video/tb_display_overlay.sv',
                 'tb/video/overlay_reference.py', 'scripts/video/test_overlay_geometry.py', 'scripts/video/common.py']
        result['inputs'] = input_hashes(ROOT/n for n in names)
        for name in names:
            dest = work/'src'/name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes((ROOT/name).read_bytes())
        source = (work/'src'/LEAF).read_text(encoding='utf-8')
        reference_bytes = subprocess.check_output(['git', 'show', REFERENCE+':'+LEAF], cwd=ROOT)
        (work/'reference_original.sv').write_bytes(reference_bytes)
        reference = reference_bytes.decode('utf-8')
        if interface(source) != interface(reference):
            raise ValueError('Overlay interface changed')
        result['reference_sha256'] = sha256(work/'reference_original.sv')
        result['compared_outputs'] = [n for d, _, n in interface(source) if d == 'output']
        for suffix, value in [('reference', reference), ('candidate', source)]:
            value, count = re.subn(r'\bmodule display_overlay\b', 'module display_overlay_'+suffix, value)
            if count != 1:
                raise ValueError('Module rename anchor changed')
            (work/(suffix+'.sv')).write_text(value, encoding='utf-8')
        (work/'miter.sv').write_text(miter(source), encoding='utf-8')
        spec = importlib.util.spec_from_file_location('overlay_reference', work/'src/tb/video/overlay_reference.py')
        oracle = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(oracle)
        cc, runtime = tool('iverilog'), tool('vvp')
        result['tools'] = {str(p): sha256(p) for p in (cc, runtime)}
        for n, p in [('iverilog', cc), ('vvp', runtime)]:
            run_logged([p, '-V'], work/(n+'_version.log'))

        def compile_sim(label, width, radius, vectors, candidate, negative=False, driver=None):
            binary = work/(label+'.vvp')
            run_logged([cc, '-g2012', '-s', 'tb_display_overlay', '-o', binary,
                        '-Ptb_display_overlay.LINE_WIDTH='+str(width), '-Ptb_display_overlay.POINT_RADIUS='+str(radius),
                        work/'src/rtl/video/avatar_sample_map.sv', work/'reference.sv', candidate, work/'miter.sv',
                        driver or work/'src/tb/video/tb_display_overlay.sv'], work/(label+'_compile.log'))
            p = subprocess.run([runtime, binary, '+DIRECTORY='+vectors.as_posix()], cwd=ROOT,
                               capture_output=True, timeout=600)
            (work/(label+'_simulation.log')).write_bytes(p.stdout+p.stderr)
            if negative:
                if p.returncode == 0 or b'OVERLAY_MITER_MISMATCH' not in p.stdout+p.stderr:
                    raise ValueError('Compiled fault escaped miter: '+label)
            elif p.returncode or p.stdout.count(b'DISPLAY_OVERLAY_DRIVER_PASS') != 1:
                raise ValueError('Miter failed '+label+': '+(p.stdout+p.stderr).decode(errors='replace')[-1500:])
            else:
                run_logged([sys.executable, work/'src/tb/video/overlay_reference.py', 'check', '--directory', vectors,
                            '--line-width', width, '--point-radius', radius], work/(label+'_oracle.log'))
            return dict(name=label, status='rejected' if negative else 'pass', exit_code=p.returncode,
                        events=len((vectors/'events.hex').read_text(encoding='ascii').splitlines()))

        for width, radius in ((2, 2), (1, 0), (800, 31), (3, 31), (799, 1)):
            label = f'geometry_{width}_{radius}'
            vectors = work/label
            write_vectors(vectors, oracle, *geometry_vectors(oracle, width, radius), label)
            result['cases'].append(compile_sim(label, width, radius, vectors, work/'candidate.sv'))
        # 16400 coordinates need 410 records with both axes; split into eight files.
        for batch in range(4):
            configs, events = sweep_vectors(oracle, batch)
            for half in range(2):
                lo, hi = half*206, min((half+1)*206, len(configs))
                if lo >= hi:
                    continue
                sliced = [tuple([e[0], e[1]-lo, *e[2:]]) for e in events if lo <= e[1] < hi]
                label = f'signed16_{batch}_{half}'
                vectors = work/label
                write_vectors(vectors, oracle, configs[lo:hi], sliced, label)
                result['cases'].append(compile_sim(label, 2, 2, vectors, work/'candidate.sv'))
        # Unknown record fields must be suppressed exactly like the frozen RTL.
        # Keep the numeric oracle independent: it models those lanes as absent.
        configs = [oracle.base_config() for _ in range(4)]
        for idx in (0, 3):
            configs[idx]['boxes'] = [[0, 0, 800, 600] for _ in range(16)]
        for c in configs:
            c['points_enable'] = 1
        events = [(0, idx, 7, x, y, 0x123456, 1, 0, 0, 0, 0)
                  for _ in range(8) for idx in range(4)
                  for y in (0, 1, 299, 300, 599, 600)
                  for x in (0, 1, 399, 400, 799, 800)]
        vectors = work/'four_state'
        write_vectors(vectors, oracle, configs, events, 'four_state')
        driver = (work/'src/tb/video/tb_display_overlay.sv').read_text(encoding='utf-8')
        anchor = 'config_word = configs[config_id];'
        if driver.count(anchor) != 1:
            raise ValueError('Four-state driver anchor changed')
        injection = '''
            // Packed offsets follow the checked 3787-bit config interface.
            case (config_id)
              0: begin
                config_word[2625+:80]={80{1'b1}};
                config_word[1345+:1280]={1280{1'bx}};
                config_word[65+:1280]={1280{1'bx}};
              end
              1: begin
                config_word[3729+:16]={16{1'bx}};
                config_word[2961+:256]={16{16'd800}};
                config_word[2705+:256]={16{16'd600}};
              end
              2: begin
                config_word[3729+:16]=16'hffff;
                config_word[2705+:1024]={1024{1'bx}};
              end
              3: begin
                config_word[2625+:80]={80{1'bx}};
                config_word[1345+:1280]={80{16'd400}};
                config_word[65+:1280]={80{16'd300}};
              end
            endcase
        '''
        driver_path = work/'four_state_driver.sv'
        driver_path.write_text(driver.replace(anchor, anchor+injection), encoding='utf-8')
        result['cases'].append(compile_sim('four_state', 2, 2, vectors, work/'candidate.sv', driver=driver_path))
        for name in ('qualification', 'dynamic', 'avatar_edges', 'fault_reset', 'blanking'):
            label = 'reference_'+name
            vectors = work/label
            oracle.generate(vectors, name)
            result['cases'].append(compile_sim(label, 2, 2, vectors, work/'candidate.sv'))
        # Each mutation is compiled, executes real pixels and must fail comparison.
        candidate = (work/'candidate.sv').read_text(encoding='utf-8')
        mutations = [('point_color', 'selected_rgb=POINT_COLOR;', 'selected_rgb=BOX_COLOR;'),
                     ('last_column', 'pixel_x<800', 'pixel_x<799'),
                     ('primary_priority', 'primary_hit ? PRIMARY_COLOR : BOX_COLOR', 'BOX_COLOR')]
        if 'point_px>=point_x_lo' in candidate:
            mutations += [('point_inclusive', 'point_px>=point_x_lo', 'point_px>point_x_lo'),
                          ('box_exclusive', 'right<=border_x_hi', 'right<border_x_hi'),
                          ('point_unsigned', 'point_px>=point_x_lo', '$unsigned(point_px)>=$unsigned(point_x_lo)')]
        for label, old, new in mutations:
            if candidate.count(old) != 1:
                raise ValueError('Mutation anchor changed: '+label)
            path = work/(label+'.sv')
            path.write_text(candidate.replace(old, new), encoding='utf-8')
            # A failing run truncates pixels.log. Never let it overwrite the
            # already checked positive evidence, even if its vectors are equal.
            vectors = work/('mutation_'+label)
            vectors.mkdir()
            for name in ('configs.hex', 'events.hex', 'vectors.json'):
                (vectors/name).write_bytes((work/'geometry_2_2'/name).read_bytes())
            result['mutations'].append(compile_sim(label, 2, 2, vectors, path, True))
        if any(sha256(ROOT/n) != h for n, h in result['inputs'].items()):
            raise ValueError('Inputs changed during geometry tests')
        result['artifacts'] = input_hashes(p for p in work.rglob('*') if p.is_file())
        result['status'] = 'pass'
    except Exception as error:
        result.update(status='fail', error=str(error))
        print(str(error), file=sys.stderr)
    write_json(work/'result.json', result)
    write_json(latest, result)
    print('OVERLAY_GEOMETRY_'+result['status'].upper(), work)
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())

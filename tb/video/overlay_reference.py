"""Independent mathematical oracle and file vectors for the F3b pixel pipeline.

The SV driver supplies pixels and a synchronous procedural texture, never expected
colors. This oracle uses clipped sets, unmodified target rectangles and Python
integer division, independently of the RTL's fractional divider/blend pipeline.
"""
import argparse
import copy
import json
from pathlib import Path
import random

CASES = ('qualification', 'boxes', 'points', 'avatar_edges', 'dynamic',
         'fault_reset', 'blanking', 'texture_1to1', 'alpha', 'full')
CONFIG_WIDTH = 3787
EVENT_WIDTH = 93
LATENCY = 12  # Input edge n -> output edge n+12, thirteen register stages.


def pack(fields):
    value = 0
    for width, item in fields:
        value = (value << width) | (item & ((1 << width) - 1))
    return value


def base_config():
    return dict(mode=1, valid=1, has_face=1, result_frame=7, primary_valid=1,
                primary=0, points_enable=0, boxes=[None]*16,
                points=[[None]*5 for _ in range(16)], avatar_enable=1,
                target=[0, 0, 800, 600])


def encode_config(c):
    boxes = c['boxes']
    points = [p for face in c['points'] for p in face]
    fields = [(2, c['mode']), (1, c['valid']), (1, c['has_face']),
              (32, c['result_frame']), (1, c['primary_valid']),
              (4, c['primary']), (1, c['points_enable']),
              (16, sum((b is not None) << i for i, b in enumerate(boxes)))]
    # Lane zero occupies the low slice of each packed bus.
    fields += [(256, pack([(16, (b or [0]*4)[axis]) for b in reversed(boxes)]))
               for axis in range(4)]
    fields += [(80, sum((p is not None) << i for i, p in enumerate(points)))]
    fields += [(1280, pack([(16, (p or [0, 0])[axis]) for p in reversed(points)]))
               for axis in range(2)]
    fields += [(1, c['avatar_enable'])] + [(16, v) for v in c['target']]
    assert sum(w for w, _ in fields) == CONFIG_WIDTH
    return pack(fields)


def encode_event(e):
    return pack(zip((1, 8, 32, 11, 11, 24, 1, 1, 1, 1, 2), e))


def decode_event(v):
    fields = []
    for width in reversed((1, 8, 32, 11, 11, 24, 1, 1, 1, 1, 2)):
        fields.append(v & ((1 << width)-1))
        v >>= width
    assert v == 0
    return tuple(reversed(fields))


def texture(sx, sy):
    return ((37*sx+13*sy+17) % 256, (sx ^ (sy*7)) % 256,
            (255-sx+11*sy) % 256, (sx+3*sy) % 256)


def reference(c, e, line_width=2, point_radius=2):
    _, _, frame, x, y, rgb, de, _, _, _, behavior = e
    flags = [0, 0, 0, 0]  # box, point, avatar selected, fault
    address = None
    if not (de and x < 800 and y < 600 and c['valid'] and c['has_face']
            and frame == c['result_frame']):
        return rgb, flags, address
    if c['mode'] == 1:
        borders = []
        point_hit = False
        for i, box in enumerate(c['boxes']):
            if box is None:
                continue
            left, top = max(0, box[0]), max(0, box[1])
            right, bottom = min(800, box[2]), min(600, box[3])
            if left >= right or top >= bottom:
                continue
            if left <= x < right and top <= y < bottom:
                if min(x-left, right-1-x, y-top, bottom-1-y) < line_width:
                    borders.append(i)
            if c['points_enable']:
                point_hit |= any(p is not None and max(abs(x-p[0]), abs(y-p[1]))
                                 <= point_radius for p in c['points'][i])
        if point_hit:
            rgb, flags[1] = 0xffff00, 1
        elif borders:
            rgb = 0xff0000 if c['primary_valid'] and c['primary'] in borders else 0x00ff00
            flags[0] = 1
    elif c['mode'] == 2 and c['avatar_enable']:
        x0, y0, x1, y1 = c['target']
        if x0 <= x < x1 and y0 <= y < y1:
            sx = ((x-x0)*256)//(x1-x0)
            sy = ((y-y0)*256)//(y1-y0)
            address = 4*(sy*256+sx)
            if behavior in (1, 2):
                flags[3] = 1
            else:
                r, g, b, a = texture(sx, sy)
                channels = [(rgb >> shift) & 255 for shift in (16, 8, 0)]
                rgb = pack([(8, (a*f+(255-a)*back+127)//255)
                            for f, back in zip((r, g, b), channels)])
                flags[2] = 1
    return rgb, flags, address


def generate(directory, case):
    directory.mkdir(parents=True, exist_ok=True)
    configs = [base_config()]
    c = configs[0]
    c['boxes'] = [[2, 2, 31, 21], [-4, -3, 5, 6], [795, 595, 810, 610],
                  [20, 0, 20, 10], [40, 20, 30, 22], [32760, 0, 32767, 600],
                  [-32768, -32768, 32767, 32767], [10, 8, 40, 26],
                  [100, 100, 101, 101], [200, 200, 201, 230], [0, 599, 800, 600],
                  [799, 0, 800, 600], [-10, -10, -1, -1], [32, 20, 35, 23],
                  [22, 12, 29, 17], [4, 5, 35, 24]]
    for i in range(16):
        c['points'][i] = [[2+i, 3+i], [797, 598], [0, 0], [799, 599], None]
    c['points'][0] = [[-1, 0], [799, 600], [-32768, 32767], [32767, -32768], [2, 2]]
    c['points'][15] = [[20, 18], [21, 19], [22, 20], [23, 21], [24, 22]]
    rng = random.Random(0x53424633)
    events = []

    def add(x, y, cfg=0, frame=7, de=1, behavior=0, reset=0, rgb=None):
        i = len(events)
        if rgb is None:
            rgb = ((i*104729) ^ (x*991+y*65537)) & 0xffffff
        events.append((reset, cfg, frame, x, y, rgb, de, int(i % 11 < 5),
                       int(i % 23 < 13), int(i % 97 == 0), behavior))

    def clone(**changes):
        v = copy.deepcopy(c)
        v.update(changes)
        configs.append(v)
        return len(configs)-1

    add(0, 0, reset=1)
    if case in ('qualification', 'dynamic', 'blanking'):
        clone(mode=0)
        clone(mode=2)
        clone(mode=3)
        clone(valid=0)
        clone(has_face=0)
        clone(result_frame=8)
        clone(mode=2, avatar_enable=0)
        clone(points_enable=1)
        for i in range(8000):
            add((0, 2, 10, 30, 798, 799)[(i//9) % 6] if case == 'qualification' else
                rng.randrange(2048 if case == 'blanking' else 800),
                (0, 2, 10, 20, 598, 599)[(i//54) % 6] if case == 'qualification' else
                rng.randrange(2048 if case == 'blanking' else 600),
                cfg=i % len(configs), frame=8 if i % 7 == 0 else 7,
                de=int(i % 5 != 0), behavior=i % 4)
    elif case in ('boxes', 'points'):
        clone(primary=15, points_enable=1)
        clone(primary_valid=0, points_enable=1)
        clone(points_enable=0)
        coords = [(x, y) for y in range(30) for x in range(44)]
        coords += [(x, y) for y in (0, 1, 2, 297, 598, 599, 600)
                   for x in range(801)]
        coords += [(x, y) for x in (0, 1, 2, 398, 798, 799, 800)
                   for y in range(601)]
        if case == 'points':
            coords += [(x, y) for y in range(45) for x in range(45)]
        for cfg in range(len(configs)):
            for x, y in coords:
                add(x, y, cfg)
    elif case == 'avatar_edges':
        targets = [[-91, -63, 163, 127], [730, 520, 930, 720],
                   [-32768, -32768, 32767, 32767], [799, 599, 800, 600],
                   [0, 0, 1, 1], [20, 30, 11, 31], [40, 10, 40, 200],
                   [18, 21, 33, 39], [-2, -1, 2, 3], [0, 0, 800, 600],
                   [32767, 0, -32768, 600], [-32768, 0, -32767, 600]]
        for target in targets:
            cfg = clone(mode=2, target=target)
            for y in (0, 1, 2, 20, 21, 29, 30, 38, 39, 126, 127, 519, 520, 598, 599, 600):
                for x in (0, 1, 2, 17, 18, 19, 20, 32, 33, 162, 163, 729, 730, 798, 799, 800):
                    add(x, y, cfg)
            for _ in range(1000):
                add(rng.randrange(800), rng.randrange(600), cfg)
        for _ in range(80):
            left, top = rng.randrange(-32768, 800), rng.randrange(-32768, 600)
            cfg = clone(mode=2, target=[left, top, rng.randrange(left+1, 32768),
                                       rng.randrange(top+1, 32768)])
            for _ in range(100):
                add(rng.randrange(800), rng.randrange(600), cfg)
    elif case == 'fault_reset':
        cfg = clone(mode=2)
        for i in range(2400):
            # Every pipeline phase is cut at least once; long spans also retire faults.
            add(i % 800, i % 600, cfg, behavior=(i//31) % 4,
                reset=int(i % 127 in (0, 1) or i % 83 == 0))
    elif case in ('full', 'texture_1to1', 'alpha'):
        w, h = (800, 600) if case == 'full' else (256, 256)
        cfg = clone(mode=2, target=[0, 0, w, h])
        for y in range(h):
            for x in range(w):
                add(x, 0 if case == 'alpha' else y, cfg,
                    rgb=y*0x010101 if case == 'alpha' else None)
            for x in range(4):
                add(800+x, y, cfg, de=0, behavior=3)
    else:
        raise ValueError(case)
    (directory/'configs.hex').write_text(''.join(f'{encode_config(v):0947x}\n' for v in configs), encoding='ascii')
    (directory/'events.hex').write_text(''.join(f'{encode_event(e):024x}\n' for e in events), encoding='ascii')
    (directory/'vectors.json').write_text(json.dumps(dict(case=case, configs=configs,
        count=len(events), latency_edges=LATENCY), indent=2)+'\n', encoding='utf-8')
    print('OVERLAY_VECTORS_READY', case, len(events))


def check(directory, line_width=2, point_radius=2):
    info = json.loads((directory/'vectors.json').read_text(encoding='utf-8'))
    configs = info['configs']
    events = [decode_event(int(v, 16)) for v in (directory/'events.hex').read_text().split()]
    expected_pixels, expected_requests = {}, {}
    epoch = 0
    for i, e in enumerate(events):
        if e[0]:
            epoch += 1
            continue
        if not any(v[0] for v in events[i+1:i+LATENCY+1]):
            expected_pixels[i] = epoch
        if not any(v[0] for v in events[i+1:i+10]):
            expected_requests[i] = True
    observed = set()
    request_ids = set()
    sticky = 0
    previous_epoch = None
    counts = dict(pixels=0, requests=0, box=0, point=0, avatar=0, fault=0)
    for line in (directory/'pixels.log').read_text().splitlines():
        p = line.split()
        if not p:
            continue
        i = int(p[1])
        e = events[i]
        rgb, flags, addr = reference(configs[e[1]], e, line_width, point_radius)
        if p[0] == 'Q':
            assert i in expected_requests and i not in request_ids, f'unexpected request slot {i}'
            request_ids.add(i)
            got = tuple(int(v, 16) for v in p[2:])
            assert got[0] == int(addr is not None), f'avatar request presence {i}: {got}, expected {addr}'
            if addr is not None:
                assert got[1] == addr, f'avatar address {i}: {got[1]} expected {addr}'
                counts['requests'] += 1
        elif p[0] == 'P':
            assert i in expected_pixels and i not in observed, f'unexpected retired pixel {i}'
            observed.add(i)
            if previous_epoch != expected_pixels[i]:
                sticky = 0
            previous_epoch = expected_pixels[i]
            sticky |= flags[3]
            want = (e[2], e[3], e[4], *e[6:10], rgb, *flags, sticky)
            got = tuple(int(v, 16) for v in p[2:])
            assert got == want, f'pixel {i}: got {got}, expected {want}'
            counts['pixels'] += 1
            for name, hit in zip(('box', 'point', 'avatar', 'fault'), flags):
                counts[name] += hit
        else:
            raise AssertionError('Unexpected dump record: '+line)
    assert observed == set(expected_pixels), 'Missing or extra retired pixels'
    assert request_ids == set(expected_requests), 'Missing or extra request slots'
    (directory/'checked.json').write_text(json.dumps(dict(status='pass', case=info['case'],
        counts=counts), indent=2)+'\n', encoding='utf-8')
    print('DISPLAY_OVERLAY_ORACLE_PASS', info['case'], counts)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('generate', 'check'))
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--case', choices=CASES)
    parser.add_argument('--line-width', type=int, default=2)
    parser.add_argument('--point-radius', type=int, default=2)
    args = parser.parse_args()
    if args.action == 'generate':
        generate(args.directory, args.case)
    else:
        check(args.directory, args.line_width, args.point_radius)

"""Measure distinct source-frame presentations in a contiguous 800x600 output capture."""
import argparse
from fractions import Fraction
import json
from pathlib import Path
import statistics

from PIL import Image


def read_id(path):
    with Image.open(path) as img:
        if img.size != (800, 600):
            raise ValueError(f'{path.name}: expected the unscaled 800x600 output')
        gray = img.crop((0, 4, 184, 20)).convert('L')
        bits = []
        for i in range(36):
            # Use centres of the blocks to tolerate minor compression at edges.
            value = statistics.median(gray.crop((5+5*i, 4, 8+5*i, 12)).getdata())
            if 70 < value < 180:
                raise ValueError(f'{path.name}: ambiguous marker cell {i}')
            bits.append(int(value >= 180))
    if bits[:4] != [1, 0, 1, 0] or any(a == b for a, b in zip(bits[4:20], bits[20:])):
        raise ValueError(f'{path.name}: sync/complement mismatch')
    return int(''.join(map(str, bits[4:20])), 2)


def measure(frames, rate):
    if rate <= 0:
        raise ValueError('Capture rate must be positive')
    changes = []
    last = None
    for i, path in enumerate(frames):
        current = read_id(path)
        if last is not None and current != last:
            if (current-last) % 65536 >= 32768:
                raise ValueError(f'{path.name}: discontinuity or out-of-order input IDs')
            changes.append(i)
        last = current
    if len(changes) < 2:
        raise ValueError('Need at least two observed transitions; capture a longer sequence')
    # Exclude the unknown duration of the first and last displayed image.
    duration = (changes[-1]-changes[0])/rate
    return dict(metric='distinct_source_frame_presentations_per_second',
                capture_hz=str(rate), capture_frames=len(frames),
                complete_intervals=len(changes)-1, measured_seconds=float(duration),
                visible_updates_per_second=float((len(changes)-1)/duration),
                note='Observed at capture resolution; this does not count internal NPU completions.')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--frames', type=Path, required=True, help='Directory containing 0.png, 1.png, ... or padded numbers')
    ap.add_argument('--capture-hz', type=Fraction, required=True, help='Actual constant capture rate, e.g. 60 or 60000/1001')
    args = ap.parse_args()
    try:
        paths = list(args.frames.glob('*.png'))
        if not paths or any(not p.stem.isascii() or not p.stem.isdecimal() for p in paths):
            raise ValueError('Expected a nonempty directory of numbered PNG capture frames')
        paths.sort(key=lambda p:int(p.stem))
        ids = [int(p.stem) for p in paths]
        if ids != list(range(ids[0], ids[0]+len(ids))):
            raise ValueError('Duplicate or missing capture frames')
        print(json.dumps(measure(paths, args.capture_hz), indent=2))
    except (OSError, ValueError) as error:
        ap.exit(1, str(error)+'\n')


if __name__ == '__main__':
    main()

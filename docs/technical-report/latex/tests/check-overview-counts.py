"""Count visible first-part text, including footnotes and table contents.

Each Han character, English/alphanumeric word, number, punctuation mark and
mathematical symbol counts as one. Repeated continuation headers, LaTeX syntax,
automatic numbering and text embedded in unchanged image assets are excluded.
Image text is audited separately in the revision report; no prose is moved into
an image to meet a limit. Also report raw non-whitespace characters for comparison.
"""
from pathlib import Path
import argparse
import json
import re

def braced(text, start):
    assert text[start] == '{'
    depth = 1
    i = start + 1
    while depth:
        if text[i] == '{' and text[i - 1] != '\\':
            depth += 1
        elif text[i] == '}' and text[i - 1] != '\\':
            depth -= 1
        i += 1
    return text[start + 1:i - 1], i

def visible(source):
    source = re.sub(r'(?m)(?<!\\)%.*$', '', source)
    source = re.sub(r'\\endfirsthead.*?\\endhead', '', source, flags=re.S)
    out = []
    i = 0
    while i < len(source):
        c = source[i]
        if c != '\\':
            out.append(' ' if c in '{}$&' else c)
            i += 1
            continue
        i += 1
        if i >= len(source):
            break
        if not source[i].isalpha():
            out.append(source[i] if source[i] in '%_#&' else ' ')
            i += 1
            continue
        match = re.match(r'[A-Za-z]+\*?', source[i:])
        cmd = match.group(0)
        i += len(cmd)
        while i < len(source) and source[i].isspace():
            i += 1
        while i < len(source) and source[i] == '[':
            i = source.index(']', i) + 1
        if cmd in ('begin', 'end'):
            env, i = braced(source, i)
            if cmd == 'begin' and env in ('longtable', 'tabular'):
                _, i = braced(source, i)
            elif cmd == 'begin' and i < len(source) and source[i] == '[':
                i = source.index(']', i) + 1
            out.append(' ')
        elif cmd in ('label', 'includegraphics', 'input', 'setlength', 'addcontentsline'):
            count = {'setlength': 2, 'addcontentsline': 3}.get(cmd, 1)
            for _ in range(count):
                while i < len(source) and source[i].isspace():
                    i += 1
                _, i = braced(source, i)
        elif cmd in ('ref', 'pageref', 'cite', 'citep'):
            arg, i = braced(source, i)
            out.append(' 1 ' * len(arg.split(',')))
        elif cmd in ('times', 'approx', 'pm', 'leq', 'geq'):
            out.append({'times': '×', 'approx': '≈', 'pm': '±', 'leq': '≤', 'geq': '≥'}[cmd])
        elif cmd in ('small', 'footnotesize', 'centering', 'toprule', 'midrule',
                     'bottomrule', 'endfoot', 'endlastfoot', 'endhead', 'endfirsthead',
                     'item', 'par', 'noindent', 'arraybackslash', 'raggedright', 'FloatBarrier'):
            out.append(' ')
        # Formatting commands retain their braced text on subsequent iterations.
    return re.sub(r'\s+', ' ', ''.join(out)).strip()

def count(text):
    # Long Latin words and numeric values remain single words, as in normal
    # mixed Chinese/English word counts; punctuation is counted conservatively.
    tokens = re.findall(r'[\u3400-\u9fff]|[+-]?\d+(?:,\d{3})*(?:\.\d+)?|[A-Za-z][A-Za-z0-9]*(?:[-_][A-Za-z0-9]+)*|[^\s]', text)
    return {
        'han_characters': len(re.findall(r'[\u3400-\u9fff]', text)),
        'conservative_units': len(tokens),
        'non_whitespace_characters': len(re.sub(r'\s', '', text)),
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    rows = []
    for n, path in enumerate(sorted((root / 'chapters/01-overview').glob('*.tex')), 1):
        source = path.read_text(encoding='utf-8-sig')
        text = visible(source)
        row = {'section': f'1.{n}', 'file': path.relative_to(root).as_posix(),
               'limit': 400 if n <= 3 else 200, **count(text), 'visible_text': text}
        row['pass'] = row['conservative_units'] <= row['limit']
        rows.append(row)
    metrics = (root / 'chapters/01-overview/04-主要性能指标.tex').read_text(encoding='utf-8')
    assert metrics.count('\\begin{longtable}') == 2, 'Section 1.4 must contain two tables.'
    result = {'rule': __doc__.strip(), 'sections': rows, 'all_pass': all(r['pass'] for r in rows)}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    for row in rows:
        print(f"{row['section']}: {row['conservative_units']}/{row['limit']} units, {row['han_characters']} Han, {row['non_whitespace_characters']} characters: {'PASS' if row['pass'] else 'FAIL'}")
    raise SystemExit(0 if result['all_pass'] else 1)

if __name__ == '__main__':
    main()
